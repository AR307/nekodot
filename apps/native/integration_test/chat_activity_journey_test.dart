import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:nekodot_native/data/chat_models.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/chat_activity.dart';
import 'package:nekodot_native/features/chat_message.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/chat_composer.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/connection_notice.dart';
import 'package:nekodot_native/ui/design.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

// Native UI, actual isolated Node/Relay/Hermes and model. No event injection.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('activity remains docked across real tasks and navigation', (
    tester,
  ) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    SharedPreferences.setMockInitialValues({'notification-requested': true});
    final c = NekodotClient(vault: MemoryVault());
    final nav = GlobalKey<NavigatorState>();
    final reducedMotion = ValueNotifier(false);
    final phone = Platform.isAndroid;
    const dm = String.fromEnvironment('QA_CONVERSATION');
    const evidence = String.fromEnvironment('QA_EVIDENCE_DIR');
    const work = String.fromEnvironment('QA_WORK_DIR');
    final suffix = phone ? 'android' : 'windows';
    var converted = false;
    addTearDown(c.dispose);
    addTearDown(reducedMotion.dispose);

    Future<void> frames([int ms = 400]) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 40));
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }

    Future<void> until(bool Function() ready, String label) async {
      final end = DateTime.now().add(const Duration(seconds: 240));
      while (!ready() && DateTime.now().isBefore(end)) {
        await frames(150);
      }
      expect(ready(), isTrue, reason: label);
      debugPrint('ACTIVITY verified $label');
    }

    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder.first);
      await tester.tap(finder.hitTestable().first);
      await frames();
      expect(tester.takeException(), isNull);
    }

    Future<void> shot(String name) async {
      await frames(500);
      expect(tester.takeException(), isNull);
      if (phone) {
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
          await tester.pump();
        }
        await binding.takeScreenshot('activity-$suffix-$name');
      } else {
        final view = tester.binding.renderViews.first;
        final image = await (view.debugLayer! as OffsetLayer).toImage(
          Offset.zero & view.flutterView.physicalSize,
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(evidence).create(recursive: true);
        await File('$evidence/activity-$suffix-$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }
    }

    if (!phone) {
      await DesktopHost.initialize();
      await windowManager.setTitle('nekodot Activity QA');
      await windowManager.show();
      tester.view.physicalSize = const Size(1200, 850);
      tester.view.devicePixelRatio = 1;
    }
    await c.prefs.update(locale: 'zh', appearance: 'light');
    await c.login(
      const String.fromEnvironment('QA_EMAIL'),
      const String.fromEnvironment('QA_PASSWORD'),
    );
    await c.selectNode(const String.fromEnvironment('QA_NODE'));
    await until(
      () => c.online && c.node.bots.isNotEmpty,
      'real services connected',
    );
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: Listenable.merge([c.prefs, reducedMotion]),
        builder: (_, child) => MaterialApp(
          navigatorKey: nav,
          navigatorObservers: [nativeRoutes],
          debugShowCheckedModeBanner: false,
          theme: appTheme(
            c.prefs.theme == 'dark' ? Brightness.dark : Brightness.light,
            glass: phone,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reducedMotion.value),
            child: ConnectionNotice(
              client: c,
              child: phone
                  ? Ambient(child: child!)
                  : WindowChrome(child: child!),
            ),
          ),
          home: HomePage(client: c),
        ),
      ),
    );
    await frames(1000);
    await tap(find.byKey(const ValueKey('conversation-$dm')));
    final input = find.byKey(const ValueKey('chat-input'));
    final dock = find.byKey(const ValueKey('dot-activity'));
    final box = find.byKey(const ValueKey('composer-card'));
    final original = c.node.tasks.keys.toSet();
    Future<void> send(String text) async {
      await tester.enterText(input, text);
      await frames(150);
      await tap(find.byTooltip(c.tr('发送', 'Send')));
    }

    const reuse = String.fromEnvironment('QA_ACTIVITY_TASKS');
    final taskIds = reuse.split(',').where((s) => s.isNotEmpty).toSet();
    if (taskIds.isEmpty) {
      await send(
        '帮我阅读 $work/activity-input.txt，用原生 clarify 问我想要列表还是表格，等我回答后按我选的格式总结文档。不要改写原文件。',
      );
      await until(
        () => c.node.tasks.values.any(
          (t) => !original.contains(t.taskId) && t.active,
        ),
        'first independent task started',
      );
      taskIds.addAll(c.node.tasks.keys.where((id) => !original.contains(id)));
      debugPrint('ACTIVITY first task ${taskIds.join(',')}');
    }
    if (taskIds.length == 1) {
      await send('另外帮我列出一周七天的名字，先用原生 clarify 问我要中文还是英文，等我选完再回答。之前的工作继续保留。');
      await until(
        () => c.node.tasks.keys.any(
          (id) => !original.contains(id) && !taskIds.contains(id),
        ),
        'second independent task started',
      );
      taskIds.addAll(c.node.tasks.keys.where((id) => !original.contains(id)));
    }
    debugPrint('ACTIVITY taskIds ${taskIds.join(',')}');
    await until(
      () =>
          taskIds.every((id) => c.node.tasks[id]?.state == 'waiting_question'),
      'two native questions waiting',
    );
    await frames();
    expect(dock, findsOneWidget);
    expect(tester.getRect(dock).bottom, closeTo(tester.getRect(box).top, 1));
    final initialY = tester.getRect(dock).top;
    await shot('waiting');
    await tester.drag(
      find.byKey(const ValueKey('chat-messages')),
      const Offset(0, 450),
    );
    await frames();
    expect(tester.getRect(dock).top, closeTo(initialY, 1));
    await shot('history');
    await tester.enterText(input, '保留这段未发送草稿\n第二行');
    await frames();
    expect(tester.widget<TextField>(input).controller!.text, '保留这段未发送草稿\n第二行');
    expect(tester.getRect(dock).bottom, closeTo(tester.getRect(box).top, 1));
    await shot('draft');
    FocusManager.instance.primaryFocus?.unfocus();
    await frames();
    // Both questions wait behind one line: it names the wait, not the work.
    final row = tester.widget<ThinkingRow>(find.byType(ThinkingRow));
    expect(row.line, c.tr('等你回答', 'Needs your answer'));
    expect(row.moving, isFalse);
    expect(find.byKey(const ValueKey('chat-activity-select')), findsNothing);
    // Neither question is a line of the history; the line opens them.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('chat-messages')),
        matching: find.byType(ControlCard),
      ),
      findsNothing,
    );
    final controls = find.byKey(const ValueKey('chat-controls'));
    await tap(dock);
    expect(
      find.descendant(of: controls, matching: find.byType(ControlCard)),
      findsNWidgets(taskIds.length),
    );
    await shot('controls');
    nav.currentState!.pop();
    await frames();
    expect(controls, findsNothing);
    expect(nav.currentState!.canPop(), phone);
    await tap(find.byKey(const ValueKey('chat-flowchart')));
    await shot('flow');
    await tap(find.byKey(const ValueKey('flow-close')));
    expect(tester.widget<TextField>(input).controller!.text, '保留这段未发送草稿\n第二行');
    final composer = tester.state<ChatComposerState>(find.byType(ChatComposer));
    final question = c.node.messages[dm]!.firstWhere(
      (m) =>
          m.taskId == taskIds.first &&
          m.kind == 'question' &&
          m.status == 'streaming',
    );
    composer.quote(
      '${question.content['question'] ?? question.content['prompt'] ?? '列表'}',
      taskId: taskIds.first,
    );
    await frames();
    expect(composer.taskDraft?['taskId'], taskIds.first);
    expect(tester.getRect(dock).bottom, closeTo(tester.getRect(box).top, 1));
    await shot('quoted');
    await tap(find.byTooltip(c.tr('取消', 'Cancel')).last);
    expect(composer.taskDraft, isNull);
    expect(c.workspace['taskQuote:${c.selectedNodeId}:$dm'], isNull);
    if (phone) {
      tester.testTextInput.unregister();
      await tester.tap(input);
      await frames(1000);
      expect(tester.view.viewInsets.bottom, greaterThan(0));
      expect(tester.getRect(dock).bottom, closeTo(tester.getRect(box).top, 1));
      await shot('keyboard');
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      FocusManager.instance.primaryFocus?.unfocus();
      await frames(500);
      tester.testTextInput.register();
    }
    await c.prefs.update(locale: 'en', appearance: 'dark');
    await shot('dark-en');
    reducedMotion.value = true;
    await shot('reduced-motion');
    expect(
      find.descendant(of: dock, matching: find.byType(ShaderMask)),
      findsNothing,
    );
    await c.connection.disconnect();
    await frames(1000);
    expect(
      find.descendant(of: dock, matching: find.byType(ShaderMask)),
      findsNothing,
    );
    await shot('offline');
    await c.connection.connect();
    await until(() => c.online, 'reconnected');
    if (const bool.fromEnvironment('QA_ACTIVITY_OBSERVE_ONLY')) {
      final result = {
        'taskIds': taskIds.toList(),
        'platform': suffix,
        'pending': true,
      };
      if (!phone) {
        await File('$evidence/activity-pending.json')
            .writeAsString(jsonEncode(result));
      }
      binding.reportData = {...?binding.reportData, ...result};
      debugPrint('ACTIVITY pending ${jsonEncode(result)}');
      return;
    }
    final latest = find.byKey(const ValueKey('chat-latest'));
    if (latest.hitTestable().evaluate().isNotEmpty) await tap(latest);
    await tap(dock);
    for (final id in taskIds) {
      final question = c.node.messages[dm]!.firstWhere(
        (m) =>
            m.taskId == id && m.kind == 'question' && m.status == 'streaming',
      );
      await tap(find.byKey(ValueKey('choice-${question.messageId}-0')));
      await shot('answered-${taskIds.toList().indexOf(id)}');
    }
    // Nothing is left to answer, so the card leaves on its own.
    await until(() => controls.evaluate().isEmpty, 'answered controls closed');
    await until(
      () => taskIds.every(
        (id) =>
            c.node.tasks[id]?.active == false &&
            c.node.tasks[id]?.reportMessageId != null,
      ),
      'tasks completed and reported',
    );
    await frames();
    expect(
      taskIds.every((id) => c.node.tasks[id]?.state == 'completed'),
      isTrue,
    );
    await tester.enterText(input, '');
    c.workspace.remove('taskQuote:${c.selectedNodeId}:$dm');
    c.node.changed(dm);
    await frames();
    if (latest.hitTestable().evaluate().isNotEmpty) await tap(latest);
    await shot('results');
    // A command that needs your OK waits behind the same line.
    final botId =
        c.node.conversations.firstWhere(
              (x) => x['conversationId'] == dm,
            )['botId']
            as String;
    final mode = (await c.rpc('bots.permissions.get', {
      'botId': botId,
    }))['mode'];
    await c.rpc('bots.update', {'botId': botId, 'approvalMode': 'manual'});
    try {
      final seen = c.node.messages[dm]!.map((m) => m.messageId).toSet();
      ChatMessage? approval() => c.node.messages[dm]!
          .where(
            (m) =>
                !seen.contains(m.messageId) &&
                m.kind == 'approval' &&
                m.status == 'streaming',
          )
          .firstOrNull;
      await send(
        '请用 terminal 在前台只运行一次 python -c "print(37*41)"，这是无害的审批验收，然后把结果告诉我。',
      );
      await until(() => approval() != null, 'native approval waiting');
      final asked = approval()!;
      await frames();
      expect(
        tester.widget<ThinkingRow>(find.byType(ThinkingRow)).line,
        c.tr('等你确认', 'Needs your OK'),
      );
      await tap(dock);
      await shot('approval');
      await tap(find.byKey(ValueKey('choice-${asked.messageId}-0')));
      await until(() => controls.evaluate().isEmpty, 'approved control closed');
      await until(
        () => c.node.messages[dm]!.any(
          (m) =>
              !seen.contains(m.messageId) &&
              m.author.type == 'bot' &&
              m.taskRole != 'execution' &&
              m.status == 'done' &&
              '${m.content['text']}'.contains('1517'),
        ),
        'approved command reported in the main chat',
      );
      await shot('approved');
    } finally {
      await c.rpc('bots.update', {'botId': botId, 'approvalMode': mode});
    }
    final result = {
      'platform': suffix,
      'taskIds': taskIds.toList(),
      'states': [for (final id in taskIds) c.node.tasks[id]!.state],
    };
    if (!phone) {
      await File('$evidence/activity-$suffix-results.json')
          .writeAsString(jsonEncode(result));
    }
    binding.reportData = {...?binding.reportData, ...result};
    debugPrint('ACTIVITY PASS ${jsonEncode(result)}');
  });
}
