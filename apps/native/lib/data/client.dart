import 'chat_models.dart';

import 'dart:async';
import 'dart:convert';

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
import 'local_content.dart';
import 'delivery_queue.dart';
import 'read_positions.dart';
part 'content_state.dart';

class NekodotClient extends ChangeNotifier {
  final AccountSession account;
  final prefs = ClientPreferences();
  LocalContent? store;
  String? _contentUser;
  final workspace = <String, dynamic>{};
  final quotes = <String, String>{};
  final views = <String, Json>{};
  final _dirtyNodes = <String>{}, _dirtyMessages = <String>{};
  Timer? _saveTimer, _viewTimer;
  late final deliveries = DeliveryQueue(this);
  final contentRefresh = ValueNotifier<int>(0);
  final reading = ReadPositions();
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
        unawaited(_restoreConnection());
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
  void reportError(String value) {
    error = value;
    notifyListeners();
  }

  bool _closed = false;
  final nodes = <String, NodeData>{};
  final Map<String, List<Json>> attachmentDrafts = {};
  final drafts = <String, String>{};
  final routineDrafts = <String, Json>{};
  final notifications = StreamController<Json>.broadcast();
  final foregroundNotice = ValueNotifier<Json?>(null);
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
    if (account.token != null) {
      await restoreContent();
      if (account.me != null) {
        unawaited(bootstrap());
      } else {
        await bootstrap();
      }
    }
  }

  Future<void> acceptSession(Json result) async {
    await account.accept(result);
    await bootstrap();
  }

  Future<Json> rpc(String method, [Json params = const {}, String? target]) =>
      ClientContent.cachedReads.contains(method)
      ? readView(method, params, target ?? selectedNodeId)
      : connection.rpc(method, params, target ?? selectedNodeId);
  Future<void> login(String email, String password) async {
    final result = await account.request(
      '/auth/login',
      method: 'POST',
      body: {'email': email, 'password': password},
    );
    await acceptSession(result);
  }

  Future<void> bootstrap() async {
    final session = account.token;
    try {
      final me = await account.request('/me');
      if (_closed || session != account.token) return;
      final userId = me['user']?['userId'] as String?;
      if (userId != null) {
        await openContent(userId);
        if (_closed || session != account.token) return;
        await account.vault.write(
          key: 'content-user:${account.origin}',
          value: jsonEncode({'userId': userId, 'session': account.token}),
        );
      }
      if (_closed || session != account.token) return;
      account.me = me;
      final available = objects(account.me!['nodes']);
      for (final n in available) {
        nodes.putIfAbsent(n['nodeId'] as String, NodeData.new).online =
            n['online'] == true;
      }
      if (!available.any((n) => n['nodeId'] == selectedNodeId)) {
        selectedNodeId = available.firstOrNull?['nodeId'] as String?;
      }
      error = '';
      saveContent();
      await connection.connect();
    } catch (e) {
      if (_closed || session != account.token) return;
      if (e is RelayError && e.status == 401) {
        await clearSession();
      } else if (account.token != null) {
        unawaited(connection.connect());
      }
      if (!isConnectionFailure(e)) error = '$e';
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
      final userId = value['user']?['userId'] as String?;
      if (store == null && userId != null) {
        await openContent(userId);
        if (_closed || session != account.token) return;
        account.me = value;
        await account.vault.write(
          key: 'content-user:${account.origin}',
          value: jsonEncode({'userId': userId, 'session': session}),
        );
      }
      if (_closed || session != account.token) return;
      for (final item in objects(value['nodes'])) {
        nodes.putIfAbsent(item['nodeId'] as String, NodeData.new).online =
            item['online'] == true;
      }
      final available = objects(value['nodes']);
      if (!available.any((n) => n['nodeId'] == selectedNodeId)) {
        selectedNodeId = available.firstOrNull?['nodeId'] as String?;
      }
      saveContent();
    } catch (e) {
      if (_closed || account.token != session) return;
      if (e is RelayError && e.status == 401) {
        await clearSession();
        return;
      }
      if (!isConnectionFailure(e)) error = '$e';
    }
    notifyListeners();
  }

  Future<void> _restoreConnection() async {
    await refreshMe();
    if (_closed || !connection.ready) return;
    if (selectedNodeId != null && node.online) {
      await synchronize(selectedNodeId!);
    }
    unawaited(deliveries.drain());
    contentRefresh.value++;
  }

  Future<void> logout() async {
    // End local delivery immediately, even when revoking the remote session
    // cannot complete until a dead HTTP connection times out.
    Object? failure;
    final revoke = account
        .request('/auth/logout', method: 'POST', body: {})
        .catchError((Object e) {
          failure = e;
          return <String, dynamic>{};
        });
    await clearSession();
    await revoke;
    if (failure != null && !isConnectionFailure(failure!)) throw failure!;
  }

  Future<void> selectNode(String id) async {
    selectedNodeId = id;
    saveContent();
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
      final initialSnapshot = n.seq == 0;
      final result = await rpc(
        n.seq == 0 ? 'sync.snapshot' : 'sync.since',
        n.seq == 0 ? {} : {'seq': n.seq},
        id,
      );
      if (_closed || !identical(nodes[id], n)) return;
      if (n.seq == 0) {
        n.snapshot(result);
        await reading.baseline(id, n.seq);
      } else if (result['resyncRequired'] == true) {
        final snapshot = await rpc('sync.snapshot', {}, id);
        if (_closed || !identical(nodes[id], n)) return;
        n.snapshot(snapshot);
      } else {
        for (final event in objects(result['events'])) {
          n.update({'type': 'event', 'payload': event});
          if (event['kind'] == 'message.upserted') {
            _rememberIncoming(id, [
              ChatMessage.fromJson(object(event['data'])),
            ]);
          }
        }
      }
      _rememberIncoming(id, [
        ...n.latest.values,
        ...n.messages.values.expand((messages) => messages),
      ]);
      // A newer outgoing summary (for example from another device) can hide
      // an unread reply. Read only the changed history until that reply or
      // this device's viewed position is reached. No task is replayed.
      for (final latest
          in initialSnapshot || result['resyncRequired'] == true
              ? n.latest.values
              : const <ChatMessage>[]) {
        final conversation = latest.conversationId;
        final viewed = reading.position(id, conversation);
        if (latest.seq <= viewed || reading.latest(id, conversation) > viewed) {
          continue;
        }
        int? before;
        while (true) {
          final page = await rpc('messages.list', {
            'conversationId': conversation,
            'limit': 50,
            'beforeSeq': ?before,
          }, id);
          final messages = objects(page['messages'])
              .map(ChatMessage.fromJson)
              .toList();
          if (messages.isEmpty) break;
          _rememberIncoming(id, messages);
          final oldest = messages
              .map((m) => m.seq)
              .reduce((a, b) => a < b ? a : b);
          if (oldest <= viewed ||
              messages.length < 50 ||
              reading.latest(id, conversation) > viewed) {
            break;
          }
          before = oldest;
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
        if (event['type'] == 'event' &&
            event['payload']['kind'] == 'message.upserted') {
          _rememberIncoming(id, [
            ChatMessage.fromJson(object(event['payload']['data'])),
          ]);
        }
      }
      n.buffer.clear();
      _rememberIncoming(id, n.messages.values.expand((messages) => messages));
      error = '';
      if (id == selectedNodeId && visibleConversation != null) {
        await loadMessages(visibleConversation!, target: id);
      }
    } catch (e) {
      if (!isConnectionFailure(e)) error = '$e';
    } finally {
      // Frames received while refreshing the visible message window still
      // belong to this sync. Never strand them behind a failed page request.
      final buffered = List<Json>.of(n.buffer);
      n.buffer.clear();
      n.syncing = false;
      if (!_closed && identical(nodes[id], n)) {
        for (final event in buffered) {
          n.update(event);
          if (event['type'] == 'event' &&
              event['payload']['kind'] == 'message.upserted') {
            _rememberIncoming(id, [
              ChatMessage.fromJson(object(event['payload']['data'])),
            ]);
          }
        }
        n.notifySnapshot();
        saveContent(id);
        for (final conversation in n.messages.keys) {
          saveContent(id, conversation);
        }
      }
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
    if (opened.isEmpty) {
      final cached = await store?.read('nodes/$id/messages/$conversationId');
      if (_closed ||
          !identical(nodes[id], n) ||
          !identical(n.messages[conversationId], opened)) {
        return;
      }
      if (cached != null) {
        final merged = <String, ChatMessage>{
          for (final m in objects(cached['messages']).map(ChatMessage.fromJson))
            m.messageId: m,
          for (final m in opened) m.messageId: m,
        };
        opened
          ..clear()
          ..addAll(merged.values)
          ..sort((a, b) => a.seq.compareTo(b.seq));
        n.changed(conversationId);
      }
    }
    if ((!connection.ready || !n.online) && opened.isNotEmpty) return;
    final result = await rpc('messages.list', {
      'conversationId': conversationId,
      'limit': 50,
      'beforeSeq': ?before,
      'aroundMessageId': ?around,
    }, id);
    if (_closed || !identical(nodes[id], n)) return;
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
    _rememberIncoming(id, n.messages[conversationId]!);
    n.changed(conversationId, summary: true);
    saveContent(id, conversationId);
  }

  Future<void> loadFlow(String conversationId, [String? taskId]) async {
    final target = selectedNodeId!;
    final n = node;
    final key = taskId ?? n.flow(conversationId)?.key ?? conversationId;
    if ((!connection.ready || !n.online) && n.flows.containsKey(key)) {
      return;
    }
    final requestedAt = n.seq;
    final response = await rpc('flow.get', {
      'conversationId': conversationId,
      'taskId': ?taskId,
    }, target);
    if (_closed || !identical(nodes[target], n)) return;
    final value = response['flow'];
    final current = n.flows[key];
    if (value == null) {
      if (current == null || current.seq <= requestedAt) {
        n.flows.remove(key);
      }
    } else {
      final flow = FlowSnapshot.fromJson(object(value));
      if (current == null || current.seq <= flow.seq) {
        n.flows[flow.key] = flow;
      }
    }
    n.changed(conversationId);
    saveContent(target);
  }

  int incomingSequence(String conversationId) {
    var seq = reading.latest(selectedNodeId!, conversationId);
    final latest = node.latest[conversationId];
    for (final message in [?latest, ...?node.messages[conversationId]]) {
      if (message.author.type != 'user' &&
          message.status != 'streaming' &&
          const {
            'text',
            'approval',
            'question',
            'system',
            'secret',
          }.contains(message.kind) &&
          message.seq > seq) {
        seq = message.seq;
      }
    }
    return seq;
  }

  void _rememberIncoming(String nodeId, Iterable<ChatMessage> messages) {
    for (final message in messages) {
      if (message.author.type != 'user' &&
          message.status != 'streaming' &&
          const {
            'text',
            'approval',
            'question',
            'system',
            'secret',
          }.contains(message.kind)) {
        unawaited(
          reading.received(nodeId, message.conversationId, message.seq),
        );
      }
    }
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
    unawaited(flushContent());
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
        if (p['online'] == true) {
          contentRefresh.value++;
          unawaited(deliveries.drain());
        }
      case 'event':
      case 'live':
        if (id == null) return;
        final n = nodes.putIfAbsent(id, NodeData.new);
        if (n.syncing || n.buffer.isNotEmpty) {
          n.buffer.add(frame);
        } else {
          final incoming =
              frame['type'] == 'event' &&
              p['kind'] == 'message.upserted' &&
              (p['seq'] as int) > n.seq;
          n.update(frame);
          if (incoming) {
            _rememberIncoming(id, [ChatMessage.fromJson(object(p['data']))]);
          }
        }
        final conversation =
            (p['data']?['conversationId'] ?? p['conversationId']) as String?;
        saveContent(
          id,
          conversation != null && n.messages.containsKey(conversation)
              ? conversation
              : null,
        );
        return;
      case 'notify':
        if (id != null) notifications.add({...p, 'nodeId': id});
      case 'error':
        error = '${p['message']}';
    }

    notifyListeners();
  }

  Future<void> clearSession() async {
    final pendingSave = flushContent();
    foregroundNotice.value = null;
    account.token = null;
    await connection.disconnect();
    deliveries.suspend();
    await deliveries.save();
    await pendingSave;
    _saveTimer?.cancel();
    _viewTimer?.cancel();
    store = null;
    _contentUser = null;
    views.clear();
    quotes.clear();
    workspace.clear();
    _dirtyNodes.clear();
    _dirtyMessages.clear();
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
    unawaited(flushContent());
    _viewTimer?.cancel();
    deliveries.dispose();
    _closed = true;
    account.removeListener(notifyListeners);
    prefs.removeListener(notifyListeners);
    connection.removeListener(notifyListeners);
    connection.dispose();
    account.dispose();
    prefs.dispose();
    reading.dispose();
    for (final n in nodes.values) {
      n.dispose();
    }
    notifications.close();
    foregroundNotice.dispose();
    destinations.close();
    super.dispose();
  }
}
