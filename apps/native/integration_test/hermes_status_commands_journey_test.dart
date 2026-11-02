import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// Real native UI reading official Hermes state; intentionally invokes no model.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native status commands each show their actual Hermes response', (
    tester,
  ) async {
    if (Platform.isWindows) await DesktopHost.initialize();
    final c = NekodotClient()..language = 'en';
    final botId = const String.fromEnvironment('QA_BOT');
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
    Future<void> until(bool Function() ready, String step) async {
      final end = DateTime.now().add(const Duration(seconds: 90));
      while (!ready() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 120));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      expect(ready(), isTrue, reason: step);
    }

    await until(() => c.online, 'Actual Node online');
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
    await until(() => chat.hitTestable().evaluate().isNotEmpty, 'Open chat');
    await tester.tap(chat.hitTestable().first);
    final input = find.byKey(const ValueKey('chat-input'));
    await until(() => input.evaluate().isNotEmpty, 'Composer visible');
    await c.loadMessages(conversationId);
    final sessionId = (await c.rpc('sessions.list', {
      'botId': botId,
    }))['currentSessionId'];
    final beforeHistory = await c.rpc('sessions.history', {
      'botId': botId,
      'sessionId': sessionId,
    });
    final results = <Json>[];
    Future<String> submit(String command) async {
      final before = (c.node.messages[conversationId] ?? [])
          .map((r) => r['messageId'])
          .toSet();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(input);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.enterText(input, command);
      await tester.pump(const Duration(milliseconds: 250));
      final send = find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == 'Send' && w.onPressed != null,
      );
      await until(
        () => send.hitTestable().evaluate().isNotEmpty,
        'Send $command',
      );
      await tester.tap(send.hitTestable().first);
      await until(
        () => tester.widget<TextField>(input).controller!.text.isEmpty,
        'Command finished: $command',
      );
      final response = (c.node.messages[conversationId] ?? []).lastWhere(
        (r) =>
            !before.contains(r['messageId']) &&
            r['kind'] == 'system' &&
            '${r['content']['text']}'.startsWith('$command\n\n'),
      );
      final text = '${response['content']['text']}'.substring(
        command.length + 2,
      );
      expect(text.trim(), isNotEmpty, reason: command);
      expect(text, isNot(contains('Plugin command error')), reason: command);
      results.add({'command': command, 'actualResponse': true});
      debugPrint('QA STATUS: $command actual response displayed');
      return text;
    }

    for (final command in [
      '/help queue',
      '/status',
      '/context',
      '/context all',
      '/v',
      '/whoami',
      '/usage',
      '/insights 1',
      '/profile',
      '/diff',
      '/diff session',
      '/memory pending',
      '/kanban list',
      '/topup',
      '/suggestions',
      '/bundles',
      '/skills pending',
      '/skills diff',
      '/title',
      '/goal show',
      '/goal status',
      '/subgoal',
      '/loop status',
      '/heartbeat status',
      '/curator status',
      '/autoprune status',
      '/egress status',
      '/reasoning',
      '/voice status',
      '/approvals',
      '/codex-runtime',
      '/footer status',
      '/busy status',
      '/fast status',
      '/personality',
      '/toolsets',
      '/platforms',
      '/cron list',
      '/tools',
      '/tasks',
      '/reload-skills',
      '/reload',
      '/queue list',
      '/rollback list',
      '/browser status',
      '/reload-mcp',
      '/debug local',
      '/history',
      '/nekodot-routine-status',
    ]) {
      await submit(command);
    }
    // Native toggles are exercised and restored without submitting a model turn.
    final yolo = await submit('/yolo');
    final restoredYolo = await submit('/yolo');
    expect(restoredYolo, isNot(yolo));
    final levels = <String>{};
    for (var index = 0; index < 4; index++) {
      levels.add(await submit('/verbose'));
    }
    expect(levels.length, 4);
    final history = await c.rpc('sessions.history', {
      'botId': botId,
      'sessionId': sessionId,
    });
    expect(history['messages'], beforeHistory['messages']);
    binding.reportData = {
      'realHermes': true,
      'nativeClient': true,
      'modelInvoked': false,
      'nativeHistoryUnchanged': true,
      'localDiagnosticsReturned': true,
      'yoloToggleRestored': true,
      'verboseFullCycleRestored': true,
      'results': results,
    };
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 15)));
}
