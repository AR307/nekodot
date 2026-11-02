import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// Real model-created processes and children, controlled from the candidate UI.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native running commands with real tools and child agents', (
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
    c.token = login['token'];
    c.selectedNodeId = const String.fromEnvironment('QA_NODE');
    await c.bootstrap();
    addTearDown(c.dispose);
    Future<void> until(bool Function() ready, {int seconds = 120}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 150));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(ready(), isTrue, reason: 'Real running-command journey timed out');
    }

    Future<void> tap(Finder target) async {
      await until(() => target.hitTestable().evaluate().isNotEmpty);
      await tester.tap(target.hitTestable().first);
    }

    await until(() => c.online);
    final conversationId =
        '${c.node.conversations.firstWhere((r) => r['kind'] == 'dm' && r['botId'] == botId)['conversationId']}';
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
    await tap(find.byKey(ValueKey('conversation-$conversationId')));
    final input = find.byKey(const ValueKey('chat-input'));
    await until(() => input.evaluate().isNotEmpty);
    await c.loadMessages(conversationId);
    await until(() => c.node.activities[conversationId]?['state'] == 'idle');
    List<Json> messages() => c.node.messages[conversationId] ?? [];
    Future<void> send(String text) async {
      await tap(input);
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
      await tap(find.byTooltip('Send'));
    }

    Future<String> command(String text, String expected) async {
      final before = messages().map((r) => r['messageId']).toSet();
      await send(text);
      await until(
        () => messages().any(
          (r) =>
              !before.contains(r['messageId']) &&
              r['kind'] == 'system' &&
              '${r['content']['text']}'.startsWith(text) &&
              '${r['content']['text']}'.contains(expected),
        ),
      );
      await until(
        () => tester.widget<TextField>(input).controller!.text.isEmpty,
      );
      return '${messages().firstWhere((r) => !before.contains(r['messageId']) && r['kind'] == 'system' && '${r['content']['text']}'.startsWith(text))['content']['text']}';
    }

    Future<void> answer(String text, String expected) async {
      final before = messages().map((r) => r['messageId']).toSet();
      await send(text);
      await until(
        () => messages().any(
          (r) =>
              !before.contains(r['messageId']) &&
              r['author']['type'] == 'bot' &&
              r['status'] == 'done' &&
              '${r['content']['text']}'.contains(expected),
        ),
        seconds: 240,
      );
      await until(() => c.node.activities[conversationId]?['state'] == 'idle');
    }

    final original = (await c.rpc('sessions.list', {
      'botId': botId,
    }))['currentSessionId'];
    final marker = 'LIVE_CONTROL_${DateTime.now().millisecondsSinceEpoch}';
    final settings = objects(
      (await c.rpc('hermes.settings.get', {'botId': botId}))['fields'],
    );
    final protection = {
      for (final key in [
        'compression.protect_first_n',
        'compression.protect_last_n',
      ])
        key: settings.firstWhere((r) => r['key'] == key)['value'],
    };
    try {
      for (final key in protection.keys) {
        await c.rpc('hermes.settings.set', {
          'botId': botId,
          'key': key,
          'value': key.endsWith('first_n') ? 1 : 2,
        });
      }
      await command('/new $marker', 'New Hermes session:');
      final tools = await command('/tools', 'Hermes tools (');
      expect(tools, contains('terminal:'));
      expect(tools, contains('delegate_task:'));
      final model = c.node.bots.firstWhere((r) => r['botId'] == botId)['model'];
      await command('/model $model', 'Hermes session model');
      await command(
        '/wake status',
        'Client microphone capture is not connected',
      );
      await answer(
        '/plan Make a two-point plan for checking a harmless text file. Include $marker-PLAN. Do not use tools or write files.',
        '$marker-PLAN',
      );
      debugPrint(
        'QA RUNNING: native plan directive produced a real model answer',
      );

      await answer(
        'For isolated command acceptance, use terminal once to launch `sleep 120` with background=true. Do not wait, kill it or start any other command. Reply exactly $marker-PROCESS after the background process was started.',
        '$marker-PROCESS',
      );
      final processes = await command('/agents', 'Process ');
      final processId = RegExp(r'Process (\S+) \[running\]')
          .firstMatch(processes)
          ?.group(1);
      expect(
        processId,
        isNotNull,
        reason: 'A real background process must be visible',
      );
      await command(
        '/agents kill $processId',
        'Native session process: killed',
      );
      final stopped = await command('/agents', 'Process $processId [exited]');
      expect(stopped, contains('Process $processId [exited]'));
      await command('/stop', 'background processes and');
      debugPrint(
        'QA RUNNING: native process identifier, kill and stop verified',
      );

      await answer(
        'For isolated command acceptance, call delegate_task exactly once to spawn one child. The child goal is: "Use terminal once to run `sleep 90` in foreground, then reply $marker-CHILD. Do not delegate." After spawning, do not wait or stop the child. Reply exactly $marker-PARENT.',
        '$marker-PARENT',
      );
      final roster = await command('/agents', 'Agent ');
      final child = RegExp(r'Agent (\S+) \[running\]')
          .firstMatch(roster)
          ?.group(1);
      expect(child, isNotNull, reason: 'A real child agent must be visible');
      await command('/agents tail $child', 'subagent_id');
      await command(
        '/agents steer $child After waiting, include $marker-CHILD-STEER.',
        'Native subagent steer: queued',
      );
      await command('/agents stop $child', 'Native subagent interrupted.');
      await command('/agents pause', 'Hermes delegation spawning: paused');
      await command('/agents resume', 'Hermes delegation spawning: enabled');
      debugPrint(
        'QA RUNNING: actual child tail, steer, interrupt and spawning controls verified',
      );

      final beforeSteer = messages().map((r) => r['messageId']).toSet();
      await send(
        'Call terminal exactly once to run `sleep 30` in foreground. After it returns, reply $marker-ORIGINAL. Do not delegate or start background processes.',
      );
      await until(() => c.node.activities[conversationId]?['state'] == 'tool');
      await command(
        '/steer After the wait reply exactly $marker-STEER instead.',
        'Hermes steer: queued',
      );
      await until(
        () => messages().any(
          (r) =>
              !beforeSteer.contains(r['messageId']) &&
              r['author']['type'] == 'bot' &&
              r['status'] == 'done' &&
              '${r['content']['text']}'.contains('$marker-STEER'),
        ),
        seconds: 180,
      );
      await until(() => c.node.activities[conversationId]?['state'] == 'idle');
      expect(
        messages().where(
          (r) =>
              !beforeSteer.contains(r['messageId']) &&
              r['kind'] == 'tool' &&
              r['content']['tool'] == 'terminal',
        ),
        hasLength(1),
      );
      final beforeStop = messages().map((r) => r['messageId']).toSet();
      await send(
        'Call terminal once to run `sleep 90` in foreground, then reply $marker-STOP. Do not delegate.',
      );
      await until(() => c.node.activities[conversationId]?['state'] == 'tool');
      await tap(find.byTooltip('Stop'));
      await until(() => c.node.activities[conversationId]?['state'] == 'idle');
      expect(
        messages().any(
          (r) =>
              !beforeStop.contains(r['messageId']) &&
              r['status'] == 'cancelled',
        ),
        isTrue,
      );
      debugPrint(
        'QA RUNNING: actual main-turn slash steer and distinct Stop button verified',
      );
      final active = (await c.rpc('sessions.list', {
        'botId': botId,
      }))['currentSessionId'];
      final historyBefore = await c.rpc('sessions.history', {
        'botId': botId,
        'sessionId': active,
      });
      await command(
        '/compress Keep the harmless acceptance markers.',
        'Hermes compression (applied)',
      );
      final historyAfter = await c.rpc('sessions.history', {
        'botId': botId,
        'sessionId': active,
      });
      expect(
        objects(historyAfter['messages']).length,
        lessThan(objects(historyBefore['messages']).length),
      );
      debugPrint(
        'QA RUNNING: actual native model compression reduced the session history',
      );
      binding.reportData = {
        'realHermes': true,
        'nativePlanRealModel': true,
        'nativeProcessKill': true,
        'nativeChildTailSteerInterrupt': true,
        'delegationPauseResume': true,
        'mainTurnSlashSteer': true,
        'mainTurnStopButton': true,
        'sessionModelPick': true,
        'realModelCompression': true,
        'wake': 'status only; App microphone capture not connected',
      };
    } finally {
      // Only this isolated session's background work is stopped; history stays.
      if (c.node.activities[conversationId]?['state'] != 'idle') {
        await c.rpc('runs.stop', {'conversationId': conversationId});
        await until(
          () => c.node.activities[conversationId]?['state'] == 'idle',
        );
      }
      await command('/stop', 'background processes and');
      await command('/agents resume', 'Hermes delegation spawning: enabled');
      for (final entry in protection.entries) {
        await c.rpc('hermes.settings.set', {
          'botId': botId,
          'key': entry.key,
          'value': entry.value,
        });
      }
      await command('/resume $original', 'Resumed Hermes session:');
    }
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 15)));
}
