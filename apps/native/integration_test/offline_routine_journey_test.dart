import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/bot_model.dart';
import 'package:nekodot_native/features/chat.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/routines.dart';
import 'package:nekodot_native/main.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

class _LifecycleProbe extends WidgetsBindingObserver {
  bool paused = false, returned = false;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) paused = true;
    if (paused && state == AppLifecycleState.resumed) returned = true;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('offline model save, real routine approval and result follow-up', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'language': 'zh',
      'theme': 'light',
      'notification-requested': true,
    });
    final c = NekodotClient(vault: MemoryVault());
    final capture = GlobalKey();
    const node = String.fromEnvironment('QA_NODE'),
        dm = String.fromEnvironment('QA_CONVERSATION');
    final marker =
        'OFFLINE_ROUTINE_${Platform.operatingSystem}_${DateTime.now().millisecondsSinceEpoch}';
    var stage = 'login';
    Future<void> until(bool Function() ready, {int seconds = 180}) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 150));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(ready(), isTrue, reason: stage);
    }

    Future<void> fault(bool offline) async {
      await tester.runAsync(() async {
        final r = await http.get(
          Uri.parse(
            '${const String.fromEnvironment('RELAY_URL')}/__fault?mode=${offline ? 'offline' : 'online'}',
          ),
        );
        expect(r.statusCode, 200);
      });
      await until(() => offline ? !c.online : c.online);
    }

    Future<void> tap(Finder f) async {
      await until(() => f.evaluate().isNotEmpty);
      await tester.ensureVisible(f);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(f);
      await tester.pump(const Duration(milliseconds: 300));
    }

    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: NekodotApp(client: c),
      ),
    );
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
    await tester.runAsync(() => c.selectNode(node));
    await until(() => c.online && find.byType(HomePage).evaluate().isNotEmpty);
    final botId =
        c.node.conversations.firstWhere(
              (v) => v['conversationId'] == dm,
            )['botId']
            as String;
    final bot = c.node.bots.firstWhere((b) => b['botId'] == botId);
    final previousContext = object(bot['modelSettings'] ?? {})['contextLength'];
    final contextLength = previousContext == 100000 ? 99000 : 100000;
    final nav = Navigator.of(tester.element(find.byType(HomePage)));
    if (Platform.isAndroid) {
      stage = 'actual Android background return';
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => ChatPage(client: c, conversationId: dm),
        ),
      );
      final input = find.byKey(const ValueKey('chat-input'));
      await until(() => input.evaluate().isNotEmpty);
      await tester.enterText(input, '${marker}_UNSENT');
      final lifecycle = _LifecycleProbe();
      WidgetsBinding.instance.addObserver(lifecycle);
      debugPrint('OFFLINE ROUTINE: ANDROID_BACKGROUND_READY');
      await until(() => lifecycle.returned, seconds: 180);
      WidgetsBinding.instance.removeObserver(lifecycle);
      expect(
        tester.widget<TextField>(input).controller!.text,
        '${marker}_UNSENT',
      );
      await until(() => !c.online);
      expect(c.node.messages[dm], isNotEmpty);
      await fault(false);
      expect(
        tester.widget<TextField>(input).controller!.text,
        '${marker}_UNSENT',
      );
      await tester.enterText(input, '');
      nav.pop();
      await tester.pump(const Duration(milliseconds: 400));
      debugPrint('OFFLINE ROUTINE: Android background recovered');
    }
    stage = 'save model settings offline';
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => BotModelPage(client: c, botId: botId),
      ),
    );
    await until(
      () => find
          .byKey(const ValueKey('model-context-length'))
          .evaluate()
          .isNotEmpty,
    );
    await until(
      () =>
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('model-choice')),
              )
              .onPressed !=
          null,
    );
    await tester.enterText(
      find.byKey(const ValueKey('model-context-length')),
      '$contextLength',
    );
    await fault(true);
    await tap(find.byKey(const ValueKey('save-bot-model')));
    expect(c.deliveries.items.any((i) => i['method'] == 'bots.update'), isTrue);
    await fault(false);
    await until(() => find.byType(BotModelPage).evaluate().isEmpty);
    expect(
      c.node.bots.firstWhere(
        (b) => b['botId'] == botId,
      )['modelSettings']['contextLength'],
      contextLength,
    );
    await tester.runAsync(
      () => c.continueAction('bots.update', {
        'botId': botId,
        'modelSettings': {'contextLength': previousContext},
      }),
    );
    debugPrint('OFFLINE ROUTINE: model save recovered');
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(client: c, conversationId: dm),
      ),
    );
    final input = find.byKey(const ValueKey('chat-input'));
    await until(() => input.evaluate().isNotEmpty);
    Future<void> send(String text) async {
      await tester.tap(input);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(input, text);
      await tester.pump(const Duration(milliseconds: 200));
      await tap(find.byTooltip('发送'));
      await until(
        () => tester.widget<TextField>(input).controller!.text.isEmpty,
      );
    }

    stage = 'real one-shot cron creation and approval';
    await send(
      '这是隔离验收。请读取 nekodot-routines skill，通过原生 cronjob_manage 创建名为 $marker 的一次性任务（约一分钟后，只运行一次，local 投递）。任务内容：真实调用 terminal 用 Python 计算并打印 37 乘 41，然后仅输出 $marker 和结果。审批策略我已明确选择：每次问我，时区 Asia/Kuala_Lumpur，无时间窗口。用 hermes routine approvals 设置该任务的策略。不要立即自己执行计算，不要删除任务。创建后结束本轮，等后台任务来请求审批。',
    );
    await until(
      () => c.node.messages[dm]!.any(
        (m) =>
            m.kind == 'approval' && m.taskId != null && m.status == 'streaming',
      ),
      seconds: 420,
    );
    final approval = c.node.messages[dm]!.firstWhere(
      (m) =>
          m.kind == 'approval' && m.taskId != null && m.status == 'streaming',
    );
    final task = c.node.tasks[approval.taskId]!;
    final executionId = task.routineExecutionId!;
    await tap(find.byKey(const ValueKey('dot-activity')));
    await fault(true);
    await tap(find.byKey(ValueKey('choice-${approval.messageId}-0')));
    expect(
      c.deliveries.items.any((i) => i['method'] == 'approvals.respond'),
      isTrue,
    );
    await fault(false);
    await until(
      () => c.node.messages[dm]!.any(
        (m) =>
            m.messageId == 'routine-result:$executionId' &&
            m.status == 'done' &&
            '${m.content['text']}'.contains('1517'),
      ),
      seconds: 360,
    );
    await tester.runAsync(
      () => c.rpc('approvals.respond', {
        'messageId': approval.messageId,
        'choice': 'once',
      }),
    );
    final result = c.node.messages[dm]!.firstWhere(
      (m) => m.messageId == 'routine-result:$executionId',
    );
    final routineId = result.content['routine']['routineId'] as String;
    final detail = (await tester.runAsync(
      () => c.rpc('routines.get', {'botId': botId, 'routineId': routineId}),
    ))!;
    expect(
      objects(detail['executions'])
          .where((e) => e['executionId'] == executionId)
          .length,
      1,
    );
    debugPrint('OFFLINE ROUTINE: original cron approval resumed');
    stage = 'offline result follow-up';
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => RoutinePage(
          client: c,
          botId: botId,
          routineId: routineId,
          executionId: executionId,
        ),
      ),
    );
    await until(() => find.byType(RoutinePage).evaluate().isNotEmpty);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('routine-followup-$executionId')),
      350,
      scrollable: find
          .descendant(
            of: find.byType(RoutinePage),
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 30,
    );
    await fault(true);
    await tap(find.byKey(ValueKey('routine-followup-$executionId')));
    await until(() => find.byType(ChatPage).evaluate().isNotEmpty);
    await send('请根据我选择的这个定时任务结果回复 ${marker}_FOLLOWUP 和实际计算结果，不要再次调用工具或重新执行任务。');
    expect(
      c.deliveries.items.last['params']['routineExecutionId'],
      executionId,
    );
    await fault(false);
    await until(
      () => c.node.messages[dm]!.any(
        (m) =>
            m.author.type == 'bot' &&
            '${m.content['text']}'.contains('${marker}_FOLLOWUP') &&
            '${m.content['text']}'.contains('1517'),
      ),
      seconds: 360,
    );
    final report = {
      'offlineModelSave': true,
      if (Platform.isAndroid) 'actualBackgroundReturn': true,
      'originalRoutineApproval': true,
      'sameApprovalRetryNoReplay': true,
      'offlineResultFollowup': true,
      'executionId': executionId,
    };
    await tester.runAsync(() async {
      final dir = Platform.isAndroid
          ? '${(await getExternalStorageDirectory())!.path}/offline-routine-evidence'
          : const String.fromEnvironment('QA_EVIDENCE_DIR');
      await Directory(dir).create(recursive: true);
      await File('$dir/${Platform.operatingSystem}-routine-journey.json')
          .writeAsString(jsonEncode(report));
      final image =
          await (capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      await File('$dir/${Platform.operatingSystem}-routine-recovered.png')
          .writeAsBytes(bytes);
      image.dispose();
    });
    binding.reportData = report;
  }, timeout: const Timeout(Duration(minutes: 18)));
}
