import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/bot_details.dart';
import 'package:nekodot_native/features/bot_editor.dart';
import 'package:nekodot_native/features/chat.dart';
import 'package:nekodot_native/features/files.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/ui/design.dart';

/// Full native UI against real Node/Relay and recorded Hermes fixtures.
/// Start tests/support/native-replay.ts --journey. No paid model is used here.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'private/group chat, permissions, questions, steer, stop and files',
    (tester) async {
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      runApp(
        const MaterialApp(home: Scaffold(body: CircularProgressIndicator())),
      );
      final client = NekodotClient();
      await tester.runAsync(() async {
        final login = await client.request(
          '/auth/login',
          method: 'POST',
          body: {
            'email': const String.fromEnvironment('QA_EMAIL'),
            'password': const String.fromEnvironment('QA_PASSWORD'),
          },
        );
        // Keep the current user's secure storage untouched by this QA session.
        client.token = login['token'] as String;
        await client.bootstrap();
        await client.selectNode(const String.fromEnvironment('QA_NODE'));
      });

      Future<void> until(
        bool Function() ready, {
        Duration timeout = const Duration(seconds: 50),
      }) async {
        final end = DateTime.now().add(timeout);
        while (!ready() && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(
          ready(),
          isTrue,
          reason: 'Native product journey did not finish.',
        );
      }

      Future<void> tap(Finder finder) async {
        if (finder.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            finder,
            250,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(finder);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 300));
      }

      Future<void> fill(String label, String text) async {
        final field = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == label,
        );
        if (field.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            field,
            200,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(field);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.enterText(field, text);
        await tester.pump();
      }

      Future<Json> inspect() async =>
          object(jsonDecode((await http.get(client.url('/qa/inspect'))).body));

      var converted = false;
      Future<void> screenshot(String name) async {
        if (defaultTargetPlatform != TargetPlatform.android) return;
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 300));
        await binding.takeScreenshot(name);
      }

      await until(() => client.online && client.node.bots.length == 2);
      runApp(
        MaterialApp(
          theme: appTheme(Brightness.light),
          navigatorObservers: [nativeRoutes],
          home: HomePage(client: client),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      final bot = client.node.bots.firstWhere(
        (b) => b['handle'] == 'researcher',
      );
      final dm = client.node.conversations.firstWhere(
        (c) => c['botId'] == bot['botId'],
      );
      final id = dm['conversationId'] as String;
      final input = find.byKey(const ValueKey('chat-input'));
      await tap(find.byKey(ValueKey('conversation-$id')));
      await until(() => input.evaluate().isNotEmpty);
      await client.loadMessages(id);
      final initialBasicCount = client.node.messages[id]!
          .where(
            (m) =>
                m['author']['type'] == 'user' &&
                m['content']['text'] == 'runs-basic',
          )
          .length;
      final previousRuns = objects((await inspect())['runs'])
          .map((run) => run['runId'])
          .toSet();
      final previousGroups = client.node.groups
          .map((g) => g['groupId'])
          .toSet();

      // Saving an unrelated identity field must not replace the Hermes permission.
      await tap(find.byTooltip('详情'));
      await tap(find.byTooltip('编辑'));
      await until(() => find.text('原生智能审批').evaluate().isNotEmpty);
      await fill('名称', 'Maple updated');
      await tap(find.text('保存'));
      await until(() => find.byType(BotEditor).evaluate().isEmpty);
      expect((await inspect())['modes'][bot['botId']], 'smart');
      expect(find.widgetWithText(AppBar, 'Maple updated'), findsOneWidget);
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(BotDetails), findsNothing);

      // An accepted send must not erase text drafted while its response is in flight.
      await tester.enterText(input, 'runs-basic');
      await tester.pump();
      await tap(find.byTooltip('发送'));
      await tester.enterText(input, 'Next instruction draft');
      await tester.pump();
      final draftController = tester.widget<TextField>(input).controller!;
      expect(draftController.text, 'Next instruction draft');
      await until(() => client.node.activities[id]?['state'] == 'idle');
      await tester.pump(const Duration(seconds: 2));
      expect(
        identical(tester.widget<TextField>(input).controller, draftController),
        isTrue,
        reason: 'The open conversation must retain its input controller.',
      );
      expect(
        tester.widget<TextField>(input).controller!.text,
        'Next instruction draft',
      );
      final texts = client.node.messages[id]!.where(
        (m) => m['author']['type'] == 'user',
      );
      expect(
        texts.where((m) => m['content']['text'] == 'runs-basic'),
        hasLength(initialBasicCount + 1),
      );
      await tester.enterText(input, '');

      Future<void> send(String scenario) async {
        await tester.enterText(input, scenario);
        await tester.pump();
        await tap(find.byTooltip('发送'));
        await until(
          () => client.node.messages[id]!.any(
            (m) =>
                m['author']['type'] == 'user' &&
                m['content']['text'] == scenario,
          ),
        );
        await tester.pump(const Duration(seconds: 2));
      }

      await send('runs-clarify');
      await until(
        () => client.node.activities[id]?['state'] == 'waiting_question',
      );
      await tap(find.widgetWithText(CheckboxListTile, 'Amber (Recommended)'));
      await tester.enterText(input, 'Draft survives a pending question');
      await client.connect();
      await until(() => client.online && !client.node.syncing);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Amber (Recommended)'),
            )
            .value,
        isTrue,
      );
      expect(
        tester.widget<TextField>(input).controller!.text,
        'Draft survives a pending question',
      );
      await screenshot('native-product-question');
      await tap(find.text('提交回答'));
      await until(() => client.node.activities[id]?['state'] == 'idle');
      await tester.enterText(input, '');

      for (final scenario in ['runs-tools-approval', 'runs-approval-deny']) {
        await send(scenario);
        await until(
          () => client.node.activities[id]?['state'] == 'waiting_approval',
        );
        await screenshot('native-product-$scenario');
        await tap(
          find.text(scenario == 'runs-tools-approval' ? '允许一次' : '拒绝').last,
        );
        await until(() => client.node.activities[id]?['state'] == 'idle');
      }

      await send('runs-steer');
      await until(() => client.node.activities[id]?['state'] == 'tool');
      final runId = objects((await inspect())['runs']).singleWhere(
        (r) =>
            r['scenario'] == 'runs-steer' && !previousRuns.contains(r['runId']),
      )['runId'];
      await send('Use the updated instruction');
      await until(() => client.node.activities[id]?['state'] == 'idle');
      final steered = objects((await inspect())['runs']).singleWhere(
        (r) =>
            r['scenario'] == 'runs-steer' && !previousRuns.contains(r['runId']),
      );
      expect(steered['runId'], runId);
      expect(steered['steers'], ['Use the updated instruction']);
      expect(steered['toolStarts'], 1);

      await send('runs-stop');
      await until(() => client.node.activities[id]?['state'] == 'tool');
      await tap(find.text('停止'));
      await until(() => client.node.activities[id]?['state'] == 'idle');
      expect(
        client.node.messages[id]!.any((m) => m['status'] == 'cancelled'),
        isTrue,
      );

      await send('group-failed');
      await until(() => client.node.activities[id]?['state'] == 'idle');
      expect(
        client.node.messages[id]!.any((m) => m['status'] == 'failed'),
        isTrue,
      );
      await tester.enterText(input, 'Kept after error');
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byTooltip('发送'),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNotNull,
      );
      await screenshot('native-product-recovery');

      // The test specimen travels through the authenticated product file route.
      final file = objects(
        (await client.rpc('files.list', {'botId': bot['botId']}))['files'],
      ).single;
      expect(
        utf8.decode(await downloadFile(client, file['fileId'] as String)),
        contains('你好，nekodot'),
      );
      final navigator = Navigator.of(tester.element(find.byType(ChatPage)));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => FilePage(client: client, file: file),
        ),
      );
      await until(
        () => find.textContaining('你好，nekodot').evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await screenshot('native-product-file');
      if (const bool.fromEnvironment('QA_SYSTEM_SAVE')) {
        await tap(find.byTooltip('保存文件'));
        debugPrint('QA: system save dialog awaiting selection');
        await until(
          () => find.text('文件已保存').evaluate().isNotEmpty,
          timeout: const Duration(minutes: 3),
        );
      }
      await tap(
        find.descendant(
          of: find.byType(FilePage),
          matching: find.byType(BackButton),
        ),
      );
      await until(() => find.byType(FilePage).evaluate().isEmpty);
      if (!tester.widget<ChatPage>(find.byType(ChatPage)).embedded) {
        await tester.pageBack();
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tap(find.byTooltip('新建'));
      await tap(find.text('新建群组'));
      await fill('名称', 'Native team');
      await tap(find.widgetWithText(CheckboxListTile, 'Maple updated'));
      await tap(find.widgetWithText(CheckboxListTile, 'Willow'));
      await tap(find.text('保存'));
      await until(
        () => client.node.groups.any(
          (g) => !previousGroups.contains(g['groupId']),
        ),
      );
      await until(() => find.byType(BotEditor).evaluate().isEmpty);
      final group = client.node.conversations.firstWhere(
        (c) => c['kind'] == 'group' && !previousGroups.contains(c['groupId']),
      );
      final groupId = group['conversationId'] as String;
      await tap(find.byKey(ValueKey('conversation-$groupId')));
      await until(() => input.evaluate().isNotEmpty);
      await tester.enterText(input, '@');
      await tester.pump();
      await tap(find.widgetWithText(TextButton, 'Maple updated'));
      expect(tester.widget<TextField>(input).controller!.text, '@researcher ');
      await tester.enterText(input, '@researcher group relay');
      await tester.pump();
      await tap(find.byTooltip('发送'));
      await until(
        () =>
            (client.node.messages[groupId] ?? [])
                .where(
                  (m) =>
                      m['kind'] == 'text' &&
                      m['author']['type'] == 'bot' &&
                      m['status'] == 'done',
                )
                .length ==
            2,
      );
      await until(() => client.node.activities[groupId]?['state'] == 'idle');
      await until(() => tester.widget<TextField>(input).controller!.text.isEmpty);
      final groupRuns = objects((await inspect())['runs']).where(
        (r) =>
            ['group-researcher', 'group-writer'].contains(r['scenario']) &&
            !previousRuns.contains(r['runId']),
      );
      expect(groupRuns, hasLength(2));
      expect(groupRuns.map((r) => r['profile']).toSet(), hasLength(2));
      for (final run in groupRuns) {
        final privateConversation = client.node.conversations.singleWhere(
          (c) => c['kind'] == 'dm' && c['botId'] == run['profile'],
        );
        expect(
          run['sessionId'],
          'nk_dm_${privateConversation['conversationId']}',
        );
      }
      final before = client.node.messages[groupId]!
          .map((m) => m['messageId'])
          .toList();
      await client.connect();
      await until(() => client.online && !client.node.syncing);
      await client.loadMessages(groupId);
      expect(
        client.node.messages[groupId]!.map((m) => m['messageId']).toList(),
        before,
      );
      await screenshot('native-product-group');
      expect(tester.takeException(), isNull);
      debugPrint('QA: native product journey completed');
      client.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
