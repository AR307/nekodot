import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// Real native commands author a skill, review work and refine the actual profile.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('learn, init, review and refine use the real Hermes session', (
    tester,
  ) async {
    if (Platform.isWindows) await DesktopHost.initialize();
    final c = NekodotClient()..language = 'en';
    final botId = const String.fromEnvironment('QA_SECOND_BOT');
    final login = await c.request(
      '/auth/login',
      method: 'POST',
      body: {
        'email': const String.fromEnvironment('QA_EMAIL'),
        'password': const String.fromEnvironment('QA_PASSWORD'),
      },
    );
    c.token = login['token'] as String;
    c.selectedNodeId = const String.fromEnvironment('QA_NODE');
    await c.bootstrap();
    addTearDown(c.dispose);
    Future<void> Function()? allowPending;
    Future<void> until(
      bool Function() ready,
      String step, {
      int seconds = 300,
    }) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 150));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (allowPending != null) await allowPending();
      }
      expect(ready(), isTrue, reason: step);
    }

    await until(() => c.online, 'Node online');
    final conversationId =
        '${c.node.conversations.firstWhere((r) => r['kind'] == 'dm' && r['botId'] == botId)['conversationId']}';
    runApp(
      MaterialApp(
        theme: appTheme(Brightness.light),
        navigatorObservers: [nativeRoutes],
        home: HomePage(client: c),
      ),
    );
    final chat = find.byKey(ValueKey('conversation-$conversationId'));
    await until(() => chat.hitTestable().evaluate().isNotEmpty, 'Open Bot');
    await tester.tap(chat.hitTestable().first);
    final input = find.byKey(const ValueKey('chat-input'));
    await until(() => input.evaluate().isNotEmpty, 'Composer');
    await c.loadMessages(conversationId);
    List<Json> messages() => c.node.messages[conversationId] ?? [];
    final before = messages().map((r) => r['messageId']).toSet();
    final allowed = <Object?>{};
    allowPending = () async {
      final approval = messages()
          .where(
            (r) =>
                !before.contains(r['messageId']) &&
                !allowed.contains(r['messageId']) &&
                r['kind'] == 'approval' &&
                r['status'] == 'streaming',
          )
          .firstOrNull;
      if (approval == null) return;
      final allow = find.descendant(
        of: find.byKey(ValueKey(approval['messageId'])),
        matching: find.text('Allow once'),
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.scrollUntilVisible(
        allow,
        240,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('chat-messages')),
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 60,
      );
      await tester.ensureVisible(allow.last);
      await tester.tap(allow.last);
      allowed.add(approval['messageId']);
    };
    Future<void> submit(String text) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(input);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.enterText(input, text);
      await tester.pump(const Duration(milliseconds: 300));
      final send = find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == 'Send' && w.onPressed != null,
      );
      await until(() => send.hitTestable().evaluate().isNotEmpty, 'Send $text');
      await tester.tap(send.hitTestable().first);
      await until(
        () => tester.widget<TextField>(input).controller!.text.isEmpty,
        'Command accepted: $text',
      );
    }

    Future<void> reply(String marker) async {
      await until(
        () => messages().any(
          (r) =>
              r['kind'] == 'text' &&
              r['author']['type'] == 'bot' &&
              r['status'] == 'done' &&
              '${r['content']['text']}'.contains(marker),
        ),
        'Real reply: $marker',
      );
      await until(
        () => c.node.activities[conversationId]?['state'] == 'idle',
        'Native run settled',
      );
    }

    final original = (await c.rpc('sessions.list', {
      'botId': botId,
    }))['currentSessionId'];
    final fields = objects(
      (await c.rpc('hermes.settings.get', {'botId': botId}))['fields'],
    );
    final cwd = fields.firstWhere((r) => r['key'] == 'terminal.cwd')['value'];
    final marker = 'NATIVE_LEARNING_${DateTime.now().millisecondsSinceEpoch}';
    final skillName = 'native-learn-${DateTime.now().millisecondsSinceEpoch}';
    try {
      await c.rpc('hermes.settings.set', {
        'botId': botId,
        'key': 'terminal.cwd',
        'value': const String.fromEnvironment('QA_WORKTREE_PATH'),
      });
      await submit('/new $marker');
      await submit('/worktree new $skillName');
      await submit(
        '/init Inspect only this isolated workspace. Create or update its AGENTS.md with concise project guidance. Do not delete anything. End your final answer with $marker-INIT.',
      );
      await reply('$marker-INIT');
      expect(
        messages().any((r) => r['kind'] == 'tool' && r['status'] == 'done'),
        isTrue,
      );
      debugPrint('QA LEARN: /init finished in an isolated native worktree');
      await submit(
        '/learn Create a portable skill named $skillName from this harmless workflow: read a tiny project README, identify its purpose, then give a three-point summary. Use skill_manage to save the real skill, do not merely describe it. Include verification and no destructive actions. End your final answer with $marker-LEARN.',
      );
      await reply('$marker-LEARN');
      final content = await c.rpc('extensions.content', {
        'kind': 'skills',
        'botId': botId,
        'name': skillName,
      });
      expect('${content['content']}', contains('name: $skillName'));
      final other = const String.fromEnvironment('QA_BOT');
      final catalog = objects(
        (await c.rpc('extensions.list', {'kind': 'skills'}))['entries'],
      );
      final learned = catalog.firstWhere((r) => r['name'] == skillName);
      expect(
        objects(learned['states'])
            .any((r) => r['botId'] == other && r['installed'] == true),
        isFalse,
      );
      debugPrint(
        'QA LEARN: actual SKILL.md read back; other profile remains isolated',
      );
      final beforeReview = messages().map((r) => r['messageId']).toSet();
      await submit(
        '/review Review only the harmless README-summary workflow and this isolated workspace AGENTS.md. No external services, no modifications or deletion. Include the exact marker $marker-REVIEW in your conclusion.',
      );
      await until(
        () => messages().any(
          (r) =>
              !beforeReview.contains(r['messageId']) &&
              r['author']['type'] == 'bot' &&
              r['status'] == 'done' &&
              '${r['content']['text']}'.contains('$marker-REVIEW'),
        ),
        'Native background review result must reach App',
        seconds: 480,
      );
      await until(
        () => c.node.activities[conversationId]?['state'] == 'idle',
        'Review settled',
      );
      debugPrint('QA LEARN: actual native background review returned to chat');
      final beforeRefine = messages().map((r) => r['messageId']).toSet();
      const refineCommand =
          '/refine Review the harmless README-summary workflow. Keep personal identity and USER.md unchanged; do not remove anything. Retain reusable project-summary lessons only if useful.';
      await submit(refineCommand);
      await until(
        () => messages().any(
          (r) =>
              !beforeRefine.contains(r['messageId']) &&
              r['kind'] == 'system' &&
              '${r['content']['text']}'.startsWith('$refineCommand\n\n'),
        ),
        'Completed refine result must reach App',
      );
      final result = messages().lastWhere(
        (r) =>
            !beforeRefine.contains(r['messageId']) &&
            r['kind'] == 'system' &&
            '${r['content']['text']}'.startsWith('$refineCommand\n\n'),
      );
      expect(
        '${result['content']['text']}'
            .substring(refineCommand.length + 2)
            .toLowerCase(),
        anyOf(contains('review'), contains('skill'), contains('memory')),
      );
      final memory = await c.rpc('memory.get', {'botId': botId});
      expect(memory['documents'], isNotEmpty);
      debugPrint(
        'QA LEARN: /refine completed through the native review operation',
      );
    } finally {
      await c.rpc('hermes.settings.set', {
        'botId': botId,
        'key': 'terminal.cwd',
        'value': cwd,
      });
      if (c.node.activities[conversationId]?['state'] == 'idle') {
        await submit('/resume $original');
      }
    }
    binding.reportData = {
      'realHermes': true,
      'realModel': true,
      'initInIsolatedWorktree': true,
      'learnedSkillReadBack': true,
      'profileIsolation': true,
      'backgroundReviewReturned': true,
      'refineCompleted': true,
    };
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 25)));
}
