import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/node_update.dart';
import 'package:nekodot_native/ui/design.dart';

void main() {
  test('An updated computer refreshes its manual command without reconnecting the client', () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    WebSocket? socket;
    var old = true, reads = 0;
    final command = "curl -fsSL 'https://example.test/install.sh' | bash";
    server.listen((request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        socket = await WebSocketTransformer.upgrade(request);
        socket!.listen((raw) {
          if (jsonDecode(raw as String)['type'] == 'hello') {
            socket!.add(
              jsonEncode({'v': 1, 'type': 'hello.ok', 'payload': {}}),
            );
          }
        });
      }
    });
    final c = NekodotClient(
      server: 'http://127.0.0.1:${server.port}',
      transport: MockClient((request) async {
        reads++;
        expect(request.url.path, '/api/me');
        return http.Response(
          jsonEncode({
            'nodes': [
              {
                'nodeId': 'node',
                'online': true,
                'updateCommand': old ? command : null,
              },
            ],
          }),
          200,
        );
      }),
    );
    c.token = 'isolated-test';
    await c.connect();
    Future<void> until(bool Function() done) async {
      final end = DateTime.now().add(const Duration(seconds: 5));
      while (!done()) {
        if (DateTime.now().isAfter(end)) {
          fail('Computer information did not refresh');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    await until(() => c.me != null);
    expect(objects(c.me!['nodes']).single['updateCommand'], command);
    old = false;
    socket!.add(
      jsonEncode({
        'v': 1,
        'type': 'node.status',
        'nodeId': 'node',
        'payload': {'online': true},
      }),
    );
    await until(() => objects(c.me!['nodes']).single['updateCommand'] == null);
    expect(reads, 2);
    expect(c.ready, isTrue);
    c.dispose();
    await server.close(force: true);
  });

  testWidgets(
    'A narrow manual-update panel keeps the command readable and copyable',
    (tester) async {
      final c = NekodotClient();
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: Scaffold(
            body: SizedBox(
              width: 248,
              child: NodeUpdateNotice(
                client: c,
                command: "curl -fsSL 'https://example.test/install.sh' | bash",
              ),
            ),
          ),
        ),
      );
      expect(find.text('这台电脑需要更新一次'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.byTooltip('复制命令'), findsOneWidget);
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      c.dispose();
    },
  );
}
