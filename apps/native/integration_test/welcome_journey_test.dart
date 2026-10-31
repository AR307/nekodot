import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/chat.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/ui/design.dart';

/// Actual Node + Relay RPC and recorded Hermes text, not a widget mock.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const inspect = bool.fromEnvironment('QA_INSPECT');
  testWidgets('new profile introduction, reconnect and explicit retry', (
    tester,
  ) async {
    final client = NekodotClient();
    await client.login(
      const String.fromEnvironment('QA_EMAIL'),
      const String.fromEnvironment('QA_PASSWORD'),
    );
    Future<void> until(bool Function() ready) async {
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(
        ready(),
        isTrue,
        reason: 'The native welcome journey did not complete.',
      );
    }

    await client.selectNode(const String.fromEnvironment('QA_NODE'));
    await until(() => client.online);
    Future<String> create(String name, String handle) async {
      final result = await client.rpc('bots.create', {
        'sourceId': ((await client.rpc('providers.list'))['sources'] as List)
            .first['sourceId'],
        'displayName': name,
        'handle': handle,
        'role': 'Helpful assistant',
        'model': 'recorded-model',
        'avatar': {'shape': 'dot', 'color': '#E8603C'},
      });
      final id = result['conversation']['conversationId'] as String;
      await client.loadMessages(id);
      return id;
    }

    runApp(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: HomePage(client: client),
      ),
    );
    final id = await create('Maple', 'maple');
    await until(
      () => (client.node.messages[id] ?? []).any((m) => m['status'] == 'done'),
    );
    await until(
      () => find.byKey(ValueKey('conversation-$id')).evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(ValueKey('conversation-$id')));
    await tester.pump(const Duration(milliseconds: 500));
    final messages = client.node.messages[id]!;
    expect(messages, hasLength(1));
    expect(messages.single['content']['welcome'], isTrue);
    expect(messages.single['author']['type'], 'bot');
    expect(messages.single['content']['text'], contains('Maple'));
    expect(find.byType(MessageTile), findsOneWidget);
    debugPrint('QA: native welcome ready');
    if (inspect) await Future<void>.delayed(const Duration(seconds: 8));
    await client.connect();
    await client.selectNode(client.selectedNodeId!);
    await until(() => client.online);
    await client.loadMessages(id);
    expect(client.node.messages[id], hasLength(1));
    expect(
      client.node.messages[id]!.single['messageId'],
      messages.single['messageId'],
    );
    // A wide window keeps the chat beside the list, with no page to leave.
    if (find.byType(BackButton).evaluate().isNotEmpty) {
      await tester.pageBack();
    }
    await tester.pump(const Duration(milliseconds: 500));
    final failedId = await create('Maple Retry', 'retry-intro');
    await until(
      () => (client.node.messages[failedId] ?? []).any(
        (m) => m['status'] == 'failed',
      ),
    );
    await until(
      () =>
          find.byKey(ValueKey('conversation-$failedId')).evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(ValueKey('conversation-$failedId')));
    await tester.pump(const Duration(milliseconds: 500));
    await until(() => find.text('重试自我介绍').evaluate().isNotEmpty);
    debugPrint('QA: native welcome failure ready');
    if (inspect) await Future<void>.delayed(const Duration(seconds: 8));
    await tester.tap(find.text('重试自我介绍'));
    await until(
      () => (client.node.messages[failedId] ?? []).any(
        (m) => m['status'] == 'done',
      ),
    );
    expect(client.node.messages[failedId], hasLength(2));
    expect(
      client.node.messages[failedId]!.any((m) => m['author']['type'] == 'user'),
      isFalse,
    );
    expect(tester.takeException(), isNull);
    debugPrint('QA: native welcome retry completed');
    client.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
