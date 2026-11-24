import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/chat_models.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/chat.dart';
import 'package:nekodot_native/features/chat_composer.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// Acceptance of every Dot doing its own work, outside a private chat too, with
/// the real client on a running Relay with a real Node, Hermes and model:
/// - a group relay where each Dot uses its own tools in its own session and
///   hands on with @;
/// - a message while a Dot works in the group interrupts it and ends the relay;
/// - the Dot remembers its group work when asked in private;
/// - a one-shot scheduled task's result arrives as the Dot's own message, and
///   the Dot knows it when asked.
/// Nothing may be handed to another session. Defines: RELAY_URL, QA_TOKEN,
/// QA_NODE, QA_GROUP, QA_CONVERSATION (the private chat of the group member
/// asked first), QA_ROUTINE_CONVERSATION (a private chat for the scheduled
/// task), TOUR_OUT.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('every Dot works itself in groups and routines', (tester) async {
    final c = NekodotClient();
    c.account.token = const String.fromEnvironment('QA_TOKEN');
    c.prefs.language = 'zh';
    const group = String.fromEnvironment('QA_GROUP');
    const dm = String.fromEnvironment('QA_CONVERSATION');
    const routineDm = String.fromEnvironment('QA_ROUTINE_CONVERSATION');
    final stamp = DateTime.now().millisecondsSinceEpoch.toString();
    await tester.runAsync(() async {
      await c.bootstrap();
      await c.selectNode(const String.fromEnvironment('QA_NODE'));
      while (c.node.conversations.isEmpty || !c.online) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    final out = Directory(const String.fromEnvironment('TOUR_OUT'));
    await tester.runAsync(() => out.create(recursive: true));

    // Each line of thought a status showed, read as the test runs.
    final thoughts = <String>{};
    Future<void> run(Duration time) async {
      final end = DateTime.now().add(time);
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 40));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        for (final id in [group, dm, routineDm]) {
          final thought = c.node.activities[id]?.thought;
          if (thought != null) thoughts.add(thought);
        }
      }
    }

    Future<void> until(
      bool Function() test,
      String label, {
      int seconds = 300,
    }) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!test() && DateTime.now().isBefore(end)) {
        await run(const Duration(milliseconds: 400));
      }
      expect(test(), isTrue, reason: label);
      // ignore: avoid_print
      print('GROUP_QA $label');
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
    }

    Widget app() => MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorObservers: [nativeRoutes],
      theme: appTheme(Brightness.light),
      themeMode: ThemeMode.light,
      builder: (context, child) => WindowChrome(child: child!),
      home: HomePage(client: c),
    );
    Finder key(String name) => find.byKey(ValueKey(name));
    Future<void> open(String id) async {
      if (find
          .byWidgetPredicate((w) => w is ChatPage && w.conversationId == id)
          .evaluate()
          .isNotEmpty) {
        return;
      }
      for (final section in ['group', 'dot']) {
        if (key('conversation-$id').evaluate().isNotEmpty) break;
        if (key('home-section-$section').evaluate().isNotEmpty) {
          await tester.tap(key('home-section-$section'));
          await run(const Duration(milliseconds: 600));
        }
      }
      await tester.tap(key('conversation-$id').hitTestable().first);
      await run(const Duration(milliseconds: 1500));
    }

    c.workspace['conversation:${c.selectedNodeId}'] = group;
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(app());
    await run(const Duration(milliseconds: 1000));

    List<ChatMessage> all(String id) => c.node.messages[id] ?? const [];
    int head(String id) => all(id).fold(0, (s, m) => m.seq > s ? m.seq : s);
    String state(String id) => c.node.activities[id]?.state ?? 'idle';
    List<ChatMessage> botTexts(String id, int after) => all(id)
        .where(
          (m) =>
              m.seq > after &&
              m.author.type == 'bot' &&
              (m.kind == 'text' || m.kind == 'commentary') &&
              m.status == 'done' &&
              '${m.content['text'] ?? ''}'.trim().isNotEmpty,
        )
        .toList();
    Map<String, dynamic> dot(String handle) =>
        c.node.bots.firstWhere((b) => b['handle'] == handle);

    Future<int> send(String id, String text) async {
      await open(id);
      final mark = head(id);
      final composer = tester.state<ChatComposerState>(
        find.byType(ChatComposer),
      );
      composer.editDraft(text);
      await run(const Duration(milliseconds: 200));
      unawaited(composer.send());
      await until(
        () => all(id).any((m) => m.seq > mark && m.author.type == 'user'),
        'sent: ${text.substring(0, 12)}',
        seconds: 45,
      );
      return mark;
    }

    final xiaoyan = dot('xiaoyan'), bibi = dot('bibi');

    // 1. A relay: each Dot works with its own tools, in its own session.
    final relay = await send(
      group,
      '@xiaoyan 请用 Python 实际计算 19*23，只回结果并带上 RELAY_A_$stamp，'
      '然后 @bibi 请他用一句话总结这个数字，回复里带上 RELAY_B_$stamp。',
    );
    // The first Dot's hand-off repeats the marker, so a turn is matched by its Dot.
    bool fromA(ChatMessage m) =>
        m.author.id == xiaoyan['botId'] &&
        '${m.content['text']}'.contains('RELAY_A_$stamp');
    bool fromB(ChatMessage m) =>
        m.author.id == bibi['botId'] &&
        '${m.content['text']}'.contains('RELAY_B_$stamp');
    await until(
      () => botTexts(group, relay).any(fromB),
      'the relay reached the second Dot',
      seconds: 420,
    );
    await until(() => state(group) == 'idle', 'the relay ended');
    final relayed = all(group).where((m) => m.seq > relay).toList();
    final first = botTexts(group, relay).firstWhere(fromA);
    final second = botTexts(group, relay).firstWhere(fromB);
    expect(first.author.id, xiaoyan['botId']);
    expect('${first.content['text']}', contains('437'));
    expect(second.author.id, bibi['botId']);
    expect(
      relayed.any((m) => m.kind == 'tool' && m.author.id == xiaoyan['botId']),
      isTrue,
      reason: 'the first Dot used its own tool in the group',
    );
    expect(relayed.where((m) => m.taskRole != null), isEmpty);
    await shot('group-relay');
    await tester.tap(key('chat-flowchart'));
    await shot('group-flow', settle: 1500);
    await tester.tap(key('flow-close'));
    await run(const Duration(milliseconds: 600));

    // 2. A message while a Dot works in the group interrupts it; the relay ends.
    final long = await send(group, '@xiaoyan 请用前台代码等 90 秒，然后 @bibi 请他写一句天气总结。');
    await until(
      () => state(group) == 'tool' || state(group) == 'thinking',
      'the first Dot is working',
      seconds: 120,
    );
    await run(const Duration(seconds: 15));
    await shot('group-working');
    final interrupt = await send(
      group,
      '先停下等待，直接告诉我 2 加 3 等于几，回复带上 GROUP_INT_$stamp。',
    );
    await until(
      () => botTexts(
        group,
        interrupt,
      ).any((m) => '${m.content['text']}'.contains('GROUP_INT_$stamp')),
      'the working Dot answered the new message',
      seconds: 300,
    );
    await until(() => state(group) == 'idle', 'the interrupted relay ended');
    await run(const Duration(seconds: 20));
    expect(
      botTexts(group, long).where((m) => m.author.id == bibi['botId']),
      isEmpty,
      reason: 'the relay ended with the interrupted turn',
    );
    await shot('group-interrupted');

    // 3. In private, the Dot remembers what it did in the group: its group turns
    // ran in this same session.
    final private = await send(
      dm,
      '你刚才在周报小组里算的 19*23 等于多少？回复带上 PRIVATE_$stamp。',
    );
    await until(
      () => botTexts(dm, private).any(
        (m) =>
            '${m.content['text']}'.contains('PRIVATE_$stamp') &&
            '${m.content['text']}'.contains('437'),
      ),
      'the Dot remembers its group work in private',
      seconds: 240,
    );
    await shot('private-remembers');

    // 4. A one-shot scheduled task: its result is the Dot's own message.
    final cron = await send(
      routineDm,
      '请读取 nekodot-routines skill，通过原生 cronjob_manage 创建名为 CRON_$stamp 的一次性任务'
      '（约一分钟后运行一次，local 投递）。任务内容：用 Python 计算 37 乘 41，只输出 CRON_$stamp 和结果。'
      '审批策略：自动允许，时区 Asia/Shanghai，无时间窗口。创建后结束本轮，不要自己先算。',
    );
    await until(() => state(routineDm) == 'idle', 'the task was created');
    await until(
      () => all(routineDm).any(
        (m) =>
            m.seq > cron &&
            m.messageId.startsWith('routine-result:') &&
            m.status == 'done' &&
            '${m.content['text']}'.contains('1517'),
      ),
      'the scheduled result arrived in the chat',
      seconds: 420,
    );
    final result = all(routineDm)
        .firstWhere((m) => m.messageId.startsWith('routine-result:'));
    expect(result.taskRole, isNull);
    await run(const Duration(seconds: 20));
    expect(
      botTexts(routineDm, result.seq),
      isEmpty,
      reason: 'the result is not retold',
    );
    final ask = await send(routineDm, '刚才那个定时任务算出的结果是多少？回复带上 ASK_$stamp。');
    await until(
      () => botTexts(routineDm, ask).any(
        (m) =>
            '${m.content['text']}'.contains('ASK_$stamp') &&
            '${m.content['text']}'.contains('1517'),
      ),
      'the Dot knows its scheduled result',
      seconds: 240,
    );
    await shot('routine-result');
    expect(
      [group, dm, routineDm].expand(all).where((m) => m.taskRole != null),
      isEmpty,
    );
    // ignore: avoid_print
    print('GROUP_QA thoughts ${thoughts.length} ${thoughts.take(6)}');
  }, timeout: const Timeout(Duration(minutes: 60)));
}
