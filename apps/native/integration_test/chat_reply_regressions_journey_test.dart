import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/chat_message.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';
import 'package:nekodot_native/ui/message_markdown.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

// Real clients and model/tool calls. Reuse completed work for selection-only runs.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('main Dot replies, list previews and visible text selections', (
    tester,
  ) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    SharedPreferences.setMockInitialValues({'notification-requested': true});
    final c = NekodotClient(vault: MemoryVault());
    addTearDown(c.dispose);
    final phone = Platform.isAndroid;
    final platform = phone ? 'android' : 'windows';
    const dm = String.fromEnvironment('QA_SECOND_CONVERSATION');
    const evidence = String.fromEnvironment('QA_EVIDENCE_DIR');
    var converted = false;
    Future<void> frames([int ms = 350]) async {
      final until = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(until)) {
        await tester.pump(const Duration(milliseconds: 40));
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }

    Future<void> wait(bool Function() done, String name) async {
      final until = DateTime.now().add(const Duration(minutes: 6));
      while (!done() && DateTime.now().isBefore(until)) {
        await frames(150);
      }
      expect(done(), isTrue, reason: name);
      debugPrint('CHAT_REPLIES $platform $name');
    }

    Future<void> shot(String name) async {
      await frames();
      expect(tester.takeException(), isNull, reason: name);
      if (phone) {
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
          await tester.pump();
        }
        await binding.takeScreenshot('replies-$platform-$name');
      } else {
        final view = tester.binding.renderViews.first;
        final image = await (view.debugLayer! as OffsetLayer).toImage(
          Offset.zero & view.flutterView.physicalSize,
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(evidence).create(recursive: true);
        await File('$evidence/replies-$platform-$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }
    }

    Future<void> tap(Finder target) async {
      await tester.ensureVisible(target.first);
      await frames();
      await tester.tap(target.hitTestable().first);
      await frames();
    }

    if (!phone) {
      await DesktopHost.initialize();
      await windowManager.setTitle('nekodot Chat Replies QA');
      await windowManager.show();
      tester.view.physicalSize = const Size(1160, 850);
      tester.view.devicePixelRatio = 1;
    }
    await c.prefs.update(locale: 'en', appearance: 'light');
    await c.login(
      const String.fromEnvironment('QA_EMAIL'),
      const String.fromEnvironment('QA_PASSWORD'),
    );
    await c.selectNode(const String.fromEnvironment('QA_NODE'));
    await wait(() => c.online && c.node.conversations.isNotEmpty, 'connected');
    // Begin this journey at the list, independent of the QA account's last route.
    c.workspace['category:${c.selectedNodeId}'] = 'dot';
    c.workspace['conversation:dot:${c.selectedNodeId}'] = null;
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: c.prefs,
        builder: (_, child) => MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorObservers: [nativeRoutes],
          theme: appTheme(
            c.prefs.theme == 'dark' ? Brightness.dark : Brightness.light,
            glass: phone,
          ),
          builder: (_, child) =>
              phone ? Ambient(child: child!) : WindowChrome(child: child!),
          home: HomePage(client: c),
        ),
      ),
    );
    await frames(1000);
    final row = find.byKey(const ValueKey('conversation-$dm'));
    final input = find.byKey(const ValueKey('chat-input'));
    await shot('list-start');
    await tap(row);
    await wait(() => input.evaluate().isNotEmpty, 'chat opened');
    final before = c.node.tasks.keys.toSet();
    final beforeSeq = c.node.seq;
    var workerPreviewChecks = 0;
    var showedWorkerPreview = false;
    void checkPreview() {
      final newest = c.node.messages[dm]?.lastOrNull;
      if (newest?.taskRole == 'execution' &&
          (newest?.kind == 'text' || newest?.kind == 'commentary')) {
        showedWorkerPreview |= c.node.latestText(dm)?.taskRole == 'execution';
        workerPreviewChecks++;
      }
    }

    c.node.conversation(dm).addListener(checkPreview);
    addTearDown(() => c.node.conversation(dm).removeListener(checkPreview));
    var reportId = const String.fromEnvironment('QA_REPORT_MESSAGE');
    if (reportId.isEmpty) {
      await tester.enterText(
        input,
        '帮我核对周报数据。先简短回应我，再安排用 Python 实际计算 19*23、31*17。'
        '最终用中文给我两条 Markdown 列表，每条都同时有加粗的项目名、行内代码和正常文字，'
        '例如 **项目一**：`19*23` 的结果是 **437**。再给一行总结。'
        '不需要浏览网页、不创建文件，也不需要问我。',
      );
      await frames();
      await tap(find.byTooltip('Send'));
      await wait(
        () => c.node.tasks.values.any((t) => !before.contains(t.taskId)),
        'native task started',
      );
      await wait(
        () => c.node.tasks.values
            .where((t) => !before.contains(t.taskId))
            .every((t) => t.reportMessageId != null),
        'native work reported',
      );
      reportId = c.node.tasks.values
          .lastWhere((t) => !before.contains(t.taskId))
          .reportMessageId!;
      final fresh = c.node.messages[dm]!.where((m) => m.seq > beforeSeq);
      expect(
        fresh.any((m) => m.kind == 'tool' && m.taskRole == 'execution'),
        isTrue,
      );
      expect(workerPreviewChecks, greaterThan(0));
      expect(showedWorkerPreview, isFalse);
      debugPrint(
        'CHAT_REPLIES $platform worker preview checks $workerPreviewChecks',
      );
      expect(
        fresh.any((m) => '${m.content['text']}'.contains('silence marker')),
        isFalse,
      );
      expect(
        fresh
            .where((m) => m.taskRole != 'execution' && m.kind == 'text')
            .any(
              (m) =>
                  RegExp(r'^\s*(NO_REPLY|\[SILENT\])\s*$')
                      .hasMatch('${m.content['text']}'),
            ),
        isFalse,
      );
    }
    await c.loadMessages(dm);
    final report = c.node.messages[dm]!.firstWhere(
      (m) => m.messageId == reportId,
    );
    expect('${report.content['text']}', contains('437'));
    expect('${report.content['text']}', contains('527'));
    final preview = c.node.latestText(dm)!;
    expect(preview.taskRole, isNot('execution'));
    debugPrint('CHAT_REPLIES $platform report $reportId');
    // Home stays mounted while the phone opens a chat. Exercise its loaded cache,
    // then close/reopen: private execution rows must never become list previews.
    if (phone) {
      await binding.handlePopRoute();
      await frames();
      await shot('list-after-work');
      final words = tester
          .widgetList<Text>(
            find.descendant(of: row, matching: find.byType(Text)),
          )
          .map((t) => t.data ?? '')
          .join(' ');
      expect(words, contains('437'));
      await tap(row);
      await wait(() => c.node.messages[dm]?.isNotEmpty == true, 'reopened');
      expect(c.node.latestText(dm)!.messageId, preview.messageId);
    }
    final user = c.node.messages[dm]!.lastWhere((m) => m.author.type == 'user');
    Finder tile(String id) => find.byWidgetPredicate(
      (w) => w is MessageTile && w.message.messageId == id,
    );
    Future<void> select(String id, String name) async {
      final target = tile(id);
      await Scrollable.ensureVisible(tester.element(target), alignment: .5);
      await frames();
      final paragraphs = find.descendant(
        of: find.descendant(of: target, matching: find.byType(MessageMarkdown)),
        matching: find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().trim().length > 4,
        ),
      );
      final text = paragraphs.first;
      final at = tester.getTopLeft(text) + const Offset(6, 10);
      if (phone) {
        await tester.longPressAt(at);
        await frames();
        await tap(find.text('Select all'));
      } else {
        final drag = await tester.startGesture(
          at,
          kind: PointerDeviceKind.mouse,
        );
        await drag.moveTo(at + const Offset(40, 0));
        await frames(100);
        await drag.up();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      }
      await shot(name);
      final region = tester.state<SelectionAreaState>(
        find.descendant(of: target, matching: find.byType(SelectionArea)).first,
      );
      expect(region.selectableRegion.contextMenuButtonItems, isNotEmpty);
      region.selectableRegion.clearSelection();
      region.selectableRegion.hideToolbar();
      await frames();
    }

    for (final theme in ['light', 'dark']) {
      await c.prefs.update(appearance: theme);
      await frames(600);
      await select(reportId, '$theme-markdown-selected');
      await select(user.messageId, '$theme-user-selected');
    }
    await shot('finished');
    await tester.pumpWidget(const SizedBox());
  });
}
