import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/chat_models.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/main.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real clarification, approval, FIFO, steer and stop', (
    tester,
  ) async {
    const botId = String.fromEnvironment('QA_SECOND_BOT');
    const nodeId = String.fromEnvironment('QA_NODE');
    SharedPreferences.setMockInitialValues({
      'language': 'en',
      'theme': 'light',
      'notification-requested': true,
    });
    final c = NekodotClient(vault: MemoryVault());
    final capture = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: NekodotApp(client: c),
      ),
    );
    var stage = 'login';
    final passed = <String>[];
    Future<void> until(bool Function() ready, {int seconds = 180}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 120));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(ready(), isTrue, reason: 'Real controls journey: $stage');
    }

    Future<void> tap(Finder target) async {
      await until(() => target.evaluate().isNotEmpty);
      await Scrollable.ensureVisible(
        tester.element(target.first),
        alignment: .35,
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(target.first);
      await tester.pump(const Duration(milliseconds: 200));
    }

    Future<void> shot(String name) async {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        final image =
            await (capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Platform.isAndroid
            ? '${(await getExternalStorageDirectory())!.path}/controls-evidence'
            : const String.fromEnvironment('QA_EVIDENCE_DIR');
        await Directory(directory).create(recursive: true);
        await File('$directory/$name.png')
            .writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      });
    }

    await until(
      () => find.byKey(const ValueKey('auth-email')).evaluate().isNotEmpty,
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      const String.fromEnvironment('QA_EMAIL'),
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      const String.fromEnvironment('QA_PASSWORD'),
    );
    await tap(find.byKey(const ValueKey('auth-submit')));
    await until(() => c.connection.ready);
    await tester.runAsync(() => c.selectNode(nodeId));
    await until(() => c.online);
    final dm =
        c.node.conversations.firstWhere(
              (x) => x['kind'] == 'dm' && x['botId'] == botId,
            )['conversationId']
            as String;
    await tap(find.byKey(ValueKey('conversation-$dm')));
    await tester.runAsync(() => c.loadMessages(dm));
    List<ChatMessage> messages() => c.node.messages[dm] ?? [];
    Future<void> send(String text) async {
      await tap(find.byKey(const ValueKey('chat-input')));
      await tester.enterText(find.byKey(const ValueKey('chat-input')), text);
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chat-input')))
            .controller!
            .text,
        text,
      );
      debugPrint('QA send: $stage');
      await tap(find.byTooltip('Send'));
      await until(
        () => tester
            .widget<TextField>(find.byKey(const ValueKey('chat-input')))
            .controller!
            .text
            .isEmpty,
      );
    }

    Future<void> command(String value) async {
      var operation = await tester.runAsync(
        () => c.rpc('commands.execute', {
          'botId': botId,
          'conversationId': dm,
          'command': value,
          'clientMsgId': uid(),
        }),
      );
      while (operation!['status'] == 'running') {
        await tester.pump(const Duration(milliseconds: 200));
        operation = await tester.runAsync(
          () => c.rpc('operations.get', {
            'operationId': operation!['operationId'],
          }),
        );
      }
      expect(operation['status'], 'done');
      await tester.runAsync(() => c.loadMessages(dm));
    }

    Future<void> idle() => until(() => c.node.activities[dm]?.state == 'idle');
    final original = (await tester.runAsync(
      () => c.rpc('sessions.list', {'botId': botId}),
    ))!['currentSessionId'];
    final permission = (await tester.runAsync(
      () => c.rpc('bots.permissions.get', {'botId': botId}),
    ))!['mode'];
    await idle();
    final marker = 'CORE_CONTROL_${DateTime.now().millisecondsSinceEpoch}';
    final first = messages().map((m) => m.messageId).toSet();
    List<ChatMessage> recent() =>
        messages().where((m) => !first.contains(m.messageId)).toList();
    bool replied(String text) => recent().any(
      (m) =>
          m.kind == 'text' &&
          m.author.type == 'bot' &&
          m.status == 'done' &&
          '${m.content['text']}'.contains(text),
    );
    try {
      await tester.runAsync(
        () => c.rpc('bots.update', {'botId': botId, 'approvalMode': 'manual'}),
      );
      await command('/new $marker');
      stage = 'native clarification';
      await send(
        'Call the native clarify tool to ask me to choose TEAL or AMBER. Do not decide for me and do not ask only in plain text. After I answer, reply $marker-ANSWER and my choice.',
      );
      await until(
        () => recent().any(
          (m) => m.kind == 'question' && m.status == 'streaming',
        ),
      );
      final question = recent().firstWhere(
        (m) => m.kind == 'question' && m.status == 'streaming',
      );
      await shot('question-waiting');
      await tap(find.byKey(ValueKey('choice-${question.messageId}-0')));
      await until(() => replied('$marker-ANSWER'));
      await idle();
      passed.add('native question answered in original chat');

      stage = 'approval and queued input';
      await send(
        'Use terminal exactly once to run python -c "import time; time.sleep(5); print(37*41)" in the foreground. This is a harmless approval test. Then reply $marker-MAIN and the result. Do not use any other tool.',
      );
      await until(
        () => recent().any(
          (m) => m.kind == 'approval' && m.status == 'streaming',
        ),
      );
      final approval = recent().firstWhere(
        (m) => m.kind == 'approval' && m.status == 'streaming',
      );
      await shot('approval-waiting');
      await send('/queue Do not use tools. Reply exactly $marker-QUEUED.');
      await until(() => recent().any((m) => m.content['queue'] == 'queued'));
      final ids = messages().map((m) => m.messageId).toSet();
      await tester.runAsync(c.connection.connect);
      await until(() => c.connection.ready);
      await tester.runAsync(() => c.loadMessages(dm));
      expect(messages().map((m) => m.messageId).toSet(), containsAll(ids));
      await tap(find.byKey(ValueKey('choice-${approval.messageId}-0')));
      await until(() => replied('$marker-MAIN') && replied('$marker-QUEUED'));
      await idle();
      expect(
        recent()
            .where(
              (m) =>
                  m.kind == 'text' &&
                  m.author.type == 'bot' &&
                  '${m.content['text']}'.contains('$marker-QUEUED'),
            )
            .length,
        1,
      );
      passed.add('approval, native FIFO and reconnect without resubmission');

      stage = 'steer during actual tool';
      await tester.runAsync(
        () => c.rpc('bots.update', {'botId': botId, 'approvalMode': 'off'}),
      );
      await command('/new $marker-steer');
      await send(
        'Use terminal to run python -c "import time; time.sleep(18)" in foreground. Then reply $marker-BEFORE unless I give another instruction. Do not use any other tool.',
      );
      await until(
        () =>
            messages().any((m) => m.kind == 'tool' && m.status == 'streaming'),
      );
      await send(
        'Do not run any more tools. Change the final reply to exactly $marker-STEERED.',
      );
      await until(() => replied('$marker-STEERED'));
      await idle();
      passed.add('steer during real terminal execution');

      stage = 'stop active execution';
      await send(
        'Use terminal to run python -c "import time; time.sleep(40)" in foreground. Then reply $marker-NOT-EXPECTED. Do not start background processes.',
      );
      await until(
        () =>
            messages().any((m) => m.kind == 'tool' && m.status == 'streaming'),
      );
      await tap(find.byTooltip('Stop'));
      await idle();
      expect(replied('$marker-NOT-EXPECTED'), isFalse);
      await shot('stopped');
      passed.add('stop active tool without replay or fabricated final answer');
      debugPrint('QA real controls passed: ${passed.join('; ')}');
    } finally {
      if (c.node.activities[dm]?.state != 'idle') {
        await tester.runAsync(() => c.rpc('runs.stop', {'conversationId': dm}));
        await idle();
      }
      await tester.runAsync(
        () =>
            c.rpc('bots.update', {'botId': botId, 'approvalMode': permission}),
      );
      await command('/resume $original');
    }
    binding.reportData = {
      'realModel': 'gpt-6.1-sol',
      'platform': Platform.operatingSystem,
      'passed': passed,
    };
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 15)));
}
