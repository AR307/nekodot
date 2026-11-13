import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/chat_models.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// Walks a conversation against a running Relay with a real Node, Hermes and
/// model, and writes a PNG of each step: the header, the composer empty and
/// with words in it, the line that says what the Dot is doing, a command
/// waiting for an answer and after it, stopping a run, and a group. The Bot
/// is set to ask before each command for the length of the tour.
/// Defines: RELAY_URL, QA_TOKEN, QA_NODE, QA_CONVERSATION, QA_GROUP, TOUR_OUT.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('conversation tour', (tester) async {
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
    final out = Directory(
      '${const String.fromEnvironment('TOUR_OUT')}/../chat',
    );
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

    Future<bool> until(bool Function() test, {int seconds = 150}) async {
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
    const room = String.fromEnvironment('QA_GROUP');
    // Commands are asked of the second Bot, whose conversation is short.
    final asking = client.node.conversations.firstWhere(
      (c) => c['kind'] != 'group' && c['conversationId'] != dm,
    );
    final talk = '${asking['conversationId']}', botId = asking['botId'];
    Finder row(String id) => find.byKey(ValueKey('conversation-$id'));
    final input = find.byKey(const ValueKey('chat-input'));
    bool idle(String id) =>
        (client.node.activities[id]?.state ?? 'idle') == 'idle';
    ChatMessage? waiting() => (client.node.messages[talk] ?? [])
        .where((m) => m.kind == 'approval' && m.status == 'streaming')
        .lastOrNull;
    Finder choice(ChatMessage m, int index) =>
        find.byKey(ValueKey('choice-${m.messageId}-$index'));
    // Puts words in the composer, replacing what was there.
    Future<void> type(String text) async {
      await tester.tap(input);
      await run(const Duration(milliseconds: 150));
      tester
              .widget<EditableText>(
                find.descendant(of: input, matching: find.byType(EditableText)),
              )
              .controller
              .text =
          text;
      await run(const Duration(milliseconds: 300));
    }

    Future<void> say(String text) async {
      await type(text);
      await tester.tap(find.byTooltip('发送'));
    }

    Future<void> approvals(String mode) => tester.runAsync(
      () => client.rpc('bots.update', {'botId': botId, 'approvalMode': mode}),
    );

    // Running a script through an interpreter is what Hermes asks about.
    // The first Bot allows every command again, whatever a tour left it at.
    await tester.runAsync(
      () => client.rpc('bots.update', {
        'botId': client.node.conversations.firstWhere(
          (c) => c['conversationId'] == dm,
        )['botId'],
        'approvalMode': 'off',
      }),
    );
    const command =
        '请在终端执行这条命令，然后把输出原样告诉我：'
        'python -c "import platform, sys; print(platform.system(), sys.version_info[:2])"';

    // ---------- desktop ----------
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2;
    client.workspace.remove('category:${client.selectedNodeId}');
    await tester.pumpWidget(app());
    await run(const Duration(milliseconds: 600));
    await tester.tap(row(dm));
    await shot('desk-light-open');
    await type('帮我看一下这个仓库最近一周改了什么，按模块列出来。');
    await shot('desk-light-typed', settle: 700);
    await tester.tap(find.byKey(const ValueKey('reasoning-toggle')));
    await shot('desk-light-reasoning', settle: 1500);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await run(const Duration(milliseconds: 500));
    notes['reasoningClosed'] = find
        .byKey(const ValueKey('reasoning-slider'))
        .evaluate()
        .isEmpty;
    await type('');

    // A command that waits for an answer. Whatever an earlier tour left
    // unfinished there is stopped first.
    await tester.tap(row(talk));
    await run(const Duration(milliseconds: 800));
    final leftover = find.byKey(const ValueKey('composer-stop'));
    if (leftover.evaluate().isNotEmpty) await tester.tap(leftover);
    notes['deskClear'] = await until(() => idle(talk), seconds: 60);
    await approvals('manual');
    await say(command);
    await shot('desk-light-working', settle: 2200);
    notes['deskApproval'] = await until(() => waiting() != null, seconds: 90);
    await shot('desk-light-approval', settle: 1200);
    final asked = waiting();
    if (asked != null) {
      notes['deskChoices'] = asked.content['choices'];
      final fold = find.byKey(const ValueKey('command-fold')).last;
      await tester.tap(fold);
      await shot('desk-light-approval-folded', settle: 700);
      await tester.tap(fold);
      await run(const Duration(milliseconds: 500));
      await tester.tap(choice(asked, 0));
      await shot('desk-light-approval-answered', settle: 900);
    }
    // Any further command in the same run is allowed too.
    final end = DateTime.now().add(const Duration(seconds: 180));
    while (!idle(talk) && DateTime.now().isBefore(end)) {
      final next = waiting();
      if (next != null && choice(next, 0).evaluate().isNotEmpty) {
        await tester.tap(choice(next, 0));
      }
      await run(const Duration(milliseconds: 500));
    }
    notes['deskReplied'] = idle(talk);
    await shot('desk-light-replied', settle: 1500);
    if (asked != null) {
      await tester.tap(find.byKey(const ValueKey('command-fold')).last);
      await shot('desk-light-approval-reopened', settle: 700);
      await tester.tap(find.byKey(const ValueKey('command-fold')).last);
      await run(const Duration(milliseconds: 400));
    }

    // Stopping a run from the composer.
    await approvals('off');
    await say('写一篇八百字的短文，介绍猫的习性。');
    await until(() => !idle(talk), seconds: 20);
    await shot('desk-light-running', settle: 2500);
    final stop = find.byKey(const ValueKey('composer-stop'));
    notes['deskStopShown'] = stop.evaluate().isNotEmpty;
    if (stop.evaluate().isNotEmpty) await tester.tap(stop);
    notes['deskStopped'] = await until(() => idle(talk), seconds: 60);
    await shot('desk-light-stopped', settle: 1200);

    // A group: each Dot under its own name.
    await tester.tap(row(room));
    await run(const Duration(milliseconds: 600));
    await say('每人用一句话打个招呼。');
    await until(() => !idle(room), seconds: 20);
    await shot('desk-light-group-working', settle: 2500);
    notes['deskGroupReplied'] = await until(() => idle(room));
    await shot('desk-light-group', settle: 1500);
    mode.value = ThemeMode.dark;
    await shot('desk-dark-group');
    await tester.tap(row(dm));
    await shot('desk-dark-open');

    // ---------- phone ----------
    await tester.pumpWidget(const SizedBox.shrink());
    glass = true;
    mode.value = ThemeMode.light;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 108, bottom: 72);
    await tester.pumpWidget(app());
    await run(const Duration(milliseconds: 600));
    navigator.currentState!.popUntil((route) => route.isFirst);
    await run(const Duration(milliseconds: 500));
    await tester.tap(row(talk));
    await shot('phone-light-open');
    await type('帮我看一下这个仓库最近一周改了什么，按模块列出来。');
    await shot('phone-light-typed', settle: 700);
    await type('');

    // The same command, refused this time.
    await approvals('manual');
    await say(command);
    await shot('phone-light-working', settle: 2200);
    notes['phoneApproval'] = await until(() => waiting() != null, seconds: 90);
    await shot('phone-light-approval', settle: 1200);
    final refused = waiting();
    if (refused != null) {
      final choices = [...?(refused.content['choices'] as List?)];
      final deny = choices.isEmpty ? 1 : choices.indexOf('deny');
      await tester.tap(choice(refused, deny));
      await shot('phone-light-approval-refused', settle: 900);
    }
    final phoneEnd = DateTime.now().add(const Duration(seconds: 150));
    while (!idle(talk) && DateTime.now().isBefore(phoneEnd)) {
      final next = waiting();
      final choices = [...?(next?.content['choices'] as List?)];
      final deny = choices.isEmpty ? 1 : choices.indexOf('deny');
      if (next != null && choice(next, deny).evaluate().isNotEmpty) {
        await tester.tap(choice(next, deny));
      }
      await run(const Duration(milliseconds: 500));
    }
    notes['phoneReplied'] = idle(talk);
    await shot('phone-light-replied', settle: 1500);
    await approvals('off');
    mode.value = ThemeMode.dark;
    await shot('phone-dark-open');
    navigator.currentState!.pop();
    await run(const Duration(milliseconds: 600));
    await tester.tap(row(room));
    await shot('phone-dark-group');
    mode.value = ThemeMode.light;
    await shot('phone-light-group');

    tester.view.reset();
    client.dispose();
    // ignore: avoid_print
    print('TOUR ${jsonEncode({'done': true, ...notes})}');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
