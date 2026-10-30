import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

typedef Json = Map<String, dynamic>;
final _random = Random.secure();
Json object(dynamic value) => Map<String, dynamic>.from(value as Map);
List<Json> objects(dynamic value) =>
    (value as List? ?? []).map(object).toList();
String uid() {
  final b = List.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final s = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

class NodeData {
  List<Json> bots = [], groups = [], conversations = [];
  final Map<String, List<Json>> messages = {};
  final Map<String, Json> activities = {}, screens = {};
  int seq = 0;
  bool online = false, syncing = false;
  final List<Json> buffer = [];
  void snapshot(Json data) {
    bots = objects(data['bots']);
    groups = objects(data['groups']);
    conversations = objects(data['conversations']);
    seq = data['headSeq'] as int;
  }
}

class RelayError implements Exception {
  final String message, code;
  final int status;
  RelayError(this.message, [this.code = '', this.status = 0]);
  @override
  String toString() => message;
}

class NekodotClient extends ChangeNotifier {
  final Uri origin;
  final http.Client transport;
  final FlutterSecureStorage vault;
  NekodotClient({
    String server = const String.fromEnvironment(
      'RELAY_URL',
      defaultValue: 'https://nekodot.com',
    ),
    http.Client? transport,
    FlutterSecureStorage? vault,
  }) : origin = Uri.parse(server),
       transport = transport ?? http.Client(),
       vault = vault ?? const FlutterSecureStorage();
  String? token, selectedNodeId;
  String? visibleConversation;
  Json? me;
  String language = 'zh', theme = 'system', error = '';
  bool ready = false, connecting = false, active = true, _closed = false;
  int _retry = 1;
  WebSocket? _socket;
  Timer? _reconnect, _heartbeat;
  DateTime _lastFrame = DateTime.now();
  final nodes = <String, NodeData>{};
  final drafts = <String, String>{};
  final _pending = <String, Completer<Json>>{};
  final notifications = StreamController<Json>.broadcast();
  final destinations = StreamController<Json>.broadcast();
  Json? pendingDestination;
  String notificationStatus = '', notificationError = '';
  NodeData get node => nodes.putIfAbsent(selectedNodeId ?? '', NodeData.new);
  bool get online => ready && node.online;
  bool get zh => language == 'zh';
  String tr(String cn, String en) => zh ? cn : en;
  Uri url(String path) => origin.replace(path: path);
  Uri wsUrl(String path, [Map<String, String>? query]) => origin.replace(
    scheme: origin.scheme == 'https' ? 'wss' : 'ws',
    path: path,
    queryParameters: query,
  );

  Future<void> initialize() async {
    if (origin.scheme != 'https' &&
        !['127.0.0.1', 'localhost'].contains(origin.host)) {
      throw ArgumentError('A trusted HTTPS Relay is required');
    }
    final prefs = await SharedPreferences.getInstance();
    language = prefs.getString('language') ?? 'zh';
    theme = prefs.getString('theme') ?? 'system';
    selectedNodeId = prefs.getString('node');
    token = await vault.read(key: 'nekodot-session');
    if (token != null) await bootstrap();
  }

  Future<Json> request(String path, {String method = 'GET', Json? body}) async {
    final req = http.Request(method, url('/api$path'));
    req.headers['Content-Type'] = 'application/json';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);
    final response = await http.Response.fromStream(await transport.send(req))
        .timeout(const Duration(seconds: 30));
    final value = object(jsonDecode(response.body));
    if (response.statusCode >= 400) {
      final e = object(value['error'] ?? {});
      throw RelayError(
        '${e['message'] ?? 'HTTP ${response.statusCode}'}',
        '${e['code'] ?? ''}',
        response.statusCode,
      );
    }
    return value;
  }

  Future<void> login(String email, String password) async {
    final result = await request(
      '/auth/login',
      method: 'POST',
      body: {'email': email, 'password': password},
    );
    await acceptSession(result);
  }

  Future<void> acceptSession(Json result) async {
    if (result['token'] == null) {
      throw RelayError('Email verification required', 'verification_required');
    }
    token = result['token'] as String;
    await vault.write(key: 'nekodot-session', value: token);
    await bootstrap();
  }

  Future<void> bootstrap() async {
    try {
      me = await request('/me');
      final available = objects(me!['nodes']);
      for (final n in available) {
        nodes.putIfAbsent(n['nodeId'] as String, NodeData.new).online =
            n['online'] == true;
      }
      if (!available.any((n) => n['nodeId'] == selectedNodeId)) {
        selectedNodeId = available.firstOrNull?['nodeId'] as String?;
      }
      error = '';
      await connect();
    } on RelayError catch (e) {
      if (e.status == 401) {
        token = null;
        await vault.delete(key: 'nekodot-session');
      }
      error = e.message;
    }
    notifyListeners();
  }

  Future<void> logout() async {
    await request('/auth/logout', method: 'POST', body: {});
    await clearSession();
  }

  Future<void> clearSession() async {
    token = null;
    await _socket?.close();
    _reconnect?.cancel();
    _heartbeat?.cancel();
    await vault.delete(key: 'nekodot-session');
    token = null;
    me = null;
    nodes.clear();
    drafts.clear();
    selectedNodeId = null;
    ready = false;
    notifyListeners();
  }

  Future<void> preferences({String? locale, String? appearance}) async {
    final prefs = await SharedPreferences.getInstance();
    if (locale != null) {
      language = locale;
      await prefs.setString('language', locale);
    }
    if (appearance != null) {
      theme = appearance;
      await prefs.setString('theme', appearance);
    }
    notifyListeners();
  }

  Future<void> selectNode(String id) async {
    selectedNodeId = id;
    await (await SharedPreferences.getInstance()).setString('node', id);
    notifyListeners();
    if (ready && node.online) await synchronize(id);
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

  Future<void> connect() async {
    if (_closed || token == null || connecting) return;
    connecting = true;
    _reconnect?.cancel();
    final previous = _socket;
    _socket = null;
    await previous?.close();
    try {
      final socket = await WebSocket.connect(wsUrl('/ws/client').toString())
          .timeout(const Duration(seconds: 10));
      if (_closed || token == null) {
        await socket.close();
        return;
      }
      _socket = socket;
      _lastFrame = DateTime.now();
      socket.listen(
        (raw) {
          if (_closed) return;
          try {
            _receive(object(jsonDecode(raw as String)));
          } catch (e) {
            error = 'Protocol: $e';
            notifyListeners();
          }
        },
        onDone: () {
          if (identical(_socket, socket)) {
            if (socket.closeCode == 4401) {
              unawaited(clearSession());
            } else {
              _disconnected();
            }
          }
        },
        onError: (Object e) {
          if (identical(_socket, socket)) {
            error = '$e';
            _disconnected();
          }
        },
      );
      _send('hello', {'token': token});
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
        if (DateTime.now().difference(_lastFrame).inSeconds > 65) {
          socket.close();
        }
      });
    } catch (e) {
      error = '$e';
      _disconnected();
    } finally {
      connecting = false;
      if (!_closed) notifyListeners();
    }
  }

  void _disconnected() {
    if (_closed) return;
    ready = false;
    _socket = null;
    _heartbeat?.cancel();
    for (final p in _pending.values) {
      if (!p.isCompleted) {
        p.completeError(
          RelayError(tr('连接断开，草稿已保留', 'Disconnected. Your draft is kept.')),
        );
      }
    }
    _pending.clear();
    notifyListeners();
    if (!_closed && token != null && active) {
      _reconnect?.cancel();
      _reconnect = Timer(Duration(seconds: _retry), connect);
      _retry = (_retry * 2).clamp(1, 30);
    }
  }

  void _send(String type, Json payload, {String? id, String? nodeId}) =>
      _socket!.add(
        jsonEncode({
          'v': 1,
          'id': id ?? uid(),
          'type': type,
          'payload': payload,
          'nodeId': ?nodeId,
        }),
      );
  Future<Json> rpc(
    String method, [
    Json params = const {},
    String? target,
  ]) async {
    if (!ready || _socket == null) {
      throw RelayError(tr('尚未连接服务器', 'Relay is disconnected'));
    }
    final id = uid(), wait = Completer<Json>();
    _pending[id] = wait;
    _send(
      'rpc.req',
      {'method': method, 'params': params},
      id: id,
      nodeId: target ?? selectedNodeId,
    );
    try {
      return await wait.future.timeout(const Duration(seconds: 30));
    } finally {
      _pending.remove(id);
    }
  }

  void _receive(Json frame) {
    if (frame['v'] != 1 ||
        frame['type'] is! String ||
        frame['payload'] is! Map) {
      throw const FormatException('Invalid envelope');
    }
    _lastFrame = DateTime.now();
    final p = object(frame['payload']), id = frame['nodeId'] as String?;
    switch (frame['type']) {
      case 'ping':
        _send('pong', {});
      case 'hello.ok':
        ready = true;
        _retry = 1;
        error = '';
        if (selectedNodeId != null && node.online) {
          unawaited(synchronize(selectedNodeId!));
        }
      case 'rpc.res':
        final waiting = _pending.remove(frame['replyTo']);
        if (waiting != null && !waiting.isCompleted) {
          if (p['ok'] == true) {
            waiting.complete(object(p['result']));
          } else {
            final e = object(p['error']);
            waiting.completeError(
              RelayError('${e['message']}', '${e['code']}'),
            );
          }
        }
      case 'node.status':
        if (id == null) return;
        nodes.putIfAbsent(id, NodeData.new).online = p['online'] == true;
        for (final n in (me?['nodes'] as List? ?? [])) {
          if (n['nodeId'] == id) n['online'] = p['online'];
        }
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
          _update(n, frame);
        }
      case 'notify':
        if (id != null) notifications.add({...p, 'nodeId': id});
      case 'error':
        error = '${p['message']}';
    }
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
          _update(n, {'type': 'event', 'payload': event});
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
        _update(n, event);
      }
      n.buffer.clear();
      error = '';
    } catch (e) {
      error = '$e';
    } finally {
      n.syncing = false;
      notifyListeners();
    }
  }

  Future<void> loadMessages(
    String conversationId, {
    String? target,
    int? before,
  }) async {
    final id = target ?? selectedNodeId!;
    final n = nodes.putIfAbsent(id, NodeData.new);
    final result = await rpc('messages.list', {
      'conversationId': conversationId,
      'limit': 50,
      'beforeSeq': ?before,
    }, id);
    final previous = n.messages[conversationId] ?? [];
    final merged = <String, Json>{
      for (final m in previous) m['messageId'] as String: m,
    };
    for (final m in objects(result['messages'])) {
      merged[m['messageId'] as String] = m;
    }
    n.messages[conversationId] = merged.values.toList()
      ..sort((a, b) => (a['seq'] as int).compareTo(b['seq'] as int));
    notifyListeners();
  }

  void _update(NodeData n, Json frame) {
    final p = object(frame['payload']);
    if (frame['type'] == 'event') {
      if ((p['seq'] as int) <= n.seq) return;
      n.seq = p['seq'] as int;
      final data = object(p['data']);
      switch (p['kind']) {
        case 'bot.upserted':
          _upsert(n.bots, data, 'botId');
        case 'group.upserted':
          _upsert(n.groups, data, 'groupId');
        case 'conversation.upserted':
          _upsert(n.conversations, data, 'conversationId');
        case 'bot.archived':
          n.bots.removeWhere((x) => x['botId'] == data['botId']);
        case 'group.archived':
          n.groups.removeWhere((x) => x['groupId'] == data['groupId']);
        case 'message.upserted':
          _upsert(
            n.messages.putIfAbsent(data['conversationId'] as String, () => []),
            data,
            'messageId',
          );
      }
    } else if (p['kind'] == 'activity') {
      n.activities[p['conversationId'] as String] = p;
    } else if (p['kind'] == 'screen') {
      final s = object(p['status']);
      n.screens[s['botId'] as String] = s;
    } else if (p['kind'] == 'delta') {
      final m = n.messages[p['conversationId']]
          ?.where((x) => x['messageId'] == p['messageId'])
          .firstOrNull;
      if (m == null || m['status'] != 'streaming') return;
      final content = object(m['content']),
          text = content['text'] as String,
          offset = p['offset'] as int;
      if (offset > text.length) return;
      final delta = p['text'] as String, skip = text.length - offset;
      if (skip < delta.length) {
        m['content'] = {...content, 'text': text + delta.substring(skip)};
      }
    }
  }

  void _upsert(List<Json> list, Json data, String key) {
    final i = list.indexWhere((x) => x[key] == data[key]);
    if (i < 0) {
      list.add(data);
    } else {
      list[i] = data;
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

  void resume() {
    active = true;
    unawaited(bootstrap());
  }

  void pause() {
    active = false;
  }

  @override
  void dispose() {
    _closed = true;
    _reconnect?.cancel();
    _heartbeat?.cancel();
    final socket = _socket;
    _socket = null;
    socket?.close();
    transport.close();
    notifications.close();
    destinations.close();
    super.dispose();
  }
}
