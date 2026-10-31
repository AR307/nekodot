import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/user_memory.dart';
import 'package:nekodot_native/ui/design.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native shared memory confirmation, second computer, draft and return navigation',
    (tester) async {
      runApp(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
        ),
      );
      await tester.pump();
      final client = NekodotClient();
      await tester.runAsync(() async {
        await client.login(
          const String.fromEnvironment('QA_EMAIL'),
          const String.fromEnvironment('QA_PASSWORD'),
        );
        await client.selectNode(const String.fromEnvironment('QA_NODE'));
      });
      Future<void> until(bool Function() ready) async {
        final end = DateTime.now().add(const Duration(seconds: 35));
        while (!ready() && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 200));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(ready(), isTrue);
      }

      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 400));
      }

      var converted = false;
      Future<void> screenshot(String name) async {
        if (defaultTargetPlatform != TargetPlatform.android) return;
        if (defaultTargetPlatform == TargetPlatform.android && !converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
          await tester.pump();
        }
        await binding.takeScreenshot(name);
      }

      await until(() => client.online);
      runApp(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: HomePage(client: client),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      final id = client.node.conversations.first['conversationId'] as String;
      await tap(find.byKey(ValueKey('conversation-$id')));
      await tap(find.byTooltip('详情'));
      await tap(find.text('记忆').first);
      await until(() => find.text('USER.md').evaluate().isNotEmpty);
      await tap(find.text('USER.md'));
      final editor = find.byKey(const ValueKey('shared-user-memory-editor'));
      await until(() => editor.evaluate().isNotEmpty);
      expect(
        tester.widget<TextField>(editor).controller!.text,
        contains('Prefers concise answers.'),
      );
      const document =
          'Prefers concise answers.\n§\nUses metric units.\n§\nPrefers mint tea.';
      await tester.enterText(editor, document);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 300));
      await screenshot('native-user-memory-review');
      await tap(
        find.descendant(
          of: find.byType(SharedUserMemoryPage),
          matching: find.byType(FilledButton),
        ),
      );
      await until(() => find.text('记忆已保存').evaluate().isNotEmpty);
      await tester.pageBack();
      await until(() => find.byType(SharedUserMemoryPage).evaluate().isEmpty);
      // Wide windows show details as a side panel beside the chat.
      final closePanel = find.byTooltip('关闭');
      if (closePanel.evaluate().isNotEmpty) {
        await tester.tap(closePanel);
        await tester.pump(const Duration(milliseconds: 300));
      } else {
        await tester.pageBack();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pageBack();
      }
      await until(() => find.byType(HomePage).evaluate().isNotEmpty);
      final second = objects(client.me?['nodes'])
          .firstWhere((n) => n['name'] == 'Computer B');
      await client.selectNode(second['nodeId'] as String);
      await until(() => client.online && client.node.bots.isNotEmpty);
      final bot = client.node.bots.first;
      final memory = await client.rpc('memory.get', {'botId': bot['botId']});
      expect(
        objects(memory['documents'])
            .firstWhere((d) => d['name'] == 'USER.md')['content'],
        document,
      );
      final secondId =
          client.node.conversations.first['conversationId'] as String;
      await tester.pump(const Duration(milliseconds: 500));
      await tap(find.byKey(ValueKey('conversation-$secondId')));
      await tap(find.byTooltip('详情'));
      await tap(find.text('记忆').first);
      await until(() => find.text('USER.md').evaluate().isNotEmpty);
      await tap(find.text('USER.md'));
      await until(() => find.text('保存').evaluate().isNotEmpty);
      await tester.enterText(editor, '$document\n§\nDraft stays on refresh.');
      await tap(find.byTooltip('刷新'));
      final field = tester.widget<TextField>(editor);
      expect(field.controller!.text, contains('Draft stays on refresh.'));
      await client.connect();
      await until(() => client.online);
      expect(
        tester.widget<TextField>(editor).controller!.text,
        contains('Draft stays on refresh.'),
      );
      await screenshot('native-user-memory-second-computer');
      expect(tester.takeException(), isNull);
      debugPrint('QA: native shared USER.md journey completed');
      client.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
