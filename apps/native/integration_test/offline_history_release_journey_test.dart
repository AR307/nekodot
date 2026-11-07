import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/chat.dart';
import 'package:nekodot_native/features/chat_timeline.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'released native history reopens offline without retaining closed pages',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'language': 'zh',
        'notification-requested': true,
      });
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(640, 860));
      final c = NekodotClient(vault: MemoryVault());
      final capture = GlobalKey();
      const dm = String.fromEnvironment('QA_CONVERSATION');
      Future<void> until(bool Function() ready, {int seconds = 90}) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!ready() && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
        }
        expect(ready(), isTrue);
      }

      Future<void> fault(bool off) async {
        await tester.runAsync(
          () => http.get(
            Uri.parse(
              '${const String.fromEnvironment('RELAY_URL')}/__fault?mode=${off ? 'offline' : 'online'}',
            ),
          ),
        );
        await until(() => off ? !c.online : c.online);
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
      await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await until(() => c.connection.ready);
      await tester.runAsync(
        () => c.selectNode(const String.fromEnvironment('QA_NODE')),
      );
      await until(
        () =>
            c.online &&
            find.byType(HomePage, skipOffstage: false).evaluate().isNotEmpty,
      );
      final nav = Navigator.of(
        tester.element(find.byType(HomePage, skipOffstage: false)),
      );
      await windowManager.setMinimumSize(const Size(400, 400));
      await windowManager.setSize(const Size(640, 860));
      await tester.pump(const Duration(milliseconds: 500));
      nav.popUntil((route) => route.isFirst);
      await tester.pump(const Duration(milliseconds: 500));
      await until(
        () => find.byType(ChatPage, skipOffstage: false).evaluate().isEmpty,
      );
      Future<void> open() async {
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => ChatPage(client: c, conversationId: dm),
          ),
        );
        await until(
          () =>
              find.byType(ChatTimeline).evaluate().isNotEmpty &&
              c.node.messages[dm]?.isNotEmpty == true,
        );
        await tester.pump(const Duration(seconds: 1));
      }

      await open();
      await tester.runAsync(() => c.loadMessages(dm));
      final ids = c.node.messages[dm]!.map((m) => m.messageId).toSet();
      final input = find.byKey(const ValueKey('chat-input'));
      final draft = 'MERGE_UNSENT_${DateTime.now().millisecondsSinceEpoch}';
      await tester.enterText(input, draft);
      FocusManager.instance.primaryFocus?.unfocus();
      final timeline = tester.widget<ChatTimeline>(find.byType(ChatTimeline));
      timeline.scroll.jumpTo(
        (timeline.scroll.position.minScrollExtent + 400).clamp(
          timeline.scroll.position.minScrollExtent,
          timeline.scroll.position.maxScrollExtent,
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      final before = timeline.scroll.offset;
      await fault(true);
      nav.pop();
      await until(
        () => find.byType(ChatPage, skipOffstage: false).evaluate().isEmpty,
      );
      expect(c.node.messages.containsKey(dm), isFalse);
      await open();
      expect(
        c.node.messages[dm]!.map((m) => m.messageId).toSet(),
        containsAll(ids),
      );
      expect(tester.widget<TextField>(input).controller!.text, draft);
      expect(
        tester.widget<ChatTimeline>(find.byType(ChatTimeline)).scroll.offset,
        closeTo(before, 2),
      );
      await tester.runAsync(() async {
        final img =
            await (capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        await File(
          '${const String.fromEnvironment('QA_EVIDENCE_DIR')}/merge-offline-history.png',
        ).writeAsBytes(
          (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer
              .asUint8List(),
        );
        img.dispose();
      });
      await fault(false);
      await tester.enterText(input, '只回复 MERGE_HISTORY_OK，不调用工具。');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('发送'));
      await until(
        () => c.node.messages[dm]!.any(
          (m) =>
              m.author.type == 'bot' &&
              m.status == 'done' &&
              m.content['text'] == 'MERGE_HISTORY_OK',
        ),
        seconds: 240,
      );
      final report = {
        'closedHistoryReleased': true,
        'offlineDiskRestored': true,
        'draftPreserved': true,
        'scrollPreserved': true,
        'realModelReply': true,
      };
      await tester.runAsync(
        () => File(
          '${const String.fromEnvironment('QA_EVIDENCE_DIR')}/merge-offline-history.json',
        ).writeAsString(jsonEncode(report)),
      );
      binding.reportData = report;
    },
    timeout: const Timeout(Duration(minutes: 7)),
  );
}
