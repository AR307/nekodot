import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/tasks.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/work.dart';
import 'package:nekodot_native/features/chat_composer.dart';
import 'package:nekodot_native/features/chat_timeline.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

// Replaces the removed manual-session-switch journey. All services and model calls are real.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('parallel work stays behind one Dot with one fixed activity line', (
    tester,
  ) async {
    if (Platform.isWindows) await DesktopHost.initialize();
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final c = NekodotClient()..prefs.language = 'en';
    const id = String.fromEnvironment('QA_CONVERSATION');
    const work = String.fromEnvironment('QA_WORK_DIR');
    const evidence = String.fromEnvironment('QA_EVIDENCE_DIR');
    final stamp = DateTime.now().millisecondsSinceEpoch.toString();
    final original = <String>{};
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
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
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
    original.addAll(c.node.tasks.keys);
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

    List<DotTask> created() => c.node.tasks.values
        .where((t) => t.conversationId == id && !original.contains(t.taskId))
        .toList();
    final activity = find.byKey(const ValueKey('dot-activity'));
    String statusLine() =>
        tester.widget<ThinkingRow>(find.byType(ThinkingRow)).line;
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

    final reuse = const bool.fromEnvironment('QA_SINGLE_DOT_REUSE');
    if (!reuse) {
      await send(
        '请同时帮我做两件事：A，读取 $work/input.txt，用前台代码等90秒，再把原内容和 SINGLE_A_$stamp 写到 $work/single-dot-A.txt；B，用真实代码计算1到100的平方和，前台等120秒后，把数值和 SINGLE_B_$stamp 写到 $work/single-dot-B.txt。两件事一起做，每件完成就告诉我实际结果，我期间还会继续和你聊天。',
      );
      await until(
        () => created().length == 2 && created().every((t) => t.active),
        'two real activities behind one Dot',
      );
      await checkPinned();
      for (final task in created()) {
        expect(statusLine(), contains(compactActivity(task.title)));
        expect(find.byKey(ValueKey('task-${task.taskId}')), findsNothing);
      }
      await shot('single-dot-parallel');
      await send('顺便直接告诉我2加3等于多少，在回答里带上 CHAT_SINGLE_$stamp。');
      await until(
        () => (c.node.messages[id] ?? []).any(
          (m) =>
              m.author.type == 'bot' &&
              m.taskRole != 'execution' &&
              m.status == 'done' &&
              '${m.content['text']}'.contains('CHAT_SINGLE_$stamp'),
        ),
        'Dot answers while both activities run',
      );
      expect(created(), hasLength(2));
      await until(
        () => created().every((t) => t.reportMessageId != null),
        'both outcomes delivered in main chat',
      );
      final reception = (c.node.messages[id] ?? [])
          .where(
            (m) =>
                m.author.type == 'bot' &&
                m.taskRole != 'execution' &&
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
      for (final task in created()) {
        final result = await tester.runAsync(
          () =>
              c.rpc('tasks.get', {'conversationId': id, 'taskId': task.taskId}),
        );
        expect(result, isNotNull);
      }
      await shot('single-dot-results');
    }

    // Notifications return to the same chat and never select an internal task.
    final latest = c.node.tasks.values.lastWhere(
      (t) => t.conversationId == id && t.reportMessageId != null,
    );
    c.destinations.add({
      'nodeId': c.selectedNodeId,
      'conversationId': id,
      'taskId': latest.taskId,
    });
    await tester.pump(const Duration(milliseconds: 700));
    await until(
      () => input.evaluate().isNotEmpty,
      'notification opens main chat',
    );
    expect(c.workspace['taskQuote:${c.selectedNodeId}:$id'], isNull);
    await shot('single-dot-notification');

    // Quoting ordinary text retains its hidden routing identity and clears it on cancel.
    final composer = tester.state<ChatComposerState>(find.byType(ChatComposer));
    c.workspace['taskQuote:${c.selectedNodeId}:$id'] = {
      'taskId': latest.taskId,
      'title': latest.title,
    };
    expect(composer.taskDraft, isNull);
    composer.quote('平方和结果', taskId: latest.taskId);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('平方和结果'), findsOneWidget);
    expect(
      c.workspace['taskQuote:${c.selectedNodeId}:$id']['taskId'],
      latest.taskId,
    );
    await tap(find.byTooltip('Cancel').last);
    expect(c.workspace['taskQuote:${c.selectedNodeId}:$id'], isNull);
    expect(composer.taskDraft, isNull);
    if (const bool.fromEnvironment('QA_SINGLE_DOT_QUOTE_ONLY')) {
      binding.reportData = {'realServices': true, 'quoteRouting': true};
      return;
    }

    // Real interaction card: both platforms receive and answer it in the main chat.
    final known = c.node.tasks.keys.toSet();
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
      () => c.node.tasks.values.any(
        (t) => !known.contains(t.taskId) && t.reportMessageId != null,
      ),
      'answer continues hidden execution and Dot reports',
    );
    await shot('single-dot-answer');

    await tap(find.byKey(const ValueKey('chat-flowchart')));
    await until(
      () => find.byKey(const ValueKey('flowchart-panel')).evaluate().isNotEmpty,
      'existing flow view opens',
    );
    await shot('single-dot-flow');
    await tap(find.byKey(const ValueKey('flow-close')));

    await tester.runAsync(
      () => c.prefs.update(locale: 'zh', appearance: 'dark'),
    );
    await tester.enterText(input, '保留这条未发送的草稿');
    final control = Uri.parse(const String.fromEnvironment('RELAY_URL'))
        .replace(port: 25494, path: '/', query: 'mode=node-offline');
    await tester.runAsync(() => http.get(control));
    try {
      await until(() => !c.online, 'isolated node offline', seconds: 30);
      expect(tester.widget<TextField>(input).controller!.text, '保留这条未发送的草稿');
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
    await shot('single-dot-final');
    expect(tester.takeException(), isNull);
    binding.reportData = {
      ...?binding.reportData,
      'realServices': true,
      'singleDot': true,
      'parallelTasks': created().map((t) => t.taskId).toList(),
      'fixedCombinedStatus': !reuse,
      'notificationInChat': true,
      'questionInChat': true,
    };
  }, timeout: const Timeout(Duration(minutes: 20)));
}
