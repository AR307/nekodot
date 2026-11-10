import 'package:nekodot_native/data/chat_models.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

/// Candidate native UI -> real Relay/Node -> Hermes cron -> real model/tools.
/// Only a dedicated QA Bot is used; each task is paused when the journey ends.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('configure task approvals and discuss its actual result', (
    tester,
  ) async {
    if (Platform.isWindows) {
      await DesktopHost.initialize();
      tester.view.physicalSize = const Size(2400, 1800);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
    }
    SharedPreferences.setMockInitialValues({'language': 'zh'});
    final client = NekodotClient(vault: MemoryVault());
    Future<Json> call(String method, Json params) async =>
        (await tester.runAsync(() => client.rpc(method, params)))!;
    const botId = String.fromEnvironment('QA_BOT');
    const conversationId = String.fromEnvironment('QA_CONVERSATION');
    const evidence = String.fromEnvironment('QA_EVIDENCE_DIR');
    final platform = Platform.operatingSystem;
    final name = 'Cron $platform ${DateTime.now().millisecondsSinceEpoch}';
    const existingRoutine = String.fromEnvironment('QA_EXISTING_ROUTINE');
    const existingExecution = String.fromEnvironment('QA_EXISTING_EXECUTION');
    final reuseRoutine = existingRoutine.isNotEmpty;
    final continuing = existingExecution.isNotEmpty;
    const finishAllow = bool.fromEnvironment('QA_FINISH_ALLOW');
    final file = reuseRoutine
        ? const String.fromEnvironment('QA_EXISTING_FILE')
        : '${const String.fromEnvironment('QA_WORK_DIR').replaceAll('\\', '/')}/$name.txt';
    // A Windows candidate may drive a Linux VPS; its result file is checked on
    // that host separately, never interpreted as a Windows-local path.
    final localFile =
        Platform.isWindows && RegExp(r'^[A-Za-z]:/').hasMatch(file);
    final report = <String, Object?>{'platform': platform, 'task': name};
    void note(String key, Object? value) {
      report[key] = value;
      debugPrint('QA $key: ${jsonEncode(value)}');
    }

    Future<void> until(
      bool Function() ready,
      String stage, {
      int seconds = 240,
    }) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(ready(), isTrue, reason: stage);
    }

    Future<void> settle() async {
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump();
    }

    Future<void> tap(Finder finder) async {
      await until(() => finder.evaluate().isNotEmpty, 'Find target');
      await Scrollable.ensureVisible(
        tester.element(finder.first),
        alignment: .5,
      );
      await settle();
      await until(
        () => finder.hitTestable().evaluate().isNotEmpty,
        'Visible target',
      );
      await tester.tap(finder.hitTestable().first);
      await settle();
    }

    var converted = false;
    Future<void> shot(String stage) async {
      await settle();
      if (Platform.isAndroid) {
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
          await tester.pump();
        }
        await binding.takeScreenshot('cron-$platform-$stage');
      } else {
        await Directory(evidence).create(recursive: true);
        final view = tester.binding.renderViews.first;
        final image = await (view.debugLayer! as OffsetLayer).toImage(
          Offset.zero & view.flutterView.physicalSize,
        );
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$evidence/cron-$platform-$stage.png')
            .writeAsBytes(png!.buffer.asUint8List());
      }
    }

    final login = (await tester.runAsync(
      () => client.account.request(
        '/auth/login',
        method: 'POST',
        body: {
          'email': const String.fromEnvironment('QA_EMAIL'),
          'password': const String.fromEnvironment('QA_PASSWORD'),
        },
      ),
    ))!;
    client.account.token = login['token'] as String;
    client.selectedNodeId = const String.fromEnvironment('QA_NODE');
    await tester.runAsync(client.bootstrap);
    note('realRelayConnected', true);
    addTearDown(client.dispose);
    await until(
      () => client.online && client.node.conversations.isNotEmpty,
      'QA Node online',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        navigatorObservers: [nativeRoutes],
        builder: (context, child) => Platform.isWindows
            ? WindowChrome(child: child!)
            : Ambient(child: child!),
        home: HomePage(client: client),
      ),
    );
    await tap(find.byKey(const ValueKey('conversation-$conversationId')));
    final input = find.byKey(const ValueKey('chat-input'));
    List<ChatMessage> messages() => client.node.messages[conversationId] ?? [];
    Future<void> submit(String text, {bool waitForAdmission = true}) async {
      await until(() => input.evaluate().isNotEmpty, 'Composer');
      await tap(input);
      await tester.enterText(input, text);
      await settle();
      expect(tester.widget<TextField>(input).controller!.text, text);
      await tap(find.byTooltip('发送'));
      if (waitForAdmission) {
        await until(
          () => tester.widget<TextField>(input).controller!.text.isEmpty,
          'Message admitted',
        );
      }
    }

    Future<void> idle() => until(
      () => client.node.activities[conversationId]?.state == 'idle',
      'Conversation idle',
    );
    addTearDown(() async {
      if (!client.online) return;
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (objects((await client.rpc('operations.list'))['operations']).any(
        (op) =>
            op['status'] == 'running' && (op['botIds'] as List).contains(botId),
      )) {
        expect(
          DateTime.now().isBefore(deadline),
          isTrue,
          reason: 'Wait for final task pause',
        );
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    });
    await idle();
    Json? routine;
    var answeredBeforeCreation = false;
    const timeRule =
        '我在马来西亚，时区 Asia/Kuala_Lumpur。这个任务每天早上 08:00 到晚上 22:00 询问我，'
        '晚上 22:00 到第二天早上 08:00 自动拒绝。请帮我设置好，不要现在执行任务。';
    if (reuseRoutine) {
      routine = object(
        (await call('routines.get', {
          'botId': botId,
          'routineId': existingRoutine,
        }))['routine'],
      );
      note('continuingExistingExecution', existingExecution);
    } else {
      final creationSeen = messages().map((m) => m.messageId).toSet();
      await submit(
        '请使用原生 cronjob 工具创建一个每 1 小时运行的定时任务，名称严格为 "$name"。'
        '不要现在执行。任务固定提示如下：'
        '只调用一次 execute_code，用 Python uuid.uuid4().hex 生成一个随机字符串，'
        '用 pathlib 把字符串加换行以 append 方式写入 "$file"，打印该字符串，最终只回复打印的字符串。'
        '不要调用其他工具或创建其他任务。若 execute_code 被拒绝，不换工具绕过，只报告拒绝。'
        '任务可使用 code_execution 工具集。',
      );
      final creationDeadline = DateTime.now().add(const Duration(minutes: 5));
      while (DateTime.now().isBefore(creationDeadline)) {
        final card = messages()
            .where((m) => m.kind == 'routine' && m.content['name'] == name)
            .firstOrNull;
        if (card != null) routine = object(card.content);
        final question = messages()
            .where(
              (m) =>
                  !creationSeen.contains(m.messageId) &&
                  m.kind == 'question' &&
                  m.status == 'streaming',
            )
            .firstOrNull;
        if (question != null && !answeredBeforeCreation) {
          await shot('question');
          final field = find.byKey(ValueKey('answer-${question.messageId}'));
          await tap(field);
          await tester.enterText(field, timeRule);
          await tap(find.byTooltip('提交'));
          answeredBeforeCreation = true;
          note('agentAskedUsingNativeClarify', true);
        }
        if (routine != null &&
            client.node.activities[conversationId]?.state == 'idle') {
          break;
        }
        await tester.pump(const Duration(milliseconds: 200));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(routine, isNotNull, reason: 'Real model creates scheduled task');
    }
    final routineId = '${routine!['routineId']}';
    final target = {'botId': botId, 'routineId': routineId};
    var detail = await call('routines.get', target);
    final jobId = '${detail['routine']['cronJobId']}';
    note('jobId', jobId);
    if (!continuing && !answeredBeforeCreation) {
      expect(detail['routine']['enabled'], false);
      expect(detail['routine']['native']['approvalPolicy'], isNull);
      note('pausedUntilConfigured', true);
    }
    addTearDown(() async {
      if (client.online) {
        await client.rpc('commands.execute', {
          'botId': botId,
          'conversationId': conversationId,
          'command': '/cron pause $jobId',
          'clientMsgId': uid(),
        });
      }
    });
    final question = messages()
        .where(
          (m) =>
              m.kind == 'text' &&
              m.author.type == 'bot' &&
              m.status == 'done' &&
              RegExp('授权|审批|允许').hasMatch('${m.content['text']}'),
        )
        .lastOrNull;
    if (!continuing) {
      expect(
        answeredBeforeCreation || question != null,
        isTrue,
        reason: 'Agent asks about authorization in chat',
      );
    }
    await shot('question');
    Future<void> configure(String answer, bool Function(Json) matches) async {
      await submit(answer);
      var matched = false;
      final deadline = DateTime.now().add(const Duration(minutes: 4));
      while (DateTime.now().isBefore(deadline)) {
        detail = await call('routines.get', target);
        matched = matches(
          object(detail['routine']['native']['approvalPolicy'] ?? {}),
        );
        final readback = messages()
            .where(
              (m) =>
                  m.kind == 'approval' &&
                  m.status == 'streaming' &&
                  '${m.content['command']}'.startsWith(
                    'hermes routine get cron:$jobId',
                  ),
            )
            .firstOrNull;
        if (readback != null) {
          await tap(find.byKey(ValueKey('choice-${readback.messageId}-0')));
          note('readbackApprovedOnce', true);
        }
        if (matched &&
            client.node.activities[conversationId]?.state == 'idle') {
          break;
        }
        await tester.pump(const Duration(milliseconds: 200));
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      expect(
        matched,
        isTrue,
        reason: 'Agent saves the requested rule through its tool',
      );
      await idle();
    }

    var executionId = existingExecution;
    if (!continuing) {
      if (!answeredBeforeCreation) {
        await configure(
          timeRule,
          (p) =>
              p['default'] == 'ask' &&
              objects(p['windows']).any((w) => w['mode'] == 'deny'),
        );
      }
      expect(detail['routine']['native']['approvalPolicy'], {
        'default': 'ask',
        'timezone': 'Asia/Kuala_Lumpur',
        'windows': [
          {
            'start': '22:00',
            'end': '08:00',
            'days': [0, 1, 2, 3, 4, 5, 6],
            'mode': 'deny',
          },
        ],
      });
      note('agentConfiguredDayAskNightDeny', true);
      await shot('policy-conversation');
      await configure(
        '把刚才这个任务改成全天都询问我，去掉所有时段规则，不要现在执行。',
        (p) => p['default'] == 'ask' && objects(p['windows']).isEmpty,
      );
      await submit('/cron run $jobId', waitForAdmission: false);
      ChatMessage? approval;
      await until(() {
        approval = messages()
            .where(
              (m) =>
                  m.kind == 'approval' &&
                  m.messageId.startsWith('routine-approval:') &&
                  '${m.content['runId']}'.startsWith('cron:$jobId:') &&
                  m.status == 'streaming',
            )
            .firstOrNull;
        return approval != null;
      }, 'Cron waits for native approval');
      executionId = '${approval!.content['runId']}';
      note('executionId', executionId);
      expect(approval!.content['choices'], ['once', 'deny']);
      await shot('waiting-approval');
      await tap(find.byKey(ValueKey('choice-${approval!.messageId}-0')));
      await shot('approved');
    }
    String? resultText;
    if (continuing) {
      final previous = objects(detail['executions'])
          .firstWhere((e) => e['executionId'] == existingExecution);
      resultText = previous['text'] as String;
    }
    await until(() {
      if (resultText != null) return true;
      resultText =
          messages()
                  .where(
                    (m) =>
                        m.messageId == 'routine-result:$executionId' &&
                        m.status == 'done',
                  )
                  .firstOrNull
                  ?.content['text']
              as String?;
      return resultText != null;
    }, 'Actual cron output delivered');
    final token = RegExp(r'\b[a-f0-9]{32}\b').firstMatch(resultText!)?.group(0);
    expect(token, isNotNull, reason: 'Real script returns its new UUID');
    note('approvedResult', token);
    if (!finishAllow) {
      await until(
        () => tester.widget<TextField>(input).controller!.text.isEmpty,
        'Cron command completed',
      );
      final seen = messages().map((m) => m.messageId).toSet();
      await submit('不要执行工具。刚刚定时任务返回的随机字符串是什么？原样回复。');
      await until(
        () => messages().any(
          (m) =>
              !seen.contains(m.messageId) &&
              m.kind == 'text' &&
              m.author.type == 'bot' &&
              m.status == 'done' &&
              '${m.content['text']}'.contains(token!),
        ),
        'Ordinary follow-up sees cron result',
      );
      await idle();
      note('ordinaryFollowup', true);
      final linkedMessage = messages().lastWhere(
        (m) => m.content['routine']?['executionId'] == executionId,
      );
      final resultLink = find.byKey(
        ValueKey('routine-result-${linkedMessage.messageId}'),
      );
      await tester.scrollUntilVisible(
        resultLink,
        400,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('chat-messages')),
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 60,
      );
      await tap(resultLink);
      final followup = find.byKey(ValueKey('routine-followup-$executionId'));
      await until(
        () => find.byType(PageList).evaluate().isNotEmpty,
        'Routine details',
      );
      await tester.scrollUntilVisible(
        followup,
        400,
        scrollable: find
            .descendant(
              of: find.byType(PageList),
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 60,
      );
      await tap(followup);
      expect(
        find.byKey(const ValueKey('routine-followup-chip')),
        findsOneWidget,
      );
      final selectedSeen = messages().map((m) => m.messageId).toSet();
      await submit('不要执行工具。只回复我选择的这次执行返回的随机字符串。');
      await until(
        () => messages().any(
          (m) =>
              !selectedSeen.contains(m.messageId) &&
              m.kind == 'text' &&
              m.author.type == 'bot' &&
              m.status == 'done' &&
              '${m.content['text']}'.contains(token!),
        ),
        'Selected execution follow-up',
      );
      await idle();
      await shot('followup');
      detail = await call('routines.get', target);
      expect(objects(detail['executions']).length, 1);
      if (localFile) expect(await File(file).readAsLines(), [token]);
      note('selectedFollowupWithoutRerun', true);
      await submit('/cron resume $jobId');
      await configure(
        '把任务 $jobId 改成默认自动拒绝所有需要授权的操作，全天生效，不要现在运行。',
        (p) => p['default'] == 'deny' && objects(p['windows']).isEmpty,
      );
      final beforeDeny = messages().map((m) => m.messageId).toSet();
      await submit('/cron run $jobId', waitForAdmission: false);
      await until(
        () => messages().any(
          (m) =>
              !beforeDeny.contains(m.messageId) &&
              m.messageId.startsWith('routine-result:') &&
              m.content['routine']?['routineId'] == routineId &&
              m.status != 'streaming',
        ),
        'Explicit denial returns a real result',
      );
      if (localFile) expect(await File(file).readAsLines(), [token]);
      note('denyDidNotExecuteScript', true);
      await until(
        () => tester.widget<TextField>(input).controller!.text.isEmpty,
        'Denied cron command completed',
      );
      await configure(
        '现在把任务 $jobId 改成默认允许，全天自动同意需要授权的操作，不要现在运行。',
        (p) => p['default'] == 'approve' && objects(p['windows']).isEmpty,
      );
    } else {
      expect(
        detail['routine']['native']['approvalPolicy']['default'],
        'approve',
      );
      await submit('/cron resume $jobId');
      note('continuedAfterVerifiedAllowConfiguration', true);
    }
    final beforeAuto = messages().map((m) => m.messageId).toSet();
    await submit('/cron run $jobId', waitForAdmission: false);
    ChatMessage? autoResult;
    await until(() {
      autoResult = messages()
          .where(
            (m) =>
                m.messageId.startsWith('routine-result:') &&
                m.content['routine']?['routineId'] == routineId &&
                !beforeAuto.contains(m.messageId) &&
                m.status == 'done',
          )
          .firstOrNull;
      return autoResult != null;
    }, 'Automatic approval executes');
    expect(
      messages().where(
        (m) =>
            m.kind == 'approval' &&
            m.messageId.startsWith('routine-approval:') &&
            '${m.content['runId']}'.startsWith('cron:$jobId:') &&
            m.status == 'streaming',
      ),
      isEmpty,
    );
    final autoToken = RegExp(r'\b[a-f0-9]{32}\b')
        .firstMatch('${autoResult!.content['text']}')
        ?.group(0);
    expect(autoToken, isNotNull);
    expect(autoToken, isNot(token));
    if (localFile) {
      expect(await File(file).readAsLines(), [token, autoToken]);
    }
    note('autoAllowResult', autoToken);
    await until(
      () => tester.widget<TextField>(input).controller!.text.isEmpty,
      'Automatic cron command completed',
    );
    await submit('/cron pause $jobId');
    await until(
      () => find
          .byWidgetPredicate(
            (w) => w is ShiningText && w.text == 'Hermes 指令执行中…',
          )
          .evaluate()
          .isEmpty,
      'Final pause command completed',
    );
    await shot('completed');
    expect(tester.takeException(), isNull);
    note('done', true);
    binding.reportData = {...?binding.reportData, ...report};
    if (Platform.isWindows) {
      await File('$evidence/cron-$platform.json')
          .writeAsString(jsonEncode(report));
    }
  }, timeout: const Timeout(Duration(minutes: 25)));
}
