import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:nekodot_native/data/chat_models.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/chat_composer.dart';
import 'package:nekodot_native/features/chat_activity.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

// Replaces the removed manual-session-switch journey. All services and model calls are real.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'one Dot works, talks and asks in one chat with one fixed activity line',
    (tester) async {
      if (Platform.isWindows) await DesktopHost.initialize();
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      final c = NekodotClient()..prefs.language = 'en';
      const id = String.fromEnvironment('QA_CONVERSATION');
      const work = String.fromEnvironment('QA_WORK_DIR');
      const evidence = String.fromEnvironment('QA_EVIDENCE_DIR');
      final stamp = DateTime.now().millisecondsSinceEpoch.toString();
      var androidSurfaceReady = false;
      Future<void> until(
        bool Function() ready,
        String label, {
        int seconds = 420,
      }) async {
        final deadline = DateTime.now().add(Duration(seconds: seconds));
        while (!ready() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 150));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 150)),
          );
        }
        expect(ready(), isTrue, reason: label);
        debugPrint('TASK_QA: $label');
      }

      Future<void> tap(Finder f) async {
        await until(() => f.evaluate().isNotEmpty, 'control $f', seconds: 30);
        await Scrollable.ensureVisible(tester.element(f.first), alignment: .5);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(f.first);
        await tester.pump(const Duration(milliseconds: 350));
      }

      Future<void> shot(String stage) async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        // Apply the measured composer height after its entrance animation.
        await tester.pump();
        if (Platform.isAndroid) {
          if (!androidSurfaceReady) {
            await binding.convertFlutterSurfaceToImage();
            androidSurfaceReady = true;
            await tester.pump();
          }
          await binding.takeScreenshot('tasks-android-$stage');
        } else {
          await tester.runAsync(() async {
            final view = tester.binding.renderViews.first;
            final image = await (view.debugLayer! as OffsetLayer).toImage(
              Offset.zero & view.flutterView.physicalSize,
            );
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('$evidence/tasks-windows-$stage.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }

      await tester.runAsync(() async {
        final login = await c.account.request(
          '/auth/login',
          method: 'POST',
          body: {
            'email': const String.fromEnvironment('QA_EMAIL'),
            'password': const String.fromEnvironment('QA_PASSWORD'),
          },
        );
        c.account.token = login['token'] as String;
        await c.bootstrap();
        await c.selectNode(const String.fromEnvironment('QA_NODE'));
      });
      addTearDown(c.dispose);
      await until(
        () => c.online && c.node.conversations.isNotEmpty,
        'real Node connected',
      );
      c.workspace['conversation:${c.selectedNodeId}'] = id;
      runApp(
        ListenableBuilder(
          listenable: c.prefs,
          builder: (_, child) => MaterialApp(
            theme: appTheme(
              c.prefs.theme == 'dark' ? Brightness.dark : Brightness.light,
            ),
            navigatorObservers: [nativeRoutes],
            builder: (_, child) => Ambient(child: child!),
            home: HomePage(client: c),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final input = find.byKey(const ValueKey('chat-input'));
      await until(
        () => input.evaluate().isNotEmpty,
        'restored conversation opened',
        seconds: 30,
      );
      Future<void> send(String text) async {
        await tester.enterText(input, text);
        await tap(find.byTooltip('Send'));
        await until(
          () => tester.widget<TextField>(input).controller!.text.isEmpty,
          'composer submitted',
        );
      }

      // Work in a private chat is the Dot's own turn: no task is created for it.
      // Work in a chat is the Dot's own turn: nothing is handed to another session.
      Iterable<ChatMessage> handedOff() =>
          (c.node.messages[id] ?? []).where((m) => m.taskRole == 'execution');
      bool working() => (c.node.activities[id]?.state ?? 'idle') != 'idle';
      final activity = find.byKey(const ValueKey('dot-activity'));
      Future<void> checkPinned() async {
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        expect(activity, findsOneWidget);
        expect(find.byType(ThinkingRow), findsOneWidget);
        expect(find.byKey(const ValueKey('work-status')), findsNothing);
        expect(find.text('Queued task'), findsNothing);
        expect(
          find.descendant(of: activity, matching: find.byType(InkWell)),
          findsNothing,
        );
        final history = find.byKey(const ValueKey('chat-messages'));
        expect(find.descendant(of: history, matching: activity), findsNothing);
        final position = tester.getRect(activity);
        await tester.drag(history, const Offset(0, 380));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        expect(tester.getRect(activity).top, closeTo(position.top, 1));
        expect(
          tester.getRect(activity).bottom,
          lessThan(tester.getRect(input).top),
        );
        await shot('single-dot-scrolled');
        if (find.byTooltip('Jump to latest').evaluate().isNotEmpty) {
          await tap(find.byTooltip('Jump to latest'));
        }
      }

      // What the Dot says while the same turn goes on arrives as commentary.
      bool replied(String marker) => (c.node.messages[id] ?? []).any(
        (m) =>
            m.author.type == 'bot' &&
            (m.kind == 'text' || m.kind == 'commentary') &&
            m.status == 'done' &&
            '${m.content['text']}'.contains(marker),
      );
      bool stamped(String path, String marker) =>
          File(path).existsSync() &&
          File(path).readAsStringSync().contains(marker);
      // Each line of thought the status line showed.
      final thoughts = <String>{};
      void watchThought() {
        final thought = c.node.activities[id]?.thought;
        if (thought != null) thoughts.add(thought);
      }

      c.node.addListener(watchThought);
      c.node.conversation(id).addListener(watchThought);
      addTearDown(() {
        c.node.removeListener(watchThought);
        c.node.conversation(id).removeListener(watchThought);
      });

      final reuse = const bool.fromEnvironment('QA_SINGLE_DOT_REUSE');
      if (!reuse) {
        await send(
          '请帮我做两件事：A，读取 $work/input.txt，用前台代码等90秒，再把原内容和 SINGLE_A_$stamp 写到 $work/single-dot-A.txt；B，用真实代码计算1到100的平方和，前台等120秒后，把数值和 SINGLE_B_$stamp 写到 $work/single-dot-B.txt。做完告诉我实际结果，我期间还会继续和你聊天。',
        );
        await until(working, 'the Dot works on it itself', seconds: 60);
        await until(
          () => c.node.activities[id]?.state == 'tool',
          'the Dot runs its own tools',
          seconds: 180,
        );
        await checkPinned();
        expect(handedOff(), isEmpty);
        expect(find.byKey(const ValueKey('flow-fold')), findsNothing);
        await shot('single-dot-working');
        // A message while it works interrupts that turn, and the Dot answers it.
        await send('顺便直接告诉我2加3等于多少，在回答里带上 CHAT_SINGLE_$stamp。');
        await until(
          () => replied('CHAT_SINGLE_$stamp'),
          'the Dot answers while working',
        );
        await until(
          () =>
              !working() &&
              stamped('$work/single-dot-A.txt', 'SINGLE_A_$stamp') &&
              stamped('$work/single-dot-B.txt', 'SINGLE_B_$stamp'),
          'both pieces of work done',
          seconds: 600,
        );
        expect(
          File('$work/single-dot-A.txt').readAsStringSync(),
          contains('SINGLE_A_$stamp'),
        );
        final b = File('$work/single-dot-B.txt').readAsStringSync();
        expect(b, contains('SINGLE_B_$stamp'));
        expect(b, contains('338350'));
        expect(handedOff(), isEmpty);
        final reception = (c.node.messages[id] ?? [])
            .where(
              (m) =>
                  m.author.type == 'bot' &&
                  DateTime.parse(m.createdAt).millisecondsSinceEpoch >=
                      int.parse(stamp),
            )
            .map((m) => '${m.content['text'] ?? ''}')
            .join('\n');
        expect(
          reception,
          isNot(
            matches(
              RegExp(
                r'已(?:创建|启动|分派).*任务|子代理|子任务|subagent|delegat|task[- ](?:id|created|started)',
                caseSensitive: false,
              ),
            ),
          ),
        );
        expect(
          (c.node.messages[id] ?? []).where((m) => m.taskRole == 'execution'),
          isEmpty,
        );
        debugPrint('TASK_QA: thoughts ${thoughts.length} ${thoughts.take(8)}');
        await shot('single-dot-results');
      }

      // A notification returns to the same chat.
      c.destinations.add({'nodeId': c.selectedNodeId, 'conversationId': id});
      await tester.pump(const Duration(milliseconds: 700));
      await until(
        () => input.evaluate().isNotEmpty,
        'notification opens main chat',
      );
      await shot('single-dot-notification');

      // Quoting words of a reply shows them above the draft; Cancel clears them.
      final composer = tester.state<ChatComposerState>(
        find.byType(ChatComposer),
      );
      composer.quote('平方和结果');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('平方和结果'), findsOneWidget);
      await tap(find.byTooltip('Cancel').last);
      expect(find.text('平方和结果'), findsNothing);

      // Real interaction card: the Dot asks in the chat and continues on the answer.
      await send(
        '请读 $work/input.txt，读完先用原生clarify问我想要短版还是长版，选项用短版、长版。等我选完再总结，最后带上 SINGLE_QUESTION_$stamp。',
      );
      await until(
        () => (c.node.messages[id] ?? []).any(
          (m) => m.kind == 'question' && m.status == 'streaming',
        ),
        'real question in main chat',
      );
      final question = c.node.messages[id]!.lastWhere(
        (m) => m.kind == 'question' && m.status == 'streaming',
      );
      await until(
        () => find
            .byKey(ValueKey('choice-${question.messageId}-0'))
            .evaluate()
            .isNotEmpty,
        'original answer control visible',
      );
      await checkPinned();
      await shot('single-dot-question');
      await tap(find.byKey(ValueKey('choice-${question.messageId}-0')));
      await until(
        () => replied('SINGLE_QUESTION_$stamp') && !working(),
        'the answer continues the same work and the Dot replies',
      );
      expect(handedOff(), isEmpty);
      await shot('single-dot-answer');

      await tap(find.byKey(const ValueKey('chat-flowchart')));
      await until(
        () =>
            find.byKey(const ValueKey('flowchart-panel')).evaluate().isNotEmpty,
        'existing flow view opens',
      );
      await shot('single-dot-flow');
      await tap(find.byKey(const ValueKey('flow-close')));

      // A draft survives the Node going offline, where the harness can take it
      // offline (QA_OFFLINE_CONTROL).
      const offline = String.fromEnvironment('QA_OFFLINE_CONTROL');
      if (offline.isNotEmpty) {
        await tester.runAsync(
          () => c.prefs.update(locale: 'zh', appearance: 'dark'),
        );
        await tester.enterText(input, '保留这条未发送的草稿');
        final control = Uri.parse(offline);
        await tester.runAsync(
          () => http.get(control.replace(query: 'mode=node-offline')),
        );
        try {
          await until(() => !c.online, 'isolated node offline', seconds: 30);
          expect(
            tester.widget<TextField>(input).controller!.text,
            '保留这条未发送的草稿',
          );
          await shot('single-dot-offline-dark');
        } finally {
          await tester.runAsync(
            () => http.get(control.replace(query: 'mode=node-online')),
          );
        }
        await until(() => c.online, 'node recovered', seconds: 45);
        expect(tester.widget<TextField>(input).controller!.text, '保留这条未发送的草稿');
        await tester.enterText(input, '');
        await tester.runAsync(
          () => c.prefs.update(locale: 'en', appearance: 'light'),
        );
      }
      await shot('single-dot-final');
      expect(tester.takeException(), isNull);
      binding.reportData = {
        ...?binding.reportData,
        'realServices': true,
        'singleDot': true,
        'handedOff': handedOff().length,
        'thoughtsShown': thoughts.length,
        'notificationInChat': true,
        'questionInChat': true,
        'offlineDraft': offline.isNotEmpty,
      };
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
