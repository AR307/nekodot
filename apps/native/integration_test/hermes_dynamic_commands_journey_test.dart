import 'package:nekodot_native/data/chat_models.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// Every installed skill is invoked by the real App and a real model. This
/// checks loading/dispatch, not third-party credentials or each skill's workflow.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('every dynamic skill command loads into a real native turn', (
    tester,
  ) async {
    if (Platform.isWindows) await DesktopHost.initialize();
    final c = NekodotClient()..prefs.language = 'en';
    final botId = const String.fromEnvironment('QA_SECOND_BOT');
    final login = await c.account.request(
      '/auth/login',
      method: 'POST',
      body: {
        'email': const String.fromEnvironment('QA_EMAIL'),
        'password': const String.fromEnvironment('QA_PASSWORD'),
      },
    );
    c.account.token = login['token'];
    c.selectedNodeId = const String.fromEnvironment('QA_NODE');
    await c.bootstrap();
    addTearDown(c.dispose);
    Future<void> until(bool Function() ready, {int seconds = 90}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 150));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(ready(), isTrue, reason: 'Dynamic command did not settle');
    }

    await until(() => c.online && c.node.bots.length >= 2);
    final conversationId =
        '${c.node.conversations.firstWhere((row) => row['kind'] == 'dm' && row['botId'] == botId)['conversationId']}';
    final original = (await c.rpc('sessions.list', {
      'botId': botId,
    }))['currentSessionId'];
    final catalog = objects(
      (await c.rpc('commands.list', {'botId': botId}))['commands'],
    );
    final skills = catalog.where((row) => row['skill'] == true).toList();
    expect(skills, isNotEmpty);
    runApp(
      MaterialApp(
        theme: appTheme(Brightness.light),
        navigatorObservers: [nativeRoutes],
        builder: (context, child) => Platform.isWindows
            ? WindowChrome(child: child!)
            : Ambient(child: child!),
        home: HomePage(client: c),
      ),
    );
    final conversation = find.byKey(ValueKey('conversation-$conversationId'));
    await until(() => conversation.hitTestable().evaluate().isNotEmpty);
    await tester.tap(conversation.hitTestable().first);
    final input = find.byKey(const ValueKey('chat-input'));
    await until(() => input.evaluate().isNotEmpty);
    await c.loadMessages(conversationId);
    List<ChatMessage> messages() => c.node.messages[conversationId] ?? [];
    Future<void> send(String text) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(input);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.enterText(input, text);
      await tester.pump(const Duration(milliseconds: 250));
      await until(
        () => find
            .byWidgetPredicate(
              (w) =>
                  w is IconButton && w.tooltip == 'Send' && w.onPressed != null,
            )
            .evaluate()
            .isNotEmpty,
      );
      await tester.tap(find.byTooltip('Send'));
    }

    Future<void> command(String text, String expected) async {
      final before = messages().map((row) => row.messageId).toSet();
      await send(text);
      await until(
        () => messages().any(
          (row) =>
              !before.contains(row.messageId) &&
              row.kind == 'system' &&
              '${row.content['text']}'.contains(expected),
        ),
      );
      await until(
        () => tester.widget<TextField>(input).controller!.text.isEmpty,
      );
    }

    final results = <Json>[];
    for (final skill in skills) {
      final name = '${skill['name']}';
      await until(() => c.node.activities[conversationId]?.state == 'idle');
      await command('/new Skill dispatch QA $name', 'New Hermes session:');
      final before = messages().map((row) => row.messageId).toSet();
      final marker = 'SKILL_LOADED_${results.length + 1}';
      await send(
        '$name Acceptance is limited to loading this skill, NOT performing its workflow. '
        'Do not call tools, contact external services, create/edit/delete any files, or change settings. '
        'Acknowledge that its instructions are available by replying exactly $marker.',
      );
      await until(
        () =>
            messages().any(
              (row) =>
                  !before.contains(row.messageId) &&
                  row.author.type == 'bot' &&
                  ['done', 'failed', 'cancelled'].contains(row.status),
            ) &&
            c.node.activities[conversationId]?.state == 'idle',
        seconds: 240,
      );
      final added = messages()
          .where((row) => !before.contains(row.messageId))
          .toList();
      final reply = added.lastWhere((row) => row.author.type == 'bot');
      final passed =
          reply.status == 'done' &&
          '${reply.content['text']}'.contains(marker) &&
          !added.any((row) => row.kind == 'tool');
      results.add({'command': name, 'loadedAndModelReplied': passed});
      debugPrint('QA DYNAMIC: $name ${passed ? 'passed' : 'failed'}');
    }
    await command('/resume $original', 'Resumed Hermes session:');
    binding.reportData = {
      'realHermes': true,
      'scope': 'skill loading and real model dispatch; not external workflows',
      'results': results,
    };
    expect(
      results.where((row) => row['loadedAndModelReplied'] != true),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 40)));
}
