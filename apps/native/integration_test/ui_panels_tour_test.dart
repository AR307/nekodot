import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/chat_models.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/files.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// Walks what opens beside a conversation against a running Relay with a real
/// Node, Hermes and model, and writes a PNG of each step: Flow as a panel and
/// one step's result, Bot details as a drawer with its parts, two files as
/// tabs; then on a phone, Flow folded into the conversation and opened, and
/// details and a file as sheets. One real command is run so there are steps
/// to show, and one message carries two small files to open.
/// Defines: RELAY_URL, QA_TOKEN, QA_NODE, QA_CONVERSATION, QA_GROUP, TOUR_OUT.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('panels tour', (tester) async {
    final client = NekodotClient();
    final navigator = GlobalKey<NavigatorState>();
    final mode = ValueNotifier(ThemeMode.light);
    var glass = false;
    client.account.token = const String.fromEnvironment('QA_TOKEN');
    await tester.runAsync(() async {
      await client.bootstrap();
      await client.selectNode(const String.fromEnvironment('QA_NODE'));
      while (client.node.conversations.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    const shell = String.fromEnvironment('TOUR_OUT');
    final out = Directory('$shell/../panels');
    await tester.runAsync(() => out.create(recursive: true));

    Future<void> run(Duration time) async {
      final end = DateTime.now().add(time);
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 40));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
      }
    }

    Future<bool> until(bool Function() test, {int seconds = 120}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!test() && DateTime.now().isBefore(end)) {
        await run(const Duration(milliseconds: 300));
      }
      return test();
    }

    Future<void> shot(String name, {int settle = 900}) async {
      await run(Duration(milliseconds: settle));
      final view = tester.binding.renderViews.first;
      // ignore: invalid_use_of_protected_member
      final layer = view.layer! as OffsetLayer;
      final size = tester.view.physicalSize;
      await tester.runAsync(() async {
        final ui.Image image = await layer.toImage(Offset.zero & size);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${out.path}/$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      // ignore: avoid_print
      print('TOUR ${out.path}/$name.png');
    }

    Widget app() => ValueListenableBuilder(
      valueListenable: mode,
      builder: (context, value, _) => MaterialApp(
        navigatorKey: navigator,
        debugShowCheckedModeBanner: false,
        navigatorObservers: [nativeRoutes],
        theme: appTheme(Brightness.light, glass: glass),
        darkTheme: appTheme(Brightness.dark, glass: glass),
        themeMode: value,
        builder: (context, child) =>
            glass ? Ambient(child: child!) : WindowChrome(child: child!),
        home: HomePage(client: client),
      ),
    );

    final notes = <String, Object?>{};
    const dm = String.fromEnvironment('QA_CONVERSATION');
    // The second Bot's conversation is short and has nothing left waiting.
    final asking = client.node.conversations.firstWhere(
      (c) => c['kind'] != 'group' && c['conversationId'] != dm,
    );
    final talk = '${asking['conversationId']}', botId = '${asking['botId']}';
    Finder key(String name) => find.byKey(ValueKey(name));
    Finder row(String id) => key('conversation-$id');
    final input = key('chat-input');
    bool idle() => (client.node.activities[talk]?.state ?? 'idle') == 'idle';

    // One message with two small files, sent once; the cards under it open
    // them.
    const note = '周报-第46周.md', picture = '截图.png', marker = '这是本周周报和一张截图。';
    List<String> sent() => [
      for (final m in client.node.messages[talk] ?? <ChatMessage>[])
        if (m.content['text'] == marker)
          ...List<String>.from(m.content['files'] as List? ?? const []),
    ];
    // The panel's own close button, not the window's.
    final closePanel = find.descendant(
      of: key('workspace-side-panel'),
      matching: find.byTooltip('关闭'),
    );
    // Opens a file as its card in the conversation does when tapped.
    final loaded = <Json>[];
    void openFile(int index) =>
        unawaited(showFileViewer(tester.element(input), client, loaded[index]));

    // ---------- desktop ----------
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2;
    client.workspace.remove('category:${client.selectedNodeId}');
    client.workspace.remove('details:${client.selectedNodeId}');
    await tester.pumpWidget(app());
    await run(const Duration(milliseconds: 600));
    await tester.tap(row(talk));
    await run(const Duration(milliseconds: 800));
    final leftover = key('composer-stop');
    if (leftover.evaluate().isNotEmpty) await tester.tap(leftover);
    notes['clear'] = await until(idle, seconds: 60);
    if (sent().length < 2) {
      await tester.runAsync(() async {
        final text = File('${out.path}/$note');
        await text.writeAsString(
          const [
            '# 第 46 周周报',
            '',
            '## 本周完成',
            '',
            '- 首页改为导轨加最近列表',
            '- 对话页头部、审批卡和输入框换成新样式',
            '- 动效统一为一套弹簧',
            '',
            '## 下周计划',
            '',
            '1. Flow、Bot 详情、文件预览',
            '2. 新建 Bot 与添加电脑',
            '3. 设置与统计',
            '',
            '> 所有页面在电脑和手机上各验一遍。',
            '',
          ].join(String.fromCharCode(10)),
        );
        final image = File('$shell/desk-light-recent.png');
        final node = client.selectedNodeId!;
        await client.deliveries.enqueue(
          'messages.send',
          {'conversationId': talk, 'text': marker, 'clientMsgId': uid()},
          node,
          [
            {
              'localPath': text.path,
              'name': note,
              'size': await text.length(),
              'nodeId': node,
              'conversationId': talk,
              'mime': 'text/markdown',
            },
            {
              'localPath': image.path,
              'name': picture,
              'size': await image.length(),
              'nodeId': node,
              'conversationId': talk,
              'mime': 'image/png',
            },
          ],
        );
      });
      notes['filesSent'] = await until(() => sent().length >= 2, seconds: 60);
      await until(() => !idle(), seconds: 15);
      await until(idle, seconds: 120);
    }
    final files = sent();
    await tester.runAsync(() async {
      for (final id in files) {
        loaded.add(await client.rpc('files.get', {'fileId': id}));
      }
    });

    // One command, so that Flow has steps of this run to show.
    await tester.runAsync(
      () => client.rpc('bots.update', {'botId': botId, 'approvalMode': 'off'}),
    );
    await tester.tap(input);
    await run(const Duration(milliseconds: 150));
    tester
            .widget<EditableText>(
              find.descendant(of: input, matching: find.byType(EditableText)),
            )
            .controller
            .text =
        '请在终端执行这条命令，然后把输出原样告诉我：'
        'python -c "import platform; print(platform.system())"';
    await run(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('发送'));
    await until(() => !idle(), seconds: 20);
    await tester.tap(key('chat-flowchart'));
    await shot('desk-light-flow-running', settle: 2500);
    notes['replied'] = await until(idle, seconds: 150);
    await shot('desk-light-flow', settle: 1500);
    final step = client.node
        .flow(talk)
        ?.steps
        .where((s) => s.tool != null && s.messageId != null)
        .lastOrNull;
    notes['steps'] = [
      for (final s in client.node.flow(talk)?.steps ?? [])
        '${s.kind}:${s.state}',
    ];
    if (step != null) {
      await tester.tap(key('flow-step-${step.stepId}'));
      await shot('desk-light-flow-step', settle: 1500);
      navigator.currentState!.pop();
      await run(const Duration(milliseconds: 400));
    }
    mode.value = ThemeMode.dark;
    await shot('desk-dark-flow');
    mode.value = ThemeMode.light;
    await run(const Duration(milliseconds: 300));
    await tester.tap(key('flow-close'));
    await run(const Duration(milliseconds: 600));

    // Bot details: a drawer with one long page.
    await tester.tap(find.byTooltip('详情'));
    await shot('desk-light-details', settle: 2500);
    await tester.tap(key('details-part-1'));
    await shot('desk-light-details-memory');
    await tester.tap(key('details-part-3'));
    await shot('desk-light-details-settings');
    mode.value = ThemeMode.dark;
    await shot('desk-dark-details');
    mode.value = ThemeMode.light;
    await run(const Duration(milliseconds: 300));

    // Files open beside the conversation, one tab each.
    await tester.tap(closePanel.first);
    await run(const Duration(milliseconds: 700));
    openFile(0);
    await shot('desk-light-file', settle: 2000);
    openFile(1);
    await shot('desk-light-file-tabs', settle: 2500);
    await tester.tap(key('file-tab-${files[0]}'));
    await shot('desk-light-file-first-tab', settle: 1200);
    mode.value = ThemeMode.dark;
    await shot('desk-dark-file-tabs');
    mode.value = ThemeMode.light;
    await run(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('关闭标签').first);
    await shot('desk-light-file-one-closed', settle: 700);
    await tester.tap(closePanel.first);
    await run(const Duration(milliseconds: 600));

    // ---------- phone ----------
    await tester.pumpWidget(const SizedBox.shrink());
    glass = true;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 108, bottom: 72);
    await tester.pumpWidget(app());
    await run(const Duration(milliseconds: 600));
    navigator.currentState!.popUntil((route) => route.isFirst);
    await run(const Duration(milliseconds: 500));
    await tester.tap(row(talk));
    await run(const Duration(milliseconds: 1200));
    // The steps sit under the latest message; go there if it opened higher.
    if (key('chat-latest').evaluate().isNotEmpty) {
      await tester.tap(key('chat-latest'));
    }
    await shot('phone-light-flow-folded', settle: 1200);
    await tester.tap(key('flow-fold-toggle'));
    await shot('phone-light-flow-open', settle: 1500);
    if (step != null) {
      final line = find.descendant(
        of: key('flow-fold-step-${step.stepId}'),
        matching: find.byType(InkWell),
      );
      await tester.ensureVisible(line.first);
      await run(const Duration(milliseconds: 300));
      await tester.tap(line.first);
      await shot('phone-light-flow-step', settle: 1500);
    }
    mode.value = ThemeMode.dark;
    await shot('phone-dark-flow-open');
    mode.value = ThemeMode.light;
    await run(const Duration(milliseconds: 300));
    await tester.tap(key('flow-fold-toggle'));
    await run(const Duration(milliseconds: 600));

    await tester.tap(find.byTooltip('详情'));
    await shot('phone-light-details', settle: 2500);
    await tester.tap(find.text('资料库'));
    await shot('phone-light-details-files', settle: 1200);
    mode.value = ThemeMode.dark;
    await shot('phone-dark-details-files');
    mode.value = ThemeMode.light;
    await run(const Duration(milliseconds: 300));
    navigator.currentState!.pop();
    await run(const Duration(milliseconds: 600));
    openFile(0);
    await shot('phone-light-file', settle: 2500);
    mode.value = ThemeMode.dark;
    await shot('phone-dark-file');
    navigator.currentState!.pop();
    await run(const Duration(milliseconds: 500));

    tester.view.reset();
    client.dispose();
    // ignore: avoid_print
    print('TOUR ${jsonEncode({'done': true, ...notes})}');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
