import 'chat_models.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'account.dart';
import 'preferences.dart';
import 'relay_transport.dart';
import 'node_data.dart';
import 'json.dart';
import 'flow.dart';
import 'endpoints.dart';

class NekodotClient extends ChangeNotifier {
  final AccountSession account;
  final prefs = ClientPreferences();
  late final RelayTransport connection;
  NekodotClient({
    String server = const String.fromEnvironment(
      'RELAY_URL',
      defaultValue: officialApiUrl,
    ),
    http.Client? transport,
    FlutterSecureStorage? vault,
  }) : account = AccountSession(
         server: server,
         transport: transport,
         vault: vault,
       ) {
    connection = RelayTransport(
      endpoint: account.wsUrl('/ws/client'),
      token: () => account.token,
      tr: tr,
      onEvent: _receive,
      onReady: () {
        error = '';
        unawaited(refreshMe());
        if (selectedNodeId != null && node.online) {
          unawaited(synchronize(selectedNodeId!));
        }
      },
      onUnauthorized: () => unawaited(clearSession()),
      onError: (value) {
        error = value;
      },
    );
    account.addListener(notifyListeners);
    prefs.addListener(notifyListeners);
    connection.addListener(notifyListeners);
  }
  String? selectedNodeId, visibleConversation;
  String error = '';
  bool _closed = false;
  final nodes = <String, NodeData>{};
  final Map<String, List<Json>> attachmentDrafts = {};
  final drafts = <String, String>{};
  final routineDrafts = <String, Json>{};
  final notifications = StreamController<Json>.broadcast();
  final destinations = StreamController<Json>.broadcast();
  Json? pendingDestination;
  String notificationStatus = '', notificationError = '';
  NodeData get node => nodes.putIfAbsent(selectedNodeId ?? '', NodeData.new);
  bool get online => connection.ready && node.online;
  bool get zh => prefs.language == 'zh';
  String tr(String cn, String en) => zh ? cn : en;
  Future<void> initialize() async {
    await prefs.load();
    selectedNodeId = (await SharedPreferences.getInstance()).getString('node');
    await account.load();
    if (account.token != null) await bootstrap();
  }

  Future<void> acceptSession(Json result) async {
    await account.accept(result);
    await bootstrap();
  }

  Future<Json> rpc(String method, [Json params = const {}, String? target]) =>
      connection.rpc(method, params, target ?? selectedNodeId);
  Future<void> login(String email, String password) async {
    final result = await account.request(
      '/auth/login',
      method: 'POST',
      body: {'email': email, 'password': password},
    );
    await acceptSession(result);
  }

  Future<void> bootstrap() async {
    try {
      account.me = await account.request('/me');
      final available = objects(account.me!['nodes']);
      for (final n in available) {
        nodes.putIfAbsent(n['nodeId'] as String, NodeData.new).online =
            n['online'] == true;
      }
      if (!available.any((n) => n['nodeId'] == selectedNodeId)) {
        selectedNodeId = available.firstOrNull?['nodeId'] as String?;
      }
      error = '';
      await connection.connect();
    } on RelayError catch (e) {
      if (e.status == 401) {
        account.token = null;
        await account.clear();
      }
      error = e.message;
    }
    notifyListeners();
  }

  Future<void> refreshMe() async {
    final session = account.token;
    if (session == null) return;
    try {
      final value = await account.request('/me');
      if (_closed || account.token != session) return;
      account.me = value;
    } catch (e) {
      if (_closed || account.token != session) return;
      error = '$e';
    }
    notifyListeners();
  }

  Future<void> logout() async {
    await account.request('/auth/logout', method: 'POST', body: {});
    await clearSession();
  }

  Future<void> selectNode(String id) async {
    selectedNodeId = id;
    await (await SharedPreferences.getInstance()).setString('node', id);
    notifyListeners();
    if (connection.ready && node.online) await synchronize(id);
  }

  void openNotification(Json signal) {
    pendingDestination = signal;
    destinations.add(signal);
  }

  void setNotificationState({String? status, String? failure}) {
    notificationStatus = status ?? notificationStatus;
    notificationError = failure ?? notificationError;
    notifyListeners();
  }

