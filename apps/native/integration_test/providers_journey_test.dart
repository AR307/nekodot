import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/settings.dart';
import 'package:nekodot_native/features/bot_editor.dart';
import 'package:nekodot_native/ui/design.dart';

/// Native forms + real Relay/Node using recorded native Hermes management/responses.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'source settings, model choice, native Bot creation and reconnect',
    (tester) async {
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
          reason: 'The native source journey did not finish',
        );
      }

      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 500));
      }

      Future<void> fill(String label, String text) async {
        final field = find.descendant(
          of: find.widgetWithText(LabeledField, label),
          matching: find.byType(TextField),
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, text);
        await tester.pump(const Duration(milliseconds: 200));
      }

      var surfaceConverted = false;
      Future<void> screenshot(String name) async {
        await tester.pump(const Duration(milliseconds: 300));
        if (defaultTargetPlatform == TargetPlatform.android &&
            !surfaceConverted) {
          await binding.convertFlutterSurfaceToImage();
          surfaceConverted = true;
          await tester.pump();
        }
        await binding.takeScreenshot(name);
      }

      await client.selectNode(const String.fromEnvironment('QA_NODE'));
      await until(() => client.online);
      runApp(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: HomePage(client: client),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      if (defaultTargetPlatform == TargetPlatform.android) {
        await tap(find.byTooltip('设置'));
      } else {
        await tap(find.byTooltip('账户'));
        await tap(find.text('设置'));
      }
      await tap(find.text('模型来源'));
      await until(() => find.text('授权登录').evaluate().isNotEmpty);
      expect(find.textContaining('logged_in'), findsNothing);
      // Replay of the device flow recorded from real Hermes. No external account is used here.
      final authorization = await client.rpc('providers.authorize', {
        'provider': 'openai-codex',
        'action': 'start',
      });
      for (var i = 0; i < 2; i++) {
        await client.rpc('providers.authorize', {
          'provider': 'openai-codex',
          'action': 'poll',
          'sessionId': authorization['session_id'],
        });
      }
      await tap(find.text('ChatGPT or Codex Subscription'));
      await tap(find.byTooltip('Back'));
      await tap(find.text('ChatGPT or Codex Subscription'));
      expect(find.text('已授权'), findsOneWidget);
      expect(find.text('开始授权'), findsNothing);
      await screenshot('native-authorization-approved');
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 400));
      for (final name in ['Research API', 'Writing API']) {
        await tester.scrollUntilVisible(find.byIcon(Icons.add), 300);
        await tap(find.byIcon(Icons.add));
        await fill('名称', name);
        await fill('API URL', 'https://models.example.test/v1');
        await fill('API KEY', 'test-only-$name');
        expect(find.text('模型'), findsNothing);
        await tap(find.text('保存'));
        await until(() => find.byType(CustomSourcePage).evaluate().isEmpty);
        await until(() => find.text(name).evaluate().isNotEmpty);
      }
      expect(
        objects((await client.rpc('providers.list'))['sources']),
        hasLength(3),
      );
      debugPrint('QA: native sources ready');
      await tester.scrollUntilVisible(find.text('Writing API'), 300);
      await screenshot('native-sources');
      await tester.pageBack();
      await until(() => find.byType(SourcesPage).evaluate().isEmpty);
      await tester.pageBack();
      await until(() => find.byType(SettingsPage).evaluate().isEmpty);
      await tap(find.byTooltip('新建'));
      await tap(find.text('新建 Bot'));
      await until(() => find.byType(BotEditor).evaluate().isNotEmpty);
      await fill('名称', 'Maple');
      await fill('@handle', 'maple-sources');
      await fill('角色设定', 'Helpful source specialist');
      final sourceField = find.descendant(
        of: find.widgetWithText(LabeledField, '模型来源'),
        matching: find.byType(DropdownButtonFormField<String>),
      );
      await tap(sourceField);
      await tap(find.text('Writing API').last);
      await fill('模型', 'recorded-model');
      await tap(find.text('高级'));
      await fill('上下文覆盖', '64000');
      debugPrint('QA: native source bot form ready');
      await screenshot('native-source-bot-form');
      await tap(find.text('保存'));
      await until(() => find.byType(BotEditor).evaluate().isEmpty);
      await until(
        () => client.node.bots.any((bot) => bot['handle'] == 'maple-sources'),
      );
      final bot = client.node.bots.firstWhere(
        (bot) => bot['handle'] == 'maple-sources',
      );
      final source = objects((await client.rpc('providers.list'))['sources'])
          .firstWhere((source) => source['name'] == 'Writing API');
      expect(bot['sourceId'], source['sourceId']);
      final conversation = client.node.conversations.firstWhere(
        (c) => c['kind'] == 'dm' && c['botId'] == bot['botId'],
      );
      final id = conversation['conversationId'] as String;
      await client.loadMessages(id);
      await until(
        () => (client.node.messages[id] ?? []).any(
          (message) => message['status'] == 'done',
        ),
      );
      await tap(find.byKey(ValueKey('conversation-$id')));
      await until(() => find.textContaining('Maple').evaluate().isNotEmpty);
      debugPrint('QA: native source welcome ready');
      await screenshot('native-source-welcome');
      final before = client.node.messages[id]!
          .map((message) => message['messageId'])
          .toList();
      await client.connect();
      await client.selectNode(client.selectedNodeId!);
      await until(() => client.online);
      await client.loadMessages(id);
      expect(
        client.node.messages[id]!
            .map((message) => message['messageId'])
            .toList(),
        before,
      );
      final info = await client.rpc('models.info', {'botId': bot['botId']});
      expect(info['configuredContext'], 64000);
      await tap(find.byTooltip('详情'));
      await until(() => find.text('模型与压缩').evaluate().isNotEmpty);
      await screenshot('native-model-information');
      expect(tester.takeException(), isNull);
      debugPrint('QA: native source journey completed');
      client.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
