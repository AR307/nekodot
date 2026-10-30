import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/data/client.dart';

/// A Relay stand-in that holds the handshake until the test releases it.
class Relay {
  final HttpServer server;
  final sockets = <WebSocket>[];
  final hello = <WebSocket>[];
  final requests = <Map<String, dynamic>>[];
  Relay(this.server) {
    server.transform(WebSocketTransformer()).listen((socket) {
      sockets.add(socket);
      socket.listen((raw) {
        final frame = jsonDecode(raw as String) as Map<String, dynamic>;
        if (frame['type'] == 'hello') {
          hello.add(socket);
        } else if (frame['type'] == 'rpc.req') {
          requests.add(frame);
        }
      });
    });
  }
  void accept(WebSocket socket) => socket.add(
    jsonEncode({'v': 1, 'id': 'ok', 'type': 'hello.ok', 'payload': {}}),
  );
}

Future<void> until(bool Function() ready) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!ready()) {
    if (DateTime.now().isAfter(end)) fail('Timed out waiting');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('A reconnect sends nothing until the new handshake finishes', () async {
    final relay = Relay(await HttpServer.bind('127.0.0.1', 0));
    final client = NekodotClient(
      server: 'http://127.0.0.1:${relay.server.port}',
    );
    client.token = 'test';
    await client.connect();
    await until(() => relay.hello.length == 1);
    relay.accept(relay.hello[0]);
    await until(() => client.ready);

    // An answer still owed by the old socket fails instead of waiting 30 seconds.
    final owed = client.rpc('messages.list', {}, 'node');
    await until(() => relay.requests.length == 1);
    final reconnecting = client.connect();

    expect(client.ready, isFalse);
    await expectLater(owed, throwsA(isA<RelayError>()));
    await expectLater(
      client.rpc('messages.list', {}, 'node'),
      throwsA(isA<RelayError>()),
    );
    await reconnecting;
    await until(() => relay.hello.length == 2);
    expect(client.ready, isFalse);
    expect(relay.requests, hasLength(1));

    relay.accept(relay.hello[1]);
    await until(() => client.ready);
    unawaited(
      client
          .rpc('messages.list', {}, 'node')
          .catchError((_) => <String, dynamic>{}),
    );
    await until(() => relay.requests.length == 2);

    client.dispose();
    await relay.server.close(force: true);
  });
}
