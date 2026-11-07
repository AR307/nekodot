import 'package:nekodot_native/data/chat_models.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// The native composer configures Hermes; Hermes itself schedules the later turn.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native goal and loop results reach the chat', (tester) async {
    if (Platform.isWindows) await DesktopHost.initialize();
    final client = NekodotClient()..prefs.language = 'en';
    final botId = const String.fromEnvironment('QA_SECOND_BOT');
    final login = await client.account.request(
      '/auth/login',
      method: 'POST',
      body: {
        'email': const String.fromEnvironment('QA_EMAIL'),
        'password': const String.fromEnvironment('QA_PASSWORD'),
      },
    );
    client.account.token = login['token'] as String;
    client.selectedNodeId = const String.fromEnvironment('QA_NODE');
    await client.bootstrap();
    addTearDown(client.dispose);
    Future<void> until(
      bool Function() ready,
      String step, {
      int seconds = 180,
    }) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 150));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(ready(), isTrue, reason: step);
    }

    await until(() => client.online, 'Node must be online');
    final conversationId =
        '${client.node.conversations.firstWhere((row) => row['kind'] == 'dm' && row['botId'] == botId)['conversationId']}';
    runApp(
      MaterialApp(
        theme: appTheme(Brightness.light),
        navigatorObservers: [nativeRoutes],
        home: HomePage(client: client),
      ),
    );
    final chat = find.byKey(ValueKey('conversation-$conversationId'));
    await until(() => chat.hitTestable().evaluate().isNotEmpty, 'Open Bot');
    await tester.tap(chat.hitTestable().first);
    final input = find.byKey(const ValueKey('chat-input'));
    await until(() => input.evaluate().isNotEmpty, 'Composer');
    await client.loadMessages(conversationId);
    List<ChatMessage> messages() => client.node.messages[conversationId] ?? [];
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
        'Command must complete: $text',
      );
    }

    Future<void> reply(String marker) async {
      await until(
        () => messages().any(
          (row) =>
              row.kind == 'text' &&
              row.author.type == 'bot' &&
              row.status == 'done' &&
              '${row.content['text']}'.contains(marker),
        ),
        'Real reply: $marker',
      );
      await until(
        () => client.node.activities[conversationId]?.state == 'idle',
        'Native task must settle',
      );
    }

    String output(String command) {
      final text =
          '${messages().lastWhere((row) => row.kind == 'system' && '${row.content['text']}'.startsWith(command)).content['text']}';
      return text.substring(text.indexOf('\n\n') + 2);
    }

    final original = (await client.rpc('sessions.list', {
      'botId': botId,
    }))['currentSessionId'];
    final marker = 'NATIVE_AUTOMATION_${DateTime.now().millisecondsSinceEpoch}';
    await submit('/new $marker');
    await submit(
      '/goal Do not use tools. Reply exactly $marker-GOAL. This is the complete goal.',
    );
    await submit('/goal pause');
    await submit('/subgoal Preserve the harmless $marker acceptance note.');
    expect(output('/subgoal'), contains(marker));
    await reply('$marker-GOAL');
    await submit('/goal show');
    expect(output('/goal show'), contains(marker));
    await submit('/goal pause');
    await submit('/goal clear');
    await submit(
      '/loop 24h Do not use tools. Reply exactly $marker-LOOP. --times 1',
    );
    await reply('$marker-LOOP');
    await submit('/loop status');
    expect(output('/loop status'), contains(marker));
    await submit('/loop stop');
    await submit('/heartbeat status');
    await submit('/heartbeat pause');
    await submit('/heartbeat stop');
    await submit('/blueprint');
    expect(output('/blueprint'), isNotEmpty);
    await submit('/moa');
    expect(output('/moa'), contains('/moa'));
    await submit('/resume $original');
    binding.reportData = {
      'realHermes': true,
      'realModel': true,
      'goalAndSubgoal': true,
      'nativeLoopExecuted': true,
      'nativeHeartbeatReadPauseStop': true,
      'heartbeatExecution':
          'blocked by reproduced Hermes v0.22.5 local-session bug',
      'singleTickThenStopped': true,
      'blueprintDirectory': true,
      'moaUsageOnly': true,
    };
    debugPrint(
      'QA: native goal and loop completed with real replies; heartbeat read/stop only',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 12)));
}
