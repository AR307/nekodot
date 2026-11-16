import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
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

/// Acceptance of one Dot working with its own tools: the real client sends the
/// first round of the Grok Bot probe (docs/research/grok-bot-probe/步骤.md) in
/// one private chat on a running Relay with a real Node, Hermes and model. It
/// types each message and drops each archive into the composer as a person
/// would, and records every reply, how long each took, how many tool steps it
/// used, and each line of thought the status showed. What the replies mean is
/// read from report.json afterwards; the test fails only if a step gets no
/// reply. The language is set for this run only and never saved.
/// Defines: RELAY_URL, QA_TOKEN, QA_NODE, QA_CONVERSATION, PROBE_DIR (the
/// round's archives), PASTE_FILE (the text pasted to time a plain reply),
/// TOUR_OUT.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('one Dot answers the probe with its own tools', (tester) async {
    final c = NekodotClient();
    c.account.token = const String.fromEnvironment('QA_TOKEN');
    c.prefs.language = 'zh';
    const id = String.fromEnvironment('QA_CONVERSATION');
    const probe = String.fromEnvironment('PROBE_DIR');
    await tester.runAsync(() async {
      await c.bootstrap();
      await c.selectNode(const String.fromEnvironment('QA_NODE'));
      while (c.node.conversations.isEmpty || !c.online) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    final out = Directory(const String.fromEnvironment('TOUR_OUT'));
    await tester.runAsync(() => out.create(recursive: true));
    final paste = await tester.runAsync(
      () => File(const String.fromEnvironment('PASTE_FILE')).readAsString(),
    );

    // Every line of thought the status showed, in order, per step.
    var thoughts = <String>[];
    void watch() {
      final thought = c.node.activities[id]?.thought;
      if (thought != null && (thoughts.isEmpty || thoughts.last != thought)) {
        thoughts.add(thought);
      }
    }

    Future<void> run(Duration time) async {
      final end = DateTime.now().add(time);
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 40));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        watch();
      }
    }

    Future<bool> until(bool Function() test, {int seconds = 120}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!test() && DateTime.now().isBefore(end)) {
        await run(const Duration(milliseconds: 400));
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
    }

    var phone = false;
    Widget app() => MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorObservers: [nativeRoutes],
      theme: appTheme(Brightness.light, glass: phone),
      darkTheme: appTheme(Brightness.dark, glass: phone),
      themeMode: ThemeMode.light,
      builder: (context, child) =>
          phone ? Ambient(child: child!) : WindowChrome(child: child!),
      home: HomePage(client: c),
    );
    Finder key(String name) => find.byKey(ValueKey(name));
    // The app comes back with the chat that was open last; start in this one.
    c.workspace['conversation:${c.selectedNodeId}'] = id;
    Future<void> open() async {
      final shown = find.byWidgetPredicate(
        (w) => w is ChatPage && w.conversationId == id,
      );
      if (shown.evaluate().isNotEmpty &&
          key('chat-input').hitTestable().evaluate().isNotEmpty) {
        return;
      }
      if (key('home-section-recent').evaluate().isNotEmpty) {
        await tester.tap(key('home-section-recent'));
        await run(const Duration(milliseconds: 500));
      }
      await tester.tap(key('conversation-$id').hitTestable().first);
      await run(const Duration(milliseconds: 1500));
    }

    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(app());
    await run(const Duration(milliseconds: 800));
    await open();

    List<ChatMessage> all() => c.node.messages[id] ?? const [];
    int head() => all().fold(0, (seq, m) => m.seq > seq ? m.seq : seq);
    String state() => c.node.activities[id]?.state ?? 'idle';
    List<ChatMessage> repliesAfter(int seq) => all()
        .where(
          (m) =>
              m.seq > seq &&
              m.author.type == 'bot' &&
              (m.kind == 'text' || m.kind == 'commentary') &&
              '${m.content['text'] ?? ''}'.trim().isNotEmpty,
        )
        .toList();
    int toolsAfter(int seq) =>
        all().where((m) => m.seq > seq && m.kind == 'tool').length;
    bool settled(int seq) =>
        state() == 'idle' &&
        repliesAfter(seq).isNotEmpty &&
        repliesAfter(seq).every((m) => m.status != 'streaming');

    final report = <Map<String, Object?>>[];
    final steps = <String, ({int seq, DateTime at})>{};

    /// Writes [text] into the composer (with [file] dropped in first) and
    /// sends it the way Enter does. The text is set on the composer itself:
    /// on a real Windows window the system input method can overwrite text a
    /// test types, which is not what this journey checks.
    Future<void> send(String name, String text, {String? file}) async {
      final composer = tester.state<ChatComposerState>(
        find.byType(ChatComposer),
      );
      if (file != null) {
        await tester.runAsync(
          () => composer.attachDroppedFiles([DropItemFile('$probe/$file')]),
        );
        await until(
          () => (c.attachmentDrafts.values.expand((x) => x)).isNotEmpty,
          seconds: 60,
        );
        await run(const Duration(milliseconds: 300));
      }
      thoughts = [];
      final mark = head();
      bool sent() => all().any((m) => m.seq > mark && m.author.type == 'user');
      composer.editDraft(text);
      await run(const Duration(milliseconds: 200));
      unawaited(composer.send());
      steps[name] = (seq: mark, at: DateTime.now());
      if (!await until(sent, seconds: 45)) {
        await shot('unsent-$name');
        final failed = c.deliveries.items
            .where((item) => item['state'] == 'failed')
            .map((item) => item['error']);
        fail('$name was not sent: ${failed.join('; ')}');
      }
      await run(const Duration(milliseconds: 400));
    }

    /// Records what came back since [name] was sent.
    Map<String, Object?> record(String name, {String? note}) {
      final step = steps[name]!;
      final replies = repliesAfter(step.seq);
      final entry = <String, Object?>{
        'step': name,
        'seconds': DateTime.now().difference(step.at).inMilliseconds / 1000,
        'tools': toolsAfter(step.seq),
        'replies': [for (final m in replies) '${m.content['text']}'],
        'thoughts': List.of(thoughts),
        'note': ?note,
      };
      report.add(entry);
      // Kept after every step, so a later failure leaves what was measured.
      File(
        '${out.path}/report.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
      // ignore: avoid_print
      print('PROBE $name ${entry['seconds']}s tools=${entry['tools']}');
      return entry;
    }

    Future<Map<String, Object?>> ask(
      String name,
      String text, {
      String? file,
      int seconds = 300,
      bool Function(String reply)? done,
    }) async {
      await send(name, text, file: file);
      final mark = steps[name]!.seq;
      final finished = await until(
        () =>
            settled(mark) &&
            (done == null ||
                repliesAfter(mark).any((m) => done('${m.content['text']}'))),
        seconds: seconds,
      );
      return record(name, note: finished ? null : 'timed out');
    }

    // 1. Something a tool answers, in the same turn.
    await ask('home', '你电脑的 home 目录下有几个文件？');
    await ask('home-second', '第二个叫什么？');

    // 3. A detail said in passing, then small talk, then a task that needs it.
    await ask('receipt', '刚才在便利店买水，小票上印着一串字：青柠-4207，随口一说。');
    for (final (i, talk) in [
      '你觉得早上喝茶好还是喝咖啡好？',
      '用一句话形容秋天。',
      '猫为什么喜欢钻纸箱？',
      '给我讲个冷笑话。',
      '下雨天适合做什么？',
    ].indexed) {
      await ask('talk-${i + 1}', talk);
    }
    await send(
      'task',
      '附件是我自己打包的，解压后照 r1-task.txt 做，做完告诉我。',
      file: 'r1-task.zip',
    );
    await run(const Duration(seconds: 20));
    await shot('task-working');
    await tester.tap(key('chat-flowchart'));
    await shot('task-flow-panel', settle: 1500);
    await tester.tap(key('flow-close'));
    await run(const Duration(seconds: 40));
    final taskThoughts = List.of(thoughts);
    await send('task-progress', '做到哪了？');
    await until(
      () => repliesAfter(steps['task-progress']!.seq).isNotEmpty,
      seconds: 180,
    );
    record('task-progress');
    await shot('task-progress');
    thoughts = taskThoughts;
    await until(
      () =>
          settled(steps['task']!.seq) &&
          repliesAfter(steps['task']!.seq)
              .any((m) => '${m.content['text']}'.contains('24527')),
      seconds: 600,
    );
    record('task');

    // 4. Is the work's process in the conversation afterwards?
    await ask(
      'sum',
      '附件是我自己打包的。解压后先在终端执行 sleep 120，再算 r1-sum.txt 第二列的总和，只回我一个数字。',
      file: 'r1-sum.zip',
      seconds: 600,
      done: (reply) => reply.contains('22952'),
    );
    await ask('sum-checksum', '那个 r1-sum.txt 里备注的校验码是什么？');

    // 5. Is the reply written once? Short, long, and a plain paste to time.
    await ask(
      'essay-lines',
      '附件是我自己打包的。解压后读 r1-essay.txt，只回我它一共多少行。',
      file: 'r1-essay.zip',
    );
    await ask('essay-full', '把 r1-essay.txt 的全文原样贴给我，一个字都不要改。');
    await ask('paste', paste!);

    // 6. A long script, and a question while it runs.
    await send(
      'script',
      '附件是我自己打包的。解压后执行里面的 r1-run.sh，把输出告诉我。',
      file: 'r1-run.zip',
    );
    await until(() => state() == 'tool', seconds: 60);
    await run(const Duration(seconds: 15));
    await shot('script-running');
    final scriptThoughts = List.of(thoughts);
    await send('script-question', '1+1 等于几？');
    await until(
      () =>
          repliesAfter(steps['script-question']!.seq)
              .any((m) => '${m.content['text']}'.contains('2')),
      seconds: 240,
    );
    record('script-question');
    await shot('script-question');
    thoughts = scriptThoughts;
    await until(
      () =>
          settled(steps['script']!.seq) &&
          repliesAfter(
            steps['script']!.seq,
          ).any((m) => '${m.content['text']}'.toLowerCase().contains('done')),
      seconds: 420,
    );
    record('script');
    await shot('chat-end');

    // On a phone the Flow is a page of its own.
    await tester.pumpWidget(const SizedBox.shrink());
    phone = true;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 108, bottom: 72);
    await tester.pumpWidget(app());
    await run(const Duration(milliseconds: 800));
    await open();
    await shot('phone-chat');
    await tester.tap(key('chat-flowchart'));
    await shot('phone-flow-page', settle: 1500);

    expect(
      report.where((r) => (r['replies'] as List).isEmpty).map((r) => r['step']),
      isEmpty,
    );
  }, timeout: const Timeout(Duration(minutes: 90)));
}
