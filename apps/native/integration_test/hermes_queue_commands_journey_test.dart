import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/voice.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// Real native composer, native FIFO and a real model, including a pending approval.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native queued inputs survive edits, cancel and reconnect', (
    tester,
  ) async {
    if (Platform.isWindows) await DesktopHost.initialize();
    final client = NekodotClient()..language = 'en';
    final botId = const String.fromEnvironment('QA_SECOND_BOT');
    final login = await client.request(
      '/auth/login',
      method: 'POST',
      body: {
        'email': const String.fromEnvironment('QA_EMAIL'),
        'password': const String.fromEnvironment('QA_PASSWORD'),
      },
    );
    client.token = login['token'] as String;
    client.selectedNodeId = const String.fromEnvironment('QA_NODE');
    await client.bootstrap();
    addTearDown(client.dispose);
    Future<void> until(bool Function() ready, {int seconds = 180}) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 150));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(ready(), isTrue, reason: 'Real native FIFO journey timed out');
    }

    await until(() => client.online);
    final conversationId =
        '${client.node.conversations.firstWhere((row) => row['kind'] == 'dm' && row['botId'] == botId)['conversationId']}';
    runApp(
      MaterialApp(
        theme: appTheme(Brightness.light),
        navigatorObservers: [nativeRoutes],
        home: HomePage(client: client),
      ),
    );
    final conversation = find.byKey(ValueKey('conversation-$conversationId'));
    await until(() => conversation.hitTestable().evaluate().isNotEmpty);
    await tester.tap(conversation.hitTestable().first);
    final input = find.byKey(const ValueKey('chat-input'));
    await until(() => input.evaluate().isNotEmpty);
    await client.loadMessages(conversationId);
    List<Json> messages() => client.node.messages[conversationId] ?? [];
    final existingMessages = messages().map((row) => row['messageId']).toSet();
    Future<void> submit(String text) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(input);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.enterText(input, text);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<TextField>(input).controller!.text, text);
      final send = find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.tooltip == 'Send' &&
            widget.onPressed != null,
      );
      await until(() => send.hitTestable().evaluate().isNotEmpty);
      await tester.tap(send.hitTestable().first);
      await until(
        () => tester.widget<TextField>(input).controller!.text.isEmpty,
      );
    }

    final original = (await client.rpc('sessions.list', {
      'botId': botId,
    }))['currentSessionId'];
    final marker = 'NATIVE_FIFO_${DateTime.now().millisecondsSinceEpoch}';
    await submit('/new $marker');
    await submit(
      'Harmless queue test. Run terminal exactly once with python -c "import time; time.sleep(12)" in foreground, then reply exactly $marker-MAIN. Do not run other tools.',
    );
    await until(
      () => messages().any(
        (row) => row['kind'] == 'tool' && row['status'] == 'streaming',
      ),
    );
    // Pending approval deliberately holds the main turn while the queue is edited.
    await submit('/queue Do not use tools. Reply exactly $marker-OLD.');
    await submit('/queue Do not use tools. Reply exactly $marker-CANCEL.');
    expect(
      messages().where((row) => row['content']['queue'] == 'queued').length,
      2,
    );
    await submit('/queue list');
    int rank(String suffix) {
      final text =
          '${messages().lastWhere((row) => row['kind'] == 'system' && '${row['content']['text']}'.startsWith('/queue list'))['content']['text']}';
      final line = text
          .split('\n')
          .firstWhere((line) => line.contains('$marker-$suffix'));
      return int.parse(RegExp(r'^(\d+)\.').firstMatch(line)!.group(1)!);
    }

    await submit(
      '/queue edit ${rank('OLD')} Do not use tools. Reply exactly $marker-EDITED.',
    );
    await submit('/queue list');
    await submit('/queue rm ${rank('CANCEL')}');
    await until(
      () =>
          messages()
              .where(
                (row) =>
                    row['content']['queue'] == 'cancelled' &&
                    '${row['content']['text']}'.contains(marker),
              )
              .length ==
          2,
    );
    // The same pending admissions return after a new client socket; no submit is repeated.
    final queuedIds = messages()
        .where((row) => row['content']['queue'] != null)
        .map((row) => row['messageId'])
        .toSet();
    await client.connect();
    await until(() => client.ready);
    await client.synchronize(client.selectedNodeId!);
    await client.loadMessages(conversationId);
    expect(
      messages().map((row) => row['messageId']).toSet().containsAll(queuedIds),
      isTrue,
    );
    Future<void> allowCurrentTool() async {
      final approval = messages()
          .where(
            (row) =>
                !existingMessages.contains(row['messageId']) &&
                row['kind'] == 'approval' &&
                row['status'] == 'streaming',
          )
          .firstOrNull;
      if (approval == null) return;
      final allow = find.descendant(
        of: find.byKey(ValueKey(approval['messageId'])),
        matching: find.text('Allow once'),
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 300));
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
    }

    await allowCurrentTool();
    await until(
      () => messages().any(
        (row) =>
            row['kind'] == 'text' &&
            row['author']['type'] == 'bot' &&
            row['status'] == 'done' &&
            '${row['content']['text']}'.contains('$marker-EDITED'),
      ),
    );
    await until(
      () => client.node.activities[conversationId]?['state'] == 'idle',
    );
    final replies = messages()
        .where(
          (row) =>
              row['kind'] == 'text' &&
              row['author']['type'] == 'bot' &&
              '${row['content']['text']}'.contains(marker),
        )
        .toList();
    expect(replies.length, 2);
    expect('${replies.first['content']['text']}', contains('$marker-MAIN'));
    expect('${replies.last['content']['text']}', contains('$marker-EDITED'));
    expect(
      messages()
          .where(
            (row) =>
                row['content']['queue'] == 'running' &&
                '${row['content']['text']}'.contains(marker),
          )
          .length,
      1,
    );
    expect(
      messages().where(
        (row) =>
            !existingMessages.contains(row['messageId']) &&
            row['kind'] == 'approval' &&
            row['status'] == 'streaming',
      ),
      isEmpty,
      reason: 'A queued steer must not duplicate the running turn’s approval.',
    );
    final chatScroll = find
        .descendant(
          of: find.byKey(const ValueKey('chat-messages')),
          matching: find.byType(Scrollable),
        )
        .first;
    tester.state<ScrollableState>(chatScroll).position.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 300));
    final queueMessage = messages().firstWhere(
      (row) =>
          row['content']['queue'] == 'running' &&
          '${row['content']['text']}'.contains(marker),
    );
    await tester.scrollUntilVisible(
      find.byKey(ValueKey(queueMessage['messageId'])),
      240,
      scrollable: chatScroll,
      maxScrolls: 60,
    );
    expect(find.text('Queued task').evaluate(), isNotEmpty);
    await submit(
      'Run terminal once with python -c "import time; time.sleep(12)" in foreground. Then reply $marker-BEFORE-STEER unless I provide a newer instruction. No other tools.',
    );
    await until(
      () => messages().any(
        (row) => row['kind'] == 'tool' && row['status'] == 'streaming',
      ),
    );
    await submit(
      '/queue Do not use more tools. Change your final reply to exactly $marker-STEERED.',
    );
    await submit('/queue list');
    await submit('/queue steer ${rank('STEERED')}');
    await allowCurrentTool();
    await until(
      () => messages().any(
        (row) =>
            row['content']['queue'] == 'steered' &&
            '${row['content']['text']}'.contains('$marker-STEERED'),
      ),
    );
    await until(
      () => client.node.activities[conversationId]?['state'] == 'idle',
    );
    expect(
      messages()
          .where(
            (row) =>
                row['kind'] == 'text' &&
                row['author']['type'] == 'bot' &&
                row['status'] == 'done' &&
                '${row['content']['text']}'.contains('$marker-STEERED'),
          )
          .length,
      1,
    );
    if (Platform.isAndroid) {
      FocusManager.instance.primaryFocus?.unfocus();
      await until(() => tester.view.viewInsets.bottom == 0);
      await binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(milliseconds: 300));
      await binding.takeScreenshot('hermes-queue-android');
    }
    await submit('/nekodot-routine-status');
    expect(
      messages().lastWhere((row) => row['kind'] == 'system')['content']['text'],
      contains('/nekodot-routine-status'),
    );
    expect(
      messages().lastWhere((row) => row['kind'] == 'system')['content']['text'],
      isNot(contains('Plugin command error')),
    );
    await submit('/wake');
    await until(() => find.byType(VoicePage).evaluate().isNotEmpty);
    await until(
      () => find.textContaining('Wake word needs').evaluate().isNotEmpty,
    );
    expect(find.text('Listen for wake word'), findsOneWidget);
    expect(find.text('Record a message'), findsOneWidget);
    await tester.pageBack();
    await until(() => input.evaluate().isNotEmpty);
    await submit('/resume $original');
    binding.reportData = {
      ...?binding.reportData,
      'realHermes': true,
      'nativeFIFO': true,
      'enqueueEditCancel': true,
      'queuedSteer': true,
      'reconnectWithoutResubmit': true,
      'separateReplies': true,
      'pluginStatus': true,
      'voicePageNativeRequirements': true,
    };
    debugPrint(
      'QA: real native FIFO, edit, cancel, reconnect and plugin command passed',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 10)));
}
