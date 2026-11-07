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
import 'package:nekodot_native/features/chat.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/routines.dart';
import 'package:nekodot_native/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

// Real isolated Relay HTTP ingress, native Hermes and model, not public HTTPS.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'webhook completes while client is offline and result can be discussed',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'language': 'zh',
        'notification-requested': true,
      });
      final c = NekodotClient(vault: MemoryVault());
      final capture = GlobalKey();
      const dm = String.fromEnvironment('QA_CONVERSATION');
      final marker = 'OFFLINE_HOOK_${DateTime.now().millisecondsSinceEpoch}';
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

      Future<void> tap(Finder f) async {
        await until(() => f.evaluate().isNotEmpty);
        await tester.ensureVisible(f);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(f);
        await tester.pump(const Duration(milliseconds: 350));
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
      await tester.runAsync(
        () => c.selectNode(const String.fromEnvironment('QA_NODE')),
      );
      await until(
        () => c.online && find.byType(HomePage).evaluate().isNotEmpty,
      );
      final botId =
          c.node.conversations.firstWhere(
                (r) => r['conversationId'] == dm,
              )['botId']
              as String;
      final nav = Navigator.of(tester.element(find.byType(HomePage)));
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => ChatPage(client: c, conversationId: dm),
        ),
      );
      final input = find.byKey(const ValueKey('chat-input'));
      await until(() => input.evaluate().isNotEmpty);
      Future<void> send(String text) async {
        await tester.enterText(input, text);
        await tester.pump(const Duration(milliseconds: 200));
        await tap(find.byTooltip('发送'));
        await until(
          () => tester.widget<TextField>(input).controller!.text.isEmpty,
        );
      }

      stage = 'real model creates webhook';
      await send(
        '这是隔离验收。读取 nekodot-routines skill，用原生 CLI 创建名为 $marker 的纯 webhook 任务，事件类型 test。固定提示要求读取事件中的数字，计算 43*47，然后只输出 $marker 和结果，不使用工具。事件原文用 {__raw__}。不要创建 cron，不要现在计算，不要删除任何任务，创建后结束本轮等待用户在任务详情确认接入。',
      );
      await until(
        () =>
            c.node.messages[dm]!.any(
              (m) => m.kind == 'routine' && m.content['name'] == marker,
            ) &&
            c.node.activities[dm]?.state == 'idle',
        seconds: 360,
      );
      final card = c.node.messages[dm]!.firstWhere(
        (m) => m.kind == 'routine' && m.content['name'] == marker,
      );
      final routineId = card.content['routineId'] as String;
      final target = {'botId': botId, 'routineId': routineId};
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              RoutinePage(client: c, botId: botId, routineId: routineId),
        ),
      );
      await until(() => find.byType(RoutinePage).evaluate().isNotEmpty);
      await tester.runAsync(() => c.rpc('routines.get', target));
      await tester.pump(const Duration(seconds: 1));
      final scroll = find
          .descendant(
            of: find.byType(RoutinePage),
            matching: find.byType(Scrollable),
          )
          .first;
      final grant = find.widgetWithText(FilledButton, '确认接入并保密交付');
      await tester.scrollUntilVisible(
        grant,
        300,
        scrollable: scroll,
        maxScrolls: 30,
      );
      await tap(grant);
      await until(() => find.text('暂停 Webhook').evaluate().isNotEmpty);
      final credentials = (await tester.runAsync(
        () => c.rpc('routines.credentials', target),
      ))!;
      await fault(true);
      stage = 'real webhook while client offline';
      final response = (await tester.runAsync(
        () => http.post(
          Uri.parse(
            '${const String.fromEnvironment('QA_HOOK_ORIGIN')}/hooks/$routineId',
          ),
          headers: {
            'Authorization': 'Bearer ${credentials['secret']}',
            'Content-Type': 'application/json',
            'X-Request-ID': marker,
          },
          body: jsonEncode({'event_type': 'test', 'message': marker}),
        ),
      ))!;
      expect(
        response.statusCode,
        inInclusiveRange(200, 299),
        reason: 'Isolated real Relay webhook must accept delivery',
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 20)),
      );
      await tester.pump();
      expect(find.byType(RoutinePage), findsOneWidget);
      await fault(false);
      await until(
        () => c.node.messages[dm]!.any(
          (m) =>
              m.content['routine']?['routineId'] == routineId &&
              m.kind == 'text' &&
              m.status == 'done' &&
              '${m.content['text']}'.contains('2021'),
        ),
        seconds: 360,
      );
      final result = c.node.messages[dm]!.firstWhere(
        (m) =>
            m.content['routine']?['routineId'] == routineId &&
            m.kind == 'text' &&
            '${m.content['text']}'.contains('2021'),
      );
      final executionId = result.content['routine']['executionId'] as String;
      final detail = (await tester.runAsync(
        () => c.rpc('routines.get', target),
      ))!;
      expect(objects(detail['executions']).length, 1);
      nav.pop();
      await tester.pump(const Duration(milliseconds: 350));
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
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      await tester.pump();
      final follow = find.byKey(ValueKey('routine-followup-$executionId'));
      await until(
        () => find
            .descendant(
              of: find.byType(RoutinePage),
              matching: find.byType(Scrollable),
            )
            .evaluate()
            .isNotEmpty,
      );
      await tester.scrollUntilVisible(
        follow,
        350,
        scrollable: scroll,
        maxScrolls: 40,
      );
      await fault(true);
      await tap(follow);
      await until(() => input.evaluate().isNotEmpty);
      await send('根据所选任务结果，只回复 ${marker}_FOLLOWUP 和计算结果，不调用任何工具。');
      expect(
        c.deliveries.items.last['params']['routineExecutionId'],
        executionId,
      );
      await fault(false);
      stage = 'webhook result follow-up';
      await until(
        () => c.node.messages[dm]!.any(
          (m) =>
              m.author.type == 'bot' &&
              m.status == 'done' &&
              '${m.content['text']}'.contains('${marker}_FOLLOWUP') &&
              '${m.content['text']}'.contains('2021'),
        ),
        seconds: 360,
      );
      await tester.pump(const Duration(seconds: 1));
      final report = {
        'realModel': true,
        'isolatedRelayHttp': true,
        'publicHttps': false,
        'clientOfflineDuringWebhook': true,
        'oneExecution': true,
        'offlineResultFollowup': true,
        'executionId': executionId,
      };
      await tester.runAsync(() async {
        const dir = String.fromEnvironment('QA_EVIDENCE_DIR');
        await File('$dir/windows-webhook-offline.json')
            .writeAsString(jsonEncode(report));
        final image =
            await (capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        await File('$dir/windows-webhook-recovered.png').writeAsBytes(
          (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
              .asUint8List(),
        );
        image.dispose();
      });
      binding.reportData = report;
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
