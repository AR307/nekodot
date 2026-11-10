import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';

import 'package:nekodot_native/features/chat.dart';
import 'package:nekodot_native/features/work.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';
import 'package:tray_manager/tray_manager.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real tool output and Markdown survive client reload', (
    tester,
  ) async {
    if (Platform.isWindows) {
      await DesktopHost.initialize();
      expect(
        DesktopHost.icon!.getContextMenuTrigger(),
        ContextMenuTrigger.rightClicked,
      );
      expect(DesktopHost.icon!.isVisible(), isTrue);
    }
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final c = NekodotClient();
    await tester.runAsync(() async {
      final auth = await c.account.request(
        '/auth/login',
        method: 'POST',
        body: {
          'email': const String.fromEnvironment('QA_EMAIL'),
          'password': const String.fromEnvironment('QA_PASSWORD'),
        },
      );
      c.account.token = auth['token'];
      await c.bootstrap();
      await c.selectNode(const String.fromEnvironment('QA_NODE'));
    });
    c.prefs.language = 'zh';
    await tester.runAsync(() async {
      final end = DateTime.now().add(const Duration(seconds: 90));
      while (!c.node.bots.any((b) => b['handle'] == 'tool_lead') &&
          DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    });
    final bot = c.node.bots.firstWhere((b) => b['handle'] == 'tool_lead');
    final dm = c.node.conversations.firstWhere(
      (v) => v['kind'] == 'dm' && v['botId'] == bot['botId'],
    );
    final id = dm['conversationId'] as String;
    await tester.runAsync(() => c.loadMessages(id));
    runApp(
      MaterialApp(
        theme: appTheme(Brightness.light),
        navigatorObservers: [nativeRoutes],
        builder: (_, child) => Platform.isWindows
            ? WindowChrome(child: child!)
            : Ambient(child: child!),
        home: Scaffold(
          body: ChatPage(client: c, conversationId: id),
        ),
      ),
    );
    Future<void> until(bool Function() done, {int seconds = 300}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!done() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 250));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
      }
      expect(done(), isTrue);
    }

    await until(
      () => find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty,
    );
    const prompt =
        '工具详情和Markdown真实复验20261103：请实际调用terminal执行printf输出nekodot-tool-card-ok；再实际调用terminal执行cat research-tool-qa/does-not-exist-for-ui-check.txt，预期文件不存在。不得创建该文件或读取其他文件。不需要审批的无害只读工具即可。最后用Markdown展示：一级标题、以**摘要。**紧接中文的句子、一个成功/预期失败的表格、列表和一个围栏代码块。内容只陈述本次真实观察，明确第二个工具失败不等于整个任务失败。不发送其他成员。';
    final sentBefore = (c.node.messages[id] ?? []).any(
      (m) => m.content['text'] == prompt,
    );
    if (!sentBefore) {
      await tester.enterText(find.byKey(const ValueKey('chat-input')), prompt);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('发送'));
    }
    await until(() {
      final rows = c.node.messages[id] ?? [];
      final user = rows.where((m) => m.content['text'] == prompt).firstOrNull;
      if (user == null) return false;
      return rows.any(
            (m) =>
                m.kind == 'text' &&
                m.author.type == 'bot' &&
                m.status == 'done' &&
                m.seq > user.seq,
          ) &&
          find.byTooltip('停止').evaluate().isEmpty;
    });
    final user = c.node.messages[id]!.firstWhere(
      (m) => m.content['text'] == prompt,
    );
    final tools = c.node.messages[id]!
        .where((m) => m.kind == 'tool' && m.seq > user.seq)
        .toList();
    expect(tools.length, greaterThanOrEqualTo(2));
    expect(
      tools.every(
        (m) =>
            (m.content['preview'] as String).isNotEmpty &&
            (m.content['resultPreview'] as String).isNotEmpty,
      ),
      isTrue,
    );
    expect(tools.any((m) => m.content['error'] == true), isTrue);
    await tester.runAsync(() => c.loadMessages(id));
    expect(tester.takeException(), isNull);
    binding.reportData = {
      'model': bot['model'],
      'platform': Platform.operatingSystem,
      'sentNewPrompt': !sentBefore,
      'toolDetails': tools,
      'trayRightClickTrigger': Platform.isWindows,
      'physicalRightClickTested': false,
    };
    debugPrint(
      'QA real tool details + expected failed tool preserved; Markdown displayed',
    );
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await binding.takeScreenshot('tool-markdown-native-android');
      final tableScroll = find
          .byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.horizontal,
          )
          .first;
      await tester.drag(tableScroll, const Offset(-420, 0));
      await tester.pump(const Duration(milliseconds: 300));
      final tableScrollable = tester.state<ScrollableState>(
        find
            .descendant(of: tableScroll, matching: find.byType(Scrollable))
            .first,
      );
      expect(tableScrollable.position.pixels, greaterThan(0));
      await binding.takeScreenshot('tool-markdown-table-scrolled-android');
      expect(find.byKey(const ValueKey('work-status')), findsNothing);
      expect(find.byType(StepRow), findsNothing);
    } else {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 60)),
      );
    }
    c.dispose();
  }, timeout: const Timeout(Duration(minutes: 12)));
}
