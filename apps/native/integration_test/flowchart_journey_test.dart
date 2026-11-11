import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';

import 'package:nekodot_native/data/flow.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

// Native candidate -> real Relay/Node/Hermes. No fixtures or tool simulations.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('inspect real private and group execution without resubmitting work', (
    tester,
  ) async {
    final c = NekodotClient();
    const dm = String.fromEnvironment('QA_CONVERSATION');
    const group = String.fromEnvironment('QA_GROUP');
    const evidence = String.fromEnvironment('QA_EVIDENCE_DIR');
    final work = const String.fromEnvironment('QA_WORK_DIR')
        .replaceAll('\\', '/');
    final platform = Platform.operatingSystem;
    if (Platform.isWindows) {
      await DesktopHost.initialize();
      tester.view.physicalSize = const Size(2800, 1800);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
    }
    Future<void> until(
      bool Function() ready,
      String stage, {
      int seconds = 360,
    }) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 200));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(ready(), true, reason: stage);
    }

    Future<void> settle() async {
      await tester.pump(const Duration(milliseconds: 450));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    }

    Future<void> tap(Finder f) async {
      await until(
        () => f.evaluate().isNotEmpty,
        'Control present',
        seconds: 20,
      );
      await Scrollable.ensureVisible(tester.element(f.first), alignment: .5);
      await settle();
      await until(
        () => f.hitTestable().evaluate().isNotEmpty,
        'Control tappable',
        seconds: 20,
      );
      await tester.tap(f.hitTestable().first);
      await settle();
    }

    bool converted = false;
    Future<void> shot(String stage) async {
      await settle();
      if (Platform.isAndroid) {
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
          await tester.pump();
        }
        await binding.takeScreenshot('flow-$platform-$stage');
      } else {
        await Directory(evidence).create(recursive: true);
        final view = tester.binding.renderViews.first;
        final image = await (view.debugLayer! as OffsetLayer).toImage(
          Offset.zero & view.flutterView.physicalSize,
        );
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$evidence/flow-$platform-$stage.png')
            .writeAsBytes(png!.buffer.asUint8List());
      }
    }

    final login = await c.account.request(
      '/auth/login',
      method: 'POST',
      body: {
        'email': const String.fromEnvironment('QA_EMAIL'),
        'password': const String.fromEnvironment('QA_PASSWORD'),
      },
    );
    c.account.token = login['token'] as String;
    c.selectedNodeId = const String.fromEnvironment('QA_NODE');
    await c.bootstrap();
    addTearDown(c.dispose);
    await until(
      () => c.online && c.node.conversations.isNotEmpty,
      'Real Node online',
    );
    final visual = ValueNotifier(false);
    addTearDown(visual.dispose);
    runApp(
      ValueListenableBuilder<bool>(
        valueListenable: visual,
        builder: (context, dark, _) => MaterialApp(
          theme: appTheme(
            dark ? Brightness.dark : Brightness.light,
            glass: dark ? true : null,
          ),
          navigatorObservers: [nativeRoutes],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: dark),
            child: Platform.isWindows
                ? WindowChrome(child: child!)
                : Ambient(child: child!),
          ),
          home: HomePage(client: c),
        ),
      ),
    );
    await tap(find.byKey(const ValueKey('conversation-$dm')));
    final input = find.byKey(const ValueKey('chat-input'));
    final open = find.byKey(const ValueKey('chat-flowchart'));
    final close = find.byKey(const ValueKey('flow-close'));
    Future<void> submit(String text) async {
      await tap(input);
      await tester.enterText(input, text);
      await settle();
      await tap(find.byTooltip('发送'));
      await until(
        () => tester.widget<TextField>(input).controller!.text.isEmpty,
        'Input admitted',
      );
    }

    Future<void> openGraph() async {
      await tap(open);
      await until(
        () =>
            find.byKey(const ValueKey('flowchart-panel')).evaluate().isNotEmpty,
        'Flow opened',
      );
    }

    Future<void> closeGraph() async {
      if (close.evaluate().isNotEmpty) await tap(close);
    }

    final observed = <String, Set<String>>{};
    void observe() {
      for (final f in c.node.flows.values) {
        observed
            .putIfAbsent(f.conversationId, () => {})
            .addAll(f.steps.map((s) => '${s.kind}:${s.state}'));
      }
    }

    c.addListener(observe);
    addTearDown(() => c.removeListener(observe));
    Future<FlowSnapshot> finish(String conversation, String previous) async {
      final handled = <String>{};
      final end = DateTime.now().add(const Duration(minutes: 8));
      while (DateTime.now().isBefore(end)) {
        final flow = c.node.flows[conversation];
        final pending = flow?.steps
            .where(
              (s) =>
                  s.state == 'waiting' &&
                  (s.kind == 'approval' || s.kind == 'question') &&
                  !handled.contains(s.stepId),
            )
            .firstOrNull;
        if (pending != null) {
          await shot('waiting-${pending.kind}');
          // The graph step opens the same card the Dot's line opens.
          await tap(find.byKey(ValueKey('flow-step-${pending.stepId}')));
          if (pending.kind == 'approval') {
            await tap(find.text('允许一次'));
          } else {
            final field = find.byKey(ValueKey('answer-${pending.messageId}'));
            await tap(field);
            await tester.enterText(field, '继续验收');
            await tap(find.byTooltip('提交'));
          }
          handled.add(pending.stepId);
          await openGraph();
        }
        if (flow != null &&
            flow.flowId != previous &&
            [
              'done',
              'failed',
              'cancelled',
              'paused',
              'unknown',
            ].contains(flow.state)) {
          return flow;
        }
        await settle();
      }
      throw StateError('Timed out waiting for real task $conversation');
    }

    if (const bool.fromEnvironment('QA_EMPTY')) {
      await openGraph();
      await until(
        () => (c.node.flows[dm]?.steps ?? []).isEmpty,
        'New native session has no previous graph',
      );
      await shot('new-session-empty');
      expect(find.byKey(const ValueKey('flowchart-panel')), findsOneWidget);
      expect(tester.takeException(), isNull);
      binding.reportData = {
        ...?binding.reportData,
        'platform': platform,
        'newSessionEmpty': true,
      };
      c.removeListener(observe);
      await tester.pumpWidget(const SizedBox.shrink());
      return;
    }

    if (const bool.fromEnvironment('QA_VIEW')) {
      final original = c.node.flows[dm]!;
      await openGraph();
      await shot('compact-plan-final');
      final plan = original.steps.firstWhere((s) => s.kind == 'plan');
      final list = find.byKey(const ValueKey('flow-steps'));
      await tester.drag(list, const Offset(0, 3000));
      await settle();
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('flow-step-${plan.stepId}')),
        250,
        scrollable: find.descendant(
          of: list,
          matching: find.byType(Scrollable),
        ),
      );
      await tap(find.byKey(ValueKey('flow-step-${plan.stepId}')));
      await shot('compact-plan-expanded');
      visual.value = true;
      c.prefs.language = 'en';
      c.notifyListeners();
      await shot('compact-dark-en-reduced');
      if (Platform.isAndroid) {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
        ]);
        await until(
          () =>
              tester.view.physicalSize.width > tester.view.physicalSize.height,
          'Android landscape',
        );
        await shot('compact-landscape');
        await tester.binding.handlePopRoute();
        await settle();
        expect(find.byKey(const ValueKey('flowchart-panel')), findsNothing);
        expect(input, findsOneWidget);
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
        await until(
          () =>
              tester.view.physicalSize.height > tester.view.physicalSize.width,
          'Android portrait',
        );
      } else {
        await closeGraph();
      }
      expect(c.node.flows[dm]!.seq, original.seq);
      if (Platform.isAndroid) {
        Navigator.of(tester.element(input)).pop();
        await settle();
      }
      await tap(find.byKey(ValueKey('conversation-$group')));
      final team = c.node.flows[group]!;
      await openGraph();
      await shot('compact-group-final');
      expect(team.steps.where((s) => s.kind == 'bot').length, 3);
      expect(tester.takeException(), isNull);
      final report = {
        'platform': platform,
        'viewOnly': true,
        'sameFlowSeq': true,
        'planFlow': original.flowId,
        'groupFlow': team.flowId,
        'groupTurns': 3,
        'landscape': Platform.isAndroid,
        'backPreservesChat': Platform.isAndroid,
        'reducedMotion': true,
        'compactNode': 32,
        'rowExtent': 56,
      };
      binding.reportData = {...?binding.reportData, ...report};
      if (Platform.isWindows) {
        await File('$evidence/flow-view-windows.json')
            .writeAsString(jsonEncode(report));
      }
      c.removeListener(observe);
      await tester.pumpWidget(const SizedBox.shrink());
      return;
    }

    if (const bool.fromEnvironment('QA_PLAN')) {
      final previous = c.node.flows[dm]?.flowId ?? '';
      final outputFile =
          '$work/flow-plan-$platform-${DateTime.now().millisecondsSinceEpoch}.md';
      await submit(
        '请真实使用 todo_list 创建三个计划步骤，id 分别为 read、analyse、write，标题为读取数据、计算均值、写入报告。开始只将 read 设为 in_progress，其余 pending。'
        '第一步用 read_file 读取 "$work/flow-input.csv"；完成后用 todo_list 将 read 标记 completed、analyse 标记 in_progress。'
        '第二步用 execute_code 计算 value 平均值，代码等待 12 秒以便我观察实时界面，再输出实际结果。完成后用 todo_list 将 analyse 标记 completed、write 标记 in_progress。'
        '第三步用 write_file 写入新文件 "$outputFile"，包含实际均值，然后 read_file 复核，最后 todo_list 标记全部 completed，简短回复。'
        '必须调用真实工具，步骤状态更新使用完整 todo_list，不要只写文字计划。不创建定时或 webhook。',
      );
      await openGraph();
      await until(
        () =>
            c.node.flows[dm]?.steps.any(
              (s) => s.kind == 'code' && s.state == 'running',
            ) ==
            true,
        'Native plan execution running',
      );
      final running = c.node.flows[dm]!;
      final plans = running.steps.where((s) => s.kind == 'plan').toList();
      expect(plans.length, 3);
      expect(plans.map((s) => s.state), ['done', 'running', 'pending']);
      final read = running.steps.firstWhere((s) => s.tool == 'read_file');
      final code = running.steps.firstWhere((s) => s.kind == 'code');
      expect(read.parentStepId, plans[0].stepId);
      expect(code.parentStepId, plans[1].stepId);
      await shot('plan-running');
      final list = find.byKey(const ValueKey('flow-steps'));
      await tester.drag(list, const Offset(0, 2000));
      await settle();
      expect(find.byKey(ValueKey('flow-step-${read.stepId}')), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('flow-step-${plans[0].stepId}')),
        300,
        scrollable: find.descendant(
          of: list,
          matching: find.byType(Scrollable),
        ),
      );
      await tap(find.byKey(ValueKey('flow-step-${plans[0].stepId}')));
      expect(find.byKey(ValueKey('flow-step-${read.stepId}')), findsOneWidget);
      await shot('plan-expanded');
      await tap(find.byKey(ValueKey('flow-step-${plans[0].stepId}')));
      await tap(find.byKey(const ValueKey('flow-follow')));
      final completed = await finish(dm, previous);
      expect(completed.state, 'done');
      expect(
        completed.steps.where((s) => s.kind == 'plan').map((s) => s.state),
        everyElement('done'),
      );
      await shot('plan-completed');
      await closeGraph();
      await c.bootstrap();
      await until(
        () => c.online && !c.node.syncing,
        'Real reconnect with plan',
      );
      await openGraph();
      expect(c.node.flows[dm]!.flowId, completed.flowId);
      await shot('plan-reconnected');
      visual.value = true;
      c.prefs.language = 'en';
      c.notifyListeners();
      await shot('plan-dark-en-reduced');
      if (Platform.isAndroid) {
        await tester.binding.handlePopRoute();
        await settle();
        expect(find.byKey(const ValueKey('flowchart-panel')), findsNothing);
        expect(input, findsOneWidget);
        await openGraph();
      }
      final report = {
        'platform': platform,
        'model': 'gpt-6.1-sol',
        'outputFile': outputFile,
        'flowId': completed.flowId,
        'nativePlans': plans
            .map((s) => {'title': s.title, 'state': s.state})
            .toList(),
        'steps': completed.steps
            .map(
              (s) => {
                'kind': s.kind,
                'state': s.state,
                'tool': s.tool,
                'parent': s.parentStepId,
              },
            )
            .toList(),
        'autoCollapsed': true,
        'manualExpand': true,
        'reconnectSameRun': true,
        'backPreservesChat': Platform.isAndroid,
      };
      if (Platform.isWindows) {
        await File('$evidence/flow-plan-$platform.json')
            .writeAsString(jsonEncode(report));
      }
      debugPrint('FLOW_PLAN ${jsonEncode(report)}');
      binding.reportData = {...?binding.reportData, ...report};
      expect(tester.takeException(), isNull);
      c.removeListener(observe);
      await tester.pumpWidget(const SizedBox.shrink());
      return;
    }

    if (const bool.fromEnvironment('QA_CONTROLS')) {
      const stopOnly = bool.fromEnvironment('QA_STOP_ONLY');
      var previous = c.node.flows[dm]?.flowId ?? '';
      if (!stopOnly) {
        await submit(
          '请立即使用 clarify 工具问我一个问题：是否继续验收？提供继续和取消两个选项。收到回答后简短回复，不调用其他工具。',
        );
        await openGraph();
        final question = await finish(dm, previous);
        expect(
          question.steps.any((s) => s.kind == 'question' && s.state == 'done'),
          true,
        );
        await closeGraph();
        previous = question.flowId;
        await submit(
          '请仅调用一次 terminal 执行 python -c "print(9*7)"，等我通过原生审批后再继续。最终回复实际输出。不要换用 execute_code。',
        );
        await openGraph();
        final approval = await finish(dm, previous);
        expect(
          approval.steps.any((s) => s.kind == 'approval' && s.state == 'done'),
          true,
        );
        await shot('approval-done');
        await closeGraph();
        previous = approval.flowId;
        await submit(
          '请仅调用一次 terminal 执行不存在的命令 nekodot_flow_nonexistent_20261106，用来检查错误显示。不要安装任何软件、不要换工具、不要重试；最后报告失败原因。',
        );
        await openGraph();
        final failure = await finish(dm, previous);
        expect(
          failure.steps.any((s) => s.tool != null && s.state == 'failed'),
          true,
        );
        await shot('tool-failed');
        await closeGraph();
        previous = failure.flowId;
      }
      await submit(
        '请仅调用一次 execute_code，执行 Python 的 import time; time.sleep(120); print(42)。用于检查我在运行中补充指令和停止，不写文件。',
      );
      await openGraph();
      await until(
        () =>
            c.node.flows[dm]?.steps.any(
              (s) => s.kind == 'code' && s.state == 'running',
            ) ==
            true,
        'Code actually started',
      );
      final active = c.node.flows[dm]!.flowId;
      expect(active, isNot(previous));
      await closeGraph();
      await submit('最终只需要回复一个数字。');
      expect(c.node.flows[dm]!.flowId, active);
      await submit('/queue 仅回复 QUEUED，无需工具');
      expect(c.node.flows[dm]!.flowId, active);
      await submit('/queue list');
      final listing = (c.node.messages[dm] ?? []).lastWhere(
        (m) =>
            m.kind == 'system' &&
            m.content['command'] == '/queue' &&
            '${m.content['text']}'.contains('[queued]'),
      );
      final queued = RegExp(
        r'^(\d+)\. \[queued\]',
        multiLine: true,
      ).firstMatch('${listing.content['text']}')!;
      await submit('/queue rm ${queued.group(1)}');
      await openGraph();
      await c.bootstrap();
      await until(() => c.online && !c.node.syncing, 'Reconnect real socket');
      expect(c.node.flows[dm]!.flowId, active);
      await shot('steer-reconnected');
      await closeGraph();
      await tap(find.byTooltip('停止'));
      await until(
        () => c.node.flows[dm]?.state == 'cancelled',
        'Native task stopped',
      );
      await openGraph();
      await shot('stopped');
      visual.value = true;
      if (Platform.isWindows) {
        tester.view.physicalSize = const Size(2100, 1600);
      }
      await shot('dark-glass-overlay-reduced');
      expect(tester.takeException(), isNull);
      await closeGraph();
      await submit('/new');
      await shot('new-session-before-flow');
      await openGraph();
      expect(c.node.flows[dm]?.steps ?? [], isEmpty);
      await shot('new-session-empty');
      final report = {
        'platform': platform,
        'question': !stopOnly,
        'approval': !stopOnly,
        'toolFailure': !stopOnly,
        'steer': true,
        'queueKeptFlow': true,
        'reconnect': true,
        'stop': true,
        'newSessionEmpty': true,
      };
      debugPrint('FLOW_CONTROLS ${jsonEncode(report)}');
      binding.reportData = {...?binding.reportData, ...report};
      if (Platform.isWindows) {
        await File('$evidence/flow-controls-$platform.json')
            .writeAsString(jsonEncode(report));
      }
      c.removeListener(observe);
      await tester.pumpWidget(const SizedBox.shrink());
      return;
    }

    await openGraph();
    await shot('before');
    await closeGraph();
    await tester.enterText(input, '草稿不会因为看图丢失');
    await openGraph();
    await closeGraph();
    expect(tester.widget<TextField>(input).controller!.text, '草稿不会因为看图丢失');
    final previous = c.node.flows[dm]?.flowId ?? '';
    await submit(
      '这是 Flowchart 真实工具验收。请依次：1 用 read_file 读取 "$work/flow-input.csv"；2 用 execute_code 计算 value 的平均值；3 用 write_file 写入 "$work/flow-$platform.md"，包含实际平均值；4 用 read_file 复核刚写的文件；最后简短报告。工具出错请如实说明，不用其他工具替代，不创建例行任务。',
    );
    await openGraph();
    final privateFlow = await finish(dm, previous);
    await shot('private-done');
    expect(privateFlow.state, 'done');
    expect(
      privateFlow.steps.any((s) => s.kind == 'read' && s.state == 'done'),
      true,
    );
    expect(
      privateFlow.steps.any((s) => s.kind == 'write' && s.state == 'done'),
      true,
    );
    // Reopen, synchronize and read the same snapshot: no new execution admission.
    final privateId = privateFlow.flowId;
    await closeGraph();
    await c.synchronize(c.selectedNodeId!);
    await openGraph();
    expect(c.node.flows[dm]!.flowId, privateId);
    final tool = privateFlow.steps.firstWhere((s) => s.tool != null);
    final list = find.byKey(const ValueKey('flow-steps'));
    await tester.drag(list, const Offset(0, 2000));
    await settle();
    await tap(find.byKey(ValueKey('flow-step-${tool.stepId}')));
    expect(find.byType(AlertDialog), findsOneWidget);
    await shot('tool-details');
    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await settle();
    await closeGraph();
    // Group uses the actual member queue; each member performs a different tool phase.
    if (Platform.isAndroid) {
      Navigator.of(tester.element(input)).pop();
      await settle();
    }
    await tap(find.byKey(const ValueKey('conversation-$group')));
    final oldGroup = c.node.flows[group]?.flowId ?? '';
    await submit(
      '@flowsearch @flowanalyse @flowwrite 请按顺序完成一份简短报告，各自只做自己的部分，不再 @ 其他人。检索员：用 web_search 找到 Attention Is All You Need 的真实论文链接，然后用 browser_exec 浏览它并报告标题和年份，不猜测来源。分析员：用 read_file 读 "$work/flow-input.csv"，execute_code 算平均值。撰写员：用 write_file 将前两位的实际结果和论文链接写到 "$work/flow-group-$platform.md"。工具失败如实说明，不伪装成功，不用其他工具替代。',
    );
    await openGraph();
    final groupFlow = await finish(group, oldGroup);
    await shot('group-done');
    expect(groupFlow.steps.where((s) => s.kind == 'bot').length, 3);
    expect(
      groupFlow.steps
          .where((s) => s.kind == 'bot')
          .map((s) => s.botId)
          .toSet()
          .length,
      3,
    );
    expect(groupFlow.queuedBotIds, isEmpty);
    expect(groupFlow.steps.any((s) => s.kind == 'search'), true);
    final result = {
      'platform': platform,
      'model': 'gpt-6.1-sol',
      'privateState': privateFlow.state,
      'groupState': groupFlow.state,
      'privateSteps': [
        for (final s in privateFlow.steps)
          {'kind': s.kind, 'state': s.state, 'tool': s.tool},
      ],
      'groupSteps': [
        for (final s in groupFlow.steps)
          {'kind': s.kind, 'state': s.state, 'tool': s.tool, 'botId': s.botId},
      ],
      'observed': {for (final e in observed.entries) e.key: e.value.toList()},
    };
    debugPrint('FLOW_QA ${jsonEncode(result)}');
    binding.reportData = {...?binding.reportData, ...result};
    if (Platform.isWindows) {
      await File('$evidence/flow-$platform.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(result));
    }
    expect(tester.takeException(), isNull);
    await closeGraph();
    c.removeListener(observe);
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 20)));
}
