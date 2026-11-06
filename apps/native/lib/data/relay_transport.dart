import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'account.dart';
import 'json.dart';

class RelayTransport extends ChangeNotifier {
  final Uri endpoint;
  final String? Function() token;
  final void Function(Json) onEvent;
  final VoidCallback onReady, onUnauthorized;
  final void Function(String) onError;
  final String Function(String, String) tr;
  RelayTransport({
    required this.endpoint,
    required this.token,
    required this.onEvent,
    required this.onReady,
    required this.onUnauthorized,
    required this.onError,
    required this.tr,
  });
  bool ready = false, connecting = false, active = true, _closed = false;
  int _retry = 1;
  WebSocket? _socket;
  Timer? _reconnect, _heartbeat;
  DateTime _lastFrame = DateTime.now();
  final _pending = <String, Completer<Json>>{};
  Future<void> connect() async {
    if (_closed || token() == null || connecting) return;
    connecting = true;
    _reconnect?.cancel();
    final previous = _socket;
    _socket = null;
    // Nothing may go out on the next socket before its handshake finishes.
    ready = false;
    _failPending();
    await previous?.close();
    try {
      final socket = await WebSocket.connect(endpoint.toString())
          .timeout(const Duration(seconds: 10));
      if (_closed || token() == null) {
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
            onError('Protocol: $e');
            notifyListeners();
          }
        },
        onDone: () {
          if (identical(_socket, socket)) {
            if (socket.closeCode == 4401) {
              onUnauthorized();
            } else {
              _disconnected();
            }
          }
        },
        onError: (Object e) {
          if (identical(_socket, socket)) {
            onError('$e');
            _disconnected();
          }
        },
      );
      _send('hello', {'token': token()});
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
        if (DateTime.now().difference(_lastFrame).inSeconds > 65) {
          socket.close();
        }
      });
    } catch (e) {
      onError('$e');
      _disconnected();
    } finally {
      connecting = false;
      if (!_closed) notifyListeners();
    }
  }

  void _failPending() {
    for (final p in _pending.values) {
      if (!p.isCompleted) {
        p.completeError(
          RelayError(tr('连接断开，草稿已保留', 'Disconnected. Your draft is kept.')),
        );
      }
    }
    _pending.clear();
  }

  void _disconnected() {
    if (_closed) return;
    ready = false;
    _socket = null;
    _heartbeat?.cancel();
    _failPending();
    notifyListeners();
    if (!_closed && token() != null && active) {
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
      nodeId: target,
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
    final p = object(frame['payload']);
    switch (frame['type']) {
      case 'ping':
        _send('pong', {});
      case 'hello.ok':
        ready = true;
        _retry = 1;
        onReady();
        notifyListeners();
      case 'rpc.res':
        final waiting = _pending.remove(frame['replyTo']);
        if (waiting != null && !waiting.isCompleted) {
          if (p['ok'] == true) {
            waiting.complete(object(p['result']));
          } else {
            final e = object(p['error']);
            waiting.completeError(
              RelayError(e['message'].toString(), e['code'].toString()),
            );
          }
        }
      default:
        onEvent(frame);
    }
  }

  Future<void> disconnect() async {
    await _socket?.close();
    _reconnect?.cancel();
    _heartbeat?.cancel();
    ready = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _reconnect?.cancel();
    _heartbeat?.cancel();
    final socket = _socket;
    _socket = null;
    socket?.close();
    super.dispose();
  }
}
