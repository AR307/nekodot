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
  testWidgets('Dot mediates private questions and results', (tester) async {
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
      final end = DateTime.now().add(const Duration(minutes: 10));
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
        '帮我做一个三页周汇报 PPTX，素材是 $work/activity-input.txt，内容用中文。'
        '先安排实际制作去读取素材、整理内容，再通过原生 clarify 确认我想用正式商务风还是轻松图文风。'
        '现在先不要替我选风格，也不要在接待阶段提前问；读取后再问我。'
        '我选好以后继续完成真实 PPTX，保存在 $work/weekly-$suffix.pptx，然后交付文件和简短总结。'
        '不要改写素材，不要装大型依赖。',
      );
      await until(
        () => c.node.tasks.keys.any((id) => !original.contains(id)),
        'native work started',
      );
      taskIds.addAll(c.node.tasks.keys.where((id) => !original.contains(id)));
    }
    final taskId = taskIds.single;
    if (const bool.fromEnvironment('QA_ACTIVITY_RESULT_ONLY')) {
      await until(
        () => c.node.tasks[taskId]?.reportMessageId != null,
        'existing work reported without replay',
      );
      final report = c.node.messages[dm]!.firstWhere(
        (m) => m.messageId == c.node.tasks[taskId]!.reportMessageId,
      );
      expect(c.node.tasks[taskId]!.state, 'completed');
      expect(report.content['files'], isNotEmpty);
      await shot('results');
      return;
    }
    ChatMessage? question(bool worker) => c.node.messages[dm]!
        .where(
          (m) =>
              m.taskId == taskId &&
              m.kind == 'question' &&
              m.status == 'streaming' &&
              (m.taskRole == 'execution') == worker,
        )
        .lastOrNull;
    await until(() => question(true) != null, 'worker asked privately');
    final raw = question(true)!;
    await until(
      () => question(false) != null,
      'main Dot asked with native clarify',
    );
    final asked = question(false)!;
    expect(asked.content['runId'], isNot(raw.content['runId']));
    expect(asked.content['question'], isNot(raw.content['question']));
    expect(
      '${asked.content['question']}',
      isNot(
        matches(RegExp(r'子代理|手下|任务编号|subagent|worker', caseSensitive: false)),
      ),
    );
    await frames();
    final latest = find.byKey(const ValueKey('chat-latest'));
    Future<void> showLatest() async {
      if (latest.hitTestable().evaluate().isNotEmpty) await tap(latest);
    }

    await showLatest();
    expect(find.byType(ControlCard), findsWidgets);
    expect(find.text('${raw.content['question']}'), findsNothing);
    expect(find.text('${asked.content['question']}'), findsOneWidget);
    expect(dock, findsOneWidget);
    expect(tester.getRect(dock).bottom, closeTo(tester.getRect(box).top, 1));
    final initialY = tester.getRect(dock).top;
    await shot('main-question');
    await tap(dock);
    expect(find.byKey(const ValueKey('chat-controls')), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    await tester.drag(
      find.byKey(const ValueKey('chat-messages')),
      const Offset(0, 450),
    );
    await frames();
    expect(tester.getRect(dock).top, closeTo(initialY, 1));
    await shot('history');
    await tester.enterText(input, '保留这段未发送草稿\n第二行');
    await frames();
    expect(tester.getRect(dock).bottom, closeTo(tester.getRect(box).top, 1));
    await shot('draft');
    FocusManager.instance.primaryFocus?.unfocus();
    await frames();
    final row = tester.widget<ThinkingRow>(find.byType(ThinkingRow));
    expect(row.line, c.tr('等你回答', 'Needs your answer'));
    expect(row.moving, isFalse);
    await tap(find.byKey(const ValueKey('chat-flowchart')));
    await shot('flow');
    await tap(find.byKey(const ValueKey('flow-close')));
    expect(tester.widget<TextField>(input).controller!.text, '保留这段未发送草稿\n第二行');
    final composer = tester.state<ChatComposerState>(find.byType(ChatComposer));
    composer.quote('${asked.content['question']}', taskId: taskId);
    await frames();
    expect(composer.taskDraft?['taskId'], taskId);
    expect(tester.getRect(dock).bottom, closeTo(tester.getRect(box).top, 1));
    await shot('quoted');
    await tap(find.byTooltip(c.tr('取消', 'Cancel')).last);
    expect(composer.taskDraft, isNull);
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
    await showLatest();
    await shot('dark-en');
    reducedMotion.value = true;
    await shot('reduced-motion');
    await c.connection.disconnect();
    await frames(1000);
    expect(
      find.descendant(of: dock, matching: find.byType(ShaderMask)),
      findsNothing,
    );
    await shot('offline');
    await c.connection.connect();
    await until(() => c.online, 'reconnected');
    await until(() => question(false) != null, 'same question restored');
    expect(question(false)!.messageId, asked.messageId);
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
    await showLatest();
    final choices = (asked.content['choices'] as List).cast<String>();
    final selected = choices.indexWhere(
      (s) => s.contains('正式') || s.contains('商务'),
    );
    expect(selected, greaterThanOrEqualTo(0));
    await tap(find.byKey(ValueKey('choice-${asked.messageId}-$selected')));
    await until(
      () => question(true) == null,
      'secretary passed answer to original worker',
    );
    await until(
      () => c.node.tasks[taskId]?.reportMessageId != null,
      'file produced and main Dot reported',
    );
    expect(c.node.tasks[taskId]!.state, 'completed');
    final result = await c.rpc('tasks.get', {
      'conversationId': dm,
      'taskId': taskId,
    });
    final report = c.node.messages[dm]!.firstWhere(
      (m) => m.messageId == c.node.tasks[taskId]!.reportMessageId,
    );
    final originalResult = (result['messages'] as List)
        .cast<Map>()
        .where((m) => m['messageId'] == c.node.tasks[taskId]!.resultMessageId)
        .first;
    expect(
      report.content['text'],
      isNot((originalResult['content'] as Map)['text']),
    );
    expect(report.content['files'], isNotEmpty);
    await tester.enterText(input, '');
    await showLatest();
    await shot('results');
    if (const bool.fromEnvironment('QA_SECRETARY_SELF_ANSWER')) {
      final before = c.node.tasks.keys.toSet();
      await send(
        '接下来做一次重复确认的流程验收：输出格式我已经确定为 Markdown 表格。'
        '请在实际执行中先读同一素材 $work/activity-input.txt；为了验收，'
        '让执行过程仍用原生 clarify 向你核对输出格式。'
        '你根据我已经明确的格式直接答复，不要再让我选。'
        '然后生成日期和安排两列的表格，保存 $work/self-answer-$suffix.md，简短汇报并交付。',
      );
      await until(
        () => c.node.tasks.keys.any((id) => !before.contains(id)),
        'second native requirement started',
      );
      final second = c.node.tasks.keys.firstWhere((id) => !before.contains(id));
      await until(
        () => c.node.tasks[second]?.reportMessageId != null,
        'main Dot resolved known information without interrupting user',
      );
      final detail = await c.rpc('tasks.get', {
        'conversationId': dm,
        'taskId': second,
      });
      final questions = (detail['messages'] as List)
          .cast<Map>()
          .where((m) => m['kind'] == 'question')
          .toList();
      expect(questions.where((m) => m['taskRole'] == 'execution'), isNotEmpty);
      expect(questions.where((m) => m['taskRole'] != 'execution'), isEmpty);
      expect(
        questions.every((m) => (m['content'] as Map)['answer'] != null),
        isTrue,
      );
      expect(c.node.tasks[second]!.state, 'completed');
      await showLatest();
      await shot('self-answered');
    }
    final record = {
      'platform': suffix,
      'taskIds': taskIds.toList(),
      'workerQuestion': raw.content['question'],
      'mainQuestion': asked.content['question'],
      'reportMessageId': report.messageId,
      'fileIds': report.content['files'],
    };
    if (!phone) {
      await File('$evidence/activity-$suffix-results.json')
          .writeAsString(jsonEncode(record));
    }
    binding.reportData = {...?binding.reportData, ...record};
    debugPrint('ACTIVITY PASS ${jsonEncode(record)}');
  });
}
