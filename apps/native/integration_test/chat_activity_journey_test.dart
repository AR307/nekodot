import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/chat_activity.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/task_details.dart';
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
    final dock = find.byKey(const ValueKey('chat-activity-dock'));
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
        '创建一个独立需求，标题“排版验收”。执行者先用原生 clarify 工具问我输出格式，选项“列表”和“表格”。等我回答后，只运行一次 Python：前台等待 15 秒并计算 1 到 20 的平方和，按所选格式给结果。不读写任何文件。',
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
      await send(
        '另建一个独立需求“日历验收”。执行者先用原生 clarify 问我要中文还是英文，选项“中文”和“英文”。等我回答后，以所选语言列出一周七天的名称。不影响之前的需求，不读写文件。',
      );
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
    final selector = find.byKey(const ValueKey('chat-activity-select'));
    await tap(selector);
    await shot('selector');
    final chosen = c.node.tasks[taskIds.first]!;
    await tap(find.widgetWithText(PopupMenuItem<String>, chosen.title));
    await tap(find.byKey(const ValueKey('chat-activity-current')));
    expect(find.byType(TaskDetailsPage), findsOneWidget);
    if (!phone) expect(tester.getSize(find.byType(TaskDetailsPage)).width, 540);
    await shot('details');
    await tap(find.byTooltip(c.tr('引用', 'Quote')));
    expect(find.byType(TaskDetailsPage), findsNothing);
    expect(tester.widget<TextField>(input).controller!.text, '保留这段未发送草稿\n第二行');
    expect(tester.getRect(dock).bottom, closeTo(tester.getRect(box).top, 1));
    await shot('quoted');
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
    for (final id in taskIds) {
      final task = c.node.tasks[id]!;
      final picker = find.byKey(const ValueKey('chat-activity-select'));
      if (picker.evaluate().isNotEmpty) {
        await tap(picker);
        await tap(find.widgetWithText(PopupMenuItem<String>, task.title));
      }
      await tap(find.byKey(const ValueKey('chat-activity-current')));
      await until(
        () => (c.node.messages[dm] ?? []).any(
          (m) =>
              m.taskId == id && m.kind == 'question' && m.status == 'streaming',
        ),
        'original question loaded',
      );
      final question = c.node.messages[dm]!.firstWhere(
        (m) =>
            m.taskId == id && m.kind == 'question' && m.status == 'streaming',
      );
      await tap(find.byKey(ValueKey('choice-${question.messageId}-0')));
      await tap(find.byTooltip(c.tr('关闭', 'Close')).last);
      if (id == taskIds.first) {
        await until(
          () =>
              c.node.flows[id]?.steps.any(
                (s) =>
                    s.state == 'running' &&
                    s.tool != null &&
                    s.tool != 'clarify',
              ) ==
              true,
          'real tool activity after answering',
        );
        await shot('live-tool');
      }
    }
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
    final latest = find.byKey(const ValueKey('chat-latest'));
    if (latest.hitTestable().evaluate().isNotEmpty) await tap(latest);
    await shot('results');
    final result = {
      'platform': suffix,
      'taskIds': taskIds.toList(),
      'states': [for (final id in taskIds) c.node.tasks[id]!.state],
      'labels': [
        for (final id in taskIds) ChatActivity(c, dm, c.node.tasks[id]).label,
      ],
    };
    if (!phone) {
      await File('$evidence/activity-$suffix-results.json')
          .writeAsString(jsonEncode(result));
    }
    debugPrint('ACTIVITY PASS ${jsonEncode(result)}');
  });
}