  Future<void> synchronize(String id) async {
    final n = nodes.putIfAbsent(id, NodeData.new);
    if (n.syncing) return;
    n.syncing = true;
    try {
      final result = await rpc(
        n.seq == 0 ? 'sync.snapshot' : 'sync.since',
        n.seq == 0 ? {} : {'seq': n.seq},
        id,
      );
      if (n.seq == 0) {
        n.snapshot(result);
      } else if (result['resyncRequired'] == true) {
        n.snapshot(await rpc('sync.snapshot', {}, id));
      } else {
        for (final event in objects(result['events'])) {
          n.update({'type': 'event', 'payload': event});
        }
      }
      for (final c in n.conversations) {
        if (n.messages.containsKey(c['conversationId'])) {
          await loadMessages(c['conversationId'] as String, target: id);
        }
      }
      final events = n.buffer.where((x) => x['type'] == 'event').toList()
        ..sort(
          (a, b) => (a['payload']['seq'] as int).compareTo(
            b['payload']['seq'] as int,
          ),
        );
      for (final event in [
        ...events,
        ...n.buffer.where((x) => x['type'] == 'live'),
      ]) {
        n.update(event);
      }
      n.buffer.clear();
      error = '';
    } catch (e) {
      error = '$e';
    } finally {
      n.syncing = false;
      n.notifySnapshot();
    }
  }

  Future<void> loadMessages(
    String conversationId, {
    String? target,
    int? before,
    String? around,
  }) async {
    final id = target ?? selectedNodeId!;
    final n = nodes.putIfAbsent(id, NodeData.new);
    final opened = n.messages[conversationId];
    if (opened == null) return;
    final result = await rpc('messages.list', {
      'conversationId': conversationId,
      'limit': 50,
      'beforeSeq': ?before,
      'aroundMessageId': ?around,
    }, id);
    // A response for a page that has closed must not recreate its cache.
    if (!identical(n.messages[conversationId], opened)) return;
    final previous = opened;
    final merged = <String, ChatMessage>{
      for (final m in previous) m.messageId: m,
    };
    for (final m in objects(result['messages'])) {
      merged[m['messageId'] as String] = ChatMessage.fromJson(m);
    }
    opened
      ..clear()
      ..addAll(merged.values)
      ..sort((a, b) => (a.seq).compareTo(b.seq));
    n.changed(conversationId, summary: true);
  }

  Future<void> loadFlow(String conversationId) async {
    final target = selectedNodeId!;
    final n = node;
    final requestedAt = n.seq;
    final response = await rpc('flow.get', {
      'conversationId': conversationId,
    }, target);
    final value = response['flow'];
    final current = n.flows[conversationId];
    if (value == null) {
      if (current == null || current.seq <= requestedAt) {
        n.flows.remove(conversationId);
      }
    } else {
      final flow = FlowSnapshot.fromJson(object(value));
      if (current == null || current.seq <= flow.seq) {
        n.flows[conversationId] = flow;
      }
    }
    n.changed(conversationId);
  }

  Future<void> send(String conversationId, String text) async {
    await rpc('messages.send', {
      'conversationId': conversationId,
      'text': text,
      'clientMsgId': uid(),
    });
    drafts.remove(conversationId);
  }

  /// Desktop reports this on every window focus, so a live connection is kept.
  void resume() {
    connection.active = true;
    if (connection.live) {
      unawaited(refreshMe());
    } else {
      unawaited(bootstrap());
    }
  }

  void pause() {
    connection.active = false;
  }

  void _receive(Json frame) {
    final p = object(frame['payload']), id = frame['nodeId'] as String?;
    switch (frame['type']) {
      case 'node.status':
        if (id == null) return;
        nodes.putIfAbsent(id, NodeData.new).online = p['online'] == true;
        for (final n in (account.me?['nodes'] as List? ?? [])) {
          if (n['nodeId'] == id) n['online'] = p['online'];
        }
        if (p['online'] == true) unawaited(refreshMe());
        if (id == selectedNodeId && p['online'] == true) {
          unawaited(synchronize(id));
        }
      case 'event':
      case 'live':
        if (id == null) return;
        final n = nodes.putIfAbsent(id, NodeData.new);
        if (n.syncing) {
          n.buffer.add(frame);
        } else {
          n.update(frame);
        }
        return;
      case 'notify':
        if (id != null) notifications.add({...p, 'nodeId': id});
      case 'error':
        error = '${p['message']}';
    }

    notifyListeners();
  }

  Future<void> clearSession() async {
    account.token = null;
    await connection.disconnect();
    await account.clear();
    for (final n in nodes.values) {
      n.dispose();
    }
    nodes.clear();
    drafts.clear();
    routineDrafts.clear();
    attachmentDrafts.clear();
    selectedNodeId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    account.removeListener(notifyListeners);
    prefs.removeListener(notifyListeners);
    connection.removeListener(notifyListeners);
    connection.dispose();
    account.dispose();
    prefs.dispose();
    for (final n in nodes.values) {
      n.dispose();
    }
    notifications.close();
    destinations.close();
    super.dispose();
  }
}
