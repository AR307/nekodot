import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/chat_timeline.dart';

import 'package:nekodot_native/main.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

/// Actual native UI, Relay, Node, canonical Hermes and model. Only local client
/// preferences/credential storage are isolated from the user's installed App.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('footprint: real tools, released history and reconnect', (
    tester,
  ) async {
    const email = String.fromEnvironment('QA_EMAIL');
    const password = String.fromEnvironment('QA_PASSWORD');
    const nodeId = String.fromEnvironment('QA_NODE');
    const dm = String.fromEnvironment('QA_CONVERSATION');
    const group = String.fromEnvironment('QA_GROUP');
    const toolFile = String.fromEnvironment('QA_TOOL_FILE');
    const evidence = String.fromEnvironment('QA_EVIDENCE_DIR');
    expect(
      [email, password, nodeId, dm, group, toolFile].every((v) => v.isNotEmpty),
      isTrue,
    );
    SharedPreferences.setMockInitialValues({
      'language': 'zh',
      'theme': 'light',
      // Notification consent is a separate, manual acceptance journey.
      'notification-requested': true,
    });
    final c = NekodotClient(vault: MemoryVault());
    final capture = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: NekodotApp(client: c),
      ),
    );
    Future<void> until(bool Function() done, {int seconds = 120}) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (!done() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(
        done(),
        isTrue,
        reason: 'The real journey did not reach its expected state.',
      );
    }

    Future<void> shot(String name) async {
      if (evidence.isEmpty) return;
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
        final directory = Platform.isAndroid
            ? '${(await getExternalStorageDirectory())!.path}/core-evidence'
            : evidence;
        await Directory(directory).create(recursive: true);
        await File('$directory/$name.png').writeAsBytes(bytes);
        image.dispose();
      });
    }

    Future<void> open(String id) async {
      final row = find.byKey(ValueKey('conversation-$id'));
      await tester.pump(const Duration(milliseconds: 300));
      if (row.evaluate().isEmpty &&
          find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty &&
          tester.view.physicalSize.width / tester.view.devicePixelRatio < 840) {
        await tester.pageBack();
        await tester.pump(const Duration(milliseconds: 400));
      }
      await until(() => row.evaluate().isNotEmpty);
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pump(const Duration(milliseconds: 400));
      await until(
        () => find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty,
      );
      await tester.runAsync(() => c.loadMessages(id));
    }

    Future<void> submit(String text) async {
      await tester.enterText(find.byKey(const ValueKey('chat-input')), text);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pump();
    }

    await until(
      () => find.byKey(const ValueKey('auth-email')).evaluate().isNotEmpty,
    );
    await tester.enterText(find.byKey(const ValueKey('auth-email')), email);
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      password,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await until(() => c.connection.ready);
    await tester.runAsync(() => c.selectNode(nodeId));
    await until(() => c.online && c.node.conversations.isNotEmpty);
    // A prior harness exit interrupted introductions. Acknowledge only those
    // real interrupted QA runs through the same Stop control, never replay them.
    for (final conversation in c.node.conversations.toList()) {
      final id = conversation['conversationId'] as String;
      if (c.node.activities[id]?.state != 'unknown') continue;
      await open(id);
      await tester.tap(find.byTooltip('停止'));
      await until(() => c.node.activities[id]?.state == 'idle');
    }
    debugPrint('QA real login and interrupted-run acknowledgement complete');
    await open(dm);
    final before = (c.node.messages[dm] ?? []).map((m) => m.messageId).toSet();
    await submit(
      '请使用文件工具读取 $toolFile ，然后用真实代码工具计算 17 * 19。最终使用 Markdown 列表给出文件原文与计算结果。不要修改或删除文件。',
    );
    debugPrint('QA real file/code prompt submitted');
    await until(
      () => (c.node.messages[dm] ?? []).any(
        (m) => !before.contains(m.messageId) && m.kind == 'tool',
      ),
      seconds: 240,
    );
    await tester.tap(find.byKey(const ValueKey('chat-flowchart')));
    await tester.pump(const Duration(milliseconds: 400));
    await shot('dm-flow-running');
    await until(
      () => (c.node.messages[dm] ?? []).any(
        (m) =>
            !before.contains(m.messageId) &&
            m.kind == 'text' &&
            m.author.type == 'bot' &&
            m.status == 'done' &&
            '${m.content['text']}'.contains('NEKODOT_NATIVE_LIVE_OK') &&
            '${m.content['text']}'.contains('323'),
      ),
      seconds: 300,
    );
    await until(() => c.node.activities[dm]?.state == 'idle');
    await shot('dm-flow-complete');
    await tester.tap(find.byKey(const ValueKey('flow-close')));
    await tester.pump(const Duration(milliseconds: 400));
    final completedIds = (c.node.messages[dm] ?? [])
        .map((m) => m.messageId)
        .toSet();
    await tester.runAsync(c.connection.connect);
    await until(() => c.connection.ready && !c.node.syncing);
    await tester.runAsync(() => c.loadMessages(dm));
    expect(
      (c.node.messages[dm] ?? []).map((m) => m.messageId).toSet(),
      containsAll(completedIds),
    );
    final turnCount = (c.node.messages[dm] ?? [])
        .where((m) => m.kind == 'tool')
        .length;
    await tester.pump(const Duration(seconds: 1));
    expect(
      (c.node.messages[dm] ?? []).where((m) => m.kind == 'tool').length,
      turnCount,
    );
    await open(group);
    expect(c.node.messages.containsKey(dm), isFalse);
    expect(c.node.latest[dm]?.content['text'], contains('323'));
    await open(dm);
    expect(
      (c.node.messages[dm] ?? []).map((m) => m.messageId).toSet(),
      containsAll(completedIds),
    );
    await open(group);
    expect(c.node.messages.containsKey(dm), isFalse);
    final groupBefore = (c.node.messages[group] ?? [])
        .map((m) => m.messageId)
        .toSet();
    await submit('@everyone 每位成员各自用实际工具计算 11 * 13，然后只回复结果。不要提及其他成员，不要接力。');
    await until(
      () =>
          (c.node.messages[group] ?? [])
              .where(
                (m) =>
                    !groupBefore.contains(m.messageId) &&
                    m.kind == 'text' &&
                    m.author.type == 'bot' &&
                    m.status == 'done' &&
                    '${m.content['text']}'.contains('143'),
              )
              .map((m) => m.author.id)
              .toSet()
              .length ==
          2,
      seconds: 480,
    );
    await until(() => c.node.activities[group]?.state == 'idle');
    await tester.tap(find.byKey(const ValueKey('chat-flowchart')));
    await tester.pump(const Duration(milliseconds: 400));
    await shot('group-flow-complete');
    await tester.tap(find.byKey(const ValueKey('flow-close')));
    await open(dm);
    await submit(
      'Read this checklist and reply with CHECKLIST_OK only.\n' +
          List.generate(
            80,
            (i) =>
                (i + 1).toString() +
                '. Preserve files, tools and session history.',
          ).join('\n'),
    );
    await until(
      () => (c.node.messages[dm] ?? []).any(
        (m) =>
            m.author.type == 'bot' &&
            m.status == 'done' &&
            m.content['text'].toString().contains('CHECKLIST_OK'),
      ),
    );
    await until(() => c.node.activities[dm]?.state == 'idle');
    final timeline = tester.widget<ChatTimeline>(find.byType(ChatTimeline));
    timeline.scroll.jumpTo(timeline.scroll.position.minScrollExtent + 500);
    await tester.pump(const Duration(milliseconds: 400));
    final readingPosition = timeline.scroll.offset;
    await shot('history-reading');
    await open(group);
    expect(c.node.messages.containsKey(dm), isFalse);
    expect(c.node.viewports[dm]?.offset, closeTo(readingPosition, 1));
    await open(dm);
    await tester.pump(const Duration(seconds: 1));
    final reopened = tester.widget<ChatTimeline>(find.byType(ChatTimeline));
    expect(reopened.scroll.offset, closeTo(readingPosition, 1));
    await shot('history-restored');
    binding.reportData = {
      'platform': Platform.operatingSystem,
      'realModel': 'gpt-6.1-sol',
      'fileRead': true,
      'codeExecution': true,
      'groupBots': 2,
      'closedHistoryReleased': true,
      'reopenedHistoryIntact': true,
      'reconnectNoReplay': true,
      'readingPositionRestored': true,
    };
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
