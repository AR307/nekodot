import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/bot_details.dart';
import 'package:nekodot_native/features/user_memory.dart';
import 'package:nekodot_native/main.dart';
import 'package:nekodot_native/ui/design.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real memory counters and silent tool warning recover without stopping',
    (tester) async {
      const dm = String.fromEnvironment('QA_CONVERSATION');
      const observeNotifications = bool.fromEnvironment('QA_NOTIFICATIONS');
      final evidence = Platform.isAndroid
          ? '${(await getApplicationSupportDirectory()).path}/stall-memory-evidence'
          : const String.fromEnvironment('QA_EVIDENCE_DIR');
      const control = String.fromEnvironment('QA_CONTROL');
      SharedPreferences.setMockInitialValues({
        'language': 'zh',
        'theme': 'light',
        'notification-requested': true,
      });
      final c = NekodotClient(vault: MemoryVault());
      final notifications = <String>[];
      final subscription = c.notifications.stream.listen((signal) {
        notifications.add(signal['kind'].toString());
      });
      addTearDown(subscription.cancel);
      if (observeNotifications && Platform.isWindows) {
        await windowManager.ensureInitialized();
        await windowManager.setTitle('Nekodot - Stall notification QA');
      }
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: NekodotApp(client: c),
        ),
      );
      final report = <String, Object?>{
        'platform': Platform.operatingSystem,
        'started': DateTime.now().toUtc().toIso8601String(),
      };
      Future<void> until(
        bool Function() done, {
        int seconds = 180,
        String what = '',
      }) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!done() && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 150));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
        }
        expect(done(), isTrue, reason: what);
      }

      Future<void> shot(String name) async {
        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(() async {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
          await Directory(evidence).create(recursive: true);
          await File('$evidence/${Platform.operatingSystem}-$name.png')
              .writeAsBytes(bytes);
          image.dispose();
        });
      }

      Future<void> command(String path) async {
        await tester.runAsync(() async {
          final http = HttpClient();
          final response = await (await http.postUrl(
            Uri.parse('$control$path'),
          )).close();
          expect(response.statusCode, 200);
          await response.drain<void>();
          http.close();
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
      await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await until(() => c.connection.ready, what: 'login');
      await tester.runAsync(
        () => c.selectNode(const String.fromEnvironment('QA_NODE')),
      );
      await until(
        () =>
            c.online &&
            c.node.conversations.isNotEmpty &&
            c.node.conversations.every(
              (row) =>
                  (c.node.activities[row['conversationId']]?.state ?? 'idle') ==
                  'idle',
            ),
        seconds: 600,
        what: 'node ready',
      );
      await command('/seed-memory');
      final row = find.byKey(const ValueKey('conversation-$dm'));
      await until(
        () => row.evaluate().isNotEmpty,
        what: 'conversation rendered',
      );
      await tester.ensureVisible(row);
      await until(
        () => row.hitTestable().evaluate().isNotEmpty,
        what: 'conversation ready',
      );
      await tester.tap(row.hitTestable().first);
      await until(
        () => find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('详情').hitTestable().first);
      await until(() => find.byType(BotDetails).evaluate().isNotEmpty);
      await until(
        () => find.text('记忆').hitTestable().evaluate().isNotEmpty,
        what: 'memory tab ready',
      );
      await tester.tap(find.text('记忆').hitTestable().first);
      await until(
        () => find.text('2000 / 2200 字符').evaluate().isNotEmpty,
        what: 'native MEMORY limit',
      );
      expect(find.byKey(const ValueKey('refine-memory-full')), findsOneWidget);
      await shot('memory-near-limit');
      await tester.tap(find.text('MEMORY.md').hitTestable().first);
      await until(() => find.byType(MemoryEditor).evaluate().isNotEmpty);
      final edit = find.descendant(
        of: find.byType(MemoryEditor),
        matching: find.byType(TextField),
      );
      await tester.enterText(edit, '中文🙂\n§\n中文🙂\n§\n新内容');
      await tester.pump();
      expect(find.text('9 / 2200 字符'), findsOneWidget);
      await shot('memory-editor');
      Navigator.of(tester.element(edit)).pop();
      await tester.pump(const Duration(milliseconds: 350));
      final detailsContext = tester.element(find.byType(BotDetails));
      pushPage(detailsContext, SharedUserMemoryPage(client: c));
      await until(
        () => find.byType(SharedUserMemoryPage).evaluate().isNotEmpty,
      );
      await until(
        () => find.textContaining('/ 1375 字符').evaluate().isNotEmpty,
        what: 'native USER limit',
      );
      await shot('user-memory');
      Navigator.of(tester.element(find.byType(SharedUserMemoryPage))).pop();
      await tester.pump(const Duration(milliseconds: 350));
      report['memoryLimits'] = {
        'memory': 2200,
        'user': 1375,
        'uniqueUnicodeEditorCount': 9,
      };
      final field = find.byKey(const ValueKey('chat-input'));
      if (field.hitTestable().evaluate().isEmpty) {
        Navigator.of(tester.element(find.byType(BotDetails))).pop();
        await tester.pump(const Duration(milliseconds: 350));
      }
      final before =
          c.node.messages[dm]?.map((m) => m.messageId).toSet() ?? <String>{};
      await tester.tap(field);
      await tester.enterText(
        field,
        '这是受控长任务验收。只调用一次 execute_code，Python 代码必须是 import time; time.sleep(330); print("STALL_RESUMED_330")。不要使用 terminal 或后台进程，不要分段休眠，不要重试。代码工具已设置420秒超时。工具返回后只回复 STALL_RESUMED_330。',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await until(
        () => c.node.activities[dm]?.state == 'tool',
        seconds: 180,
        what: 'real tool started',
      );
      report['toolStarted'] = DateTime.now().toUtc().toIso8601String();
      if (observeNotifications) {
        const other = String.fromEnvironment('QA_SECOND_CONVERSATION');
        final otherRow = find.byKey(const ValueKey('conversation-$other'));
        await tester.ensureVisible(otherRow);
        await tester.tap(otherRow.hitTestable().first);
        await until(() => c.visibleConversation == other);
        expect(c.notificationError, isEmpty);
      }
      await until(
        () => c.node.activities[dm]?.stalled == true,
        seconds: 380,
        what: 'five real minutes of silence',
      );
      expect(c.node.activities[dm]?.connection, isNot('reconnecting'));
      report['stalledAt'] = DateTime.now().toUtc().toIso8601String();
      await tester.pump();
      if (!observeNotifications) {
        expect(find.text('可能卡住').evaluate(), isNotEmpty);
      } else {
        await until(() => notifications.contains('stalled'));
        expect(c.notificationError, isEmpty);
        report['accountNotificationReceived'] = true;
        await tester.runAsync(
          () =>
              File('$evidence/windows-notification-ready.json')
                  .writeAsString(jsonEncode(report)),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 15)),
        );
        expect(c.notificationError, isEmpty);
      }
      await shot('stalled');
      await until(
        () =>
            (c.node.activities[dm]?.state ?? 'idle') == 'idle' &&
            (c.node.messages[dm] ?? []).any(
              (m) =>
                  !before.contains(m.messageId) &&
                  m.kind == 'text' &&
                  m.author.type == 'bot' &&
                  m.status == 'done' &&
                  m.content['text'].toString().contains('STALL_RESUMED_330'),
            ),
        seconds: 180,
        what: 'same real task completed',
      );
      expect(c.node.activities[dm]?.stalled, false);
      report['completedAt'] = DateTime.now().toUtc().toIso8601String();
      final tools = (c.node.messages[dm] ?? [])
          .where((m) => !before.contains(m.messageId) && m.kind == 'tool')
          .toList();
      expect(tools, hasLength(1));
      report['toolCount'] = tools.length;
      await shot('recovered');
      await tester.runAsync(
        () => File(
          '$evidence/${Platform.operatingSystem}${observeNotifications ? '-notification' : ''}-report.json',
        ).writeAsString(jsonEncode(report)),
      );
      binding.reportData = report;
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
