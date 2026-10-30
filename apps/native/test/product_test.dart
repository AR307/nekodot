import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/bot_editor.dart';
import 'package:nekodot_native/features/chat.dart';

final bot = <String, dynamic>{
  'botId': 'nk-test00',
  'displayName': 'Maple',
  'handle': 'maple',
  'role': 'Helpful assistant',
  'model': 'test-model',
  'sourceId': 'source',
  'avatar': {'color': '#E8603C'},
};

class JourneyClient extends NekodotClient {
  final accepted = Completer<Json>();
  Json? update;
  JourneyClient() {
    selectedNodeId = 'test-node';
    ready = true;
    node.online = true;
    node.bots = [bot];
    node.conversations = [
      {'conversationId': 'dm', 'kind': 'dm', 'botId': bot['botId']},
    ];
  }
  @override
  Future<Json> rpc(
    String method, [
    Json params = const {},
    String? target,
  ]) async {
    switch (method) {
      case 'bots.permissions.get':
        return {'mode': 'smart'};
      case 'providers.list':
        return {
          'sources': [
            {'sourceId': 'source', 'name': 'Test API', 'ready': true},
          ],
        };
      case 'models.options':
        return {
          'models': ['test-model'],
        };
      case 'bots.update':
        update = params;
        return {};
      case 'messages.list':
        return {'messages': []};
      case 'messages.send':
        return accepted.future;
      default:
        throw StateError('Unexpected test request: $method');
    }
  }
}

void main() {
  testWidgets('Rename a Bot without replacing its native approval setting', (
    tester,
  ) async {
    final client = JourneyClient();
    await tester.pumpWidget(
      MaterialApp(
        home: BotEditor(client: client, existing: bot),
      ),
    );
    await tester.pumpAndSettle();
    final name = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == '名称',
    );
    await tester.enterText(name, 'Maple updated');
    await tester.scrollUntilVisible(
      find.text('保存'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(client.update?['displayName'], 'Maple updated');
    expect(client.update?['approvalMode'], 'smart');
    await tester.pumpWidget(const SizedBox.shrink());
    client.dispose();
  });

  testWidgets(
    'Keep the next instruction drafted before the previous send is acknowledged',
    (tester) async {
      final client = JourneyClient();
      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(client: client, conversationId: 'dm'),
        ),
      );
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('chat-input'));
      await tester.enterText(input, 'First instruction');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.enterText(input, 'Next instruction');
      client.accepted.complete({});
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(input).controller!.text,
        'Next instruction',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      client.dispose();
    },
  );
}
