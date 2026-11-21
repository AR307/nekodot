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
import 'package:nekodot_native/features/chat.dart';
import 'package:nekodot_native/features/chat_composer.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// A Dot's background job, rendered as its card in the real Windows client.
/// On the dot-qa stack (a real Relay, Node, Hermes and model) a new Dot is
/// asked to collect data with a script in the background. The tour shoots the
/// card while the job runs, at phone width and in dark mode too, once it is
/// done, while a second job is stopped from its card, and when a third fails.
/// Defines: RELAY_URL, QA_TOKEN, QA_NODE, TOUR_OUT.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('a Dot’s background job as its card', (tester) async {
    final c = NekodotClient();
    c.account.token = const String.fromEnvironment('QA_TOKEN');
    c.prefs.language = 'zh';
    await tester.runAsync(() async {
      await c.bootstrap();
      await c.selectNode(const String.fromEnvironment('QA_NODE'));
      while (c.node.bots.isEmpty || !c.online) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    final out = Directory(const String.fromEnvironment('TOUR_OUT'));
    await tester.runAsync(() => out.create(recursive: true));
    final notes = <String, Object?>{};

    Future<void> run(Duration time) async {
      final end = DateTime.now().add(time);
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 40));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
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
      // ignore: avoid_print
      print('TOUR $name.png');
    }

    var phone = false, dark = false;
    Widget app() => MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorObservers: [nativeRoutes],
      theme: appTheme(Brightness.light, glass: phone),
      darkTheme: appTheme(Brightness.dark, glass: phone),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) =>
          phone ? Ambient(child: child!) : WindowChrome(child: child!),
      home: HomePage(client: c),
    );
    Finder key(String name) => find.byKey(ValueKey(name));

    // A Dot of its own, so its chat shows only this.
    final model = c.node.bots.firstWhere((bot) => bot['archived'] != true);
    final created = await tester.runAsync(
      () => c.rpc('bots.create', {
        'displayName': '采集员',
        'handle': 'caiji${DateTime.now().millisecondsSinceEpoch % 100000}',
        'role': '负责用脚本采集和整理数据。回答简洁。',
        'model': model['model'],
        'sourceId': model['sourceId'],
        'avatar': {'shape': 'dot', 'color': '#2F9E8F'},
        'approvalMode': 'off',
      }),
    );
    final id = '${created!['conversation']['conversationId']}';
    c.workspace['conversation:${c.selectedNodeId}'] = id;

    List<ChatMessage> all() => c.node.messages[id] ?? const [];
    List<ChatMessage> jobs() => all().where((m) => m.kind == 'job').toList();
    String state() => c.node.activities[id]?.state ?? 'idle';
    int head() => all().fold(0, (seq, m) => m.seq > seq ? m.seq : seq);
    Json job(int index) => object(jobs()[index].content);
    bool replied(int mark) => all().any(
      (m) =>
          m.seq > mark &&
          m.author.type == 'bot' &&
          m.kind == 'text' &&
          m.status != 'streaming' &&
          '${m.content['text'] ?? ''}'.trim().isNotEmpty,
    );

    Future<void> open() async {
      final shown = find.byWidgetPredicate(
        (w) => w is ChatPage && w.conversationId == id,
      );
      for (var i = 0; i < 10; i++) {
        if (shown.evaluate().isNotEmpty &&
            key('chat-input').hitTestable().evaluate().isNotEmpty) {
          return;
        }
        if (key('home-section-recent').evaluate().isNotEmpty) {
          await tester.tap(key('home-section-recent'));
          await run(const Duration(milliseconds: 500));
        }
        final row = key('conversation-$id').hitTestable();
        if (row.evaluate().isNotEmpty) await tester.tap(row.first);
        await run(const Duration(milliseconds: 1200));
      }
    }

    /// The end of the chat, where the newest card is.
    Future<void> latest() async {
      final button = key('chat-latest').hitTestable();
      if (button.evaluate().isNotEmpty) {
        await tester.tap(button.first);
        await run(const Duration(milliseconds: 800));
      }
    }

    Future<void> desktop() async {
      await tester.pumpWidget(const SizedBox.shrink());
      phone = false;
      tester.view.physicalSize = const Size(2560, 1600);
      tester.view.devicePixelRatio = 2;
      tester.view.resetPadding();
      await tester.pumpWidget(app());
      await run(const Duration(milliseconds: 800));
      await open();
      await latest();
    }

    /// Sends [text] the way Enter does, set on the composer itself.
    Future<int> send(String text) async {
      final composer = tester.state<ChatComposerState>(
        find.byType(ChatComposer),
      );
      final mark = head();
      composer.editDraft(text);
      await run(const Duration(milliseconds: 200));
      unawaited(composer.send());
      expect(
        await until(
          () => all().any((m) => m.seq > mark && m.author.type == 'user'),
          seconds: 45,
        ),
        isTrue,
        reason: 'Not sent: $text',
      );
      return mark;
    }

    await desktop();
    // The Dot introduces itself first.
    await until(() => replied(0) && state() == 'idle', seconds: 180);

    // ---------- a job that runs to the end ----------
    var mark = await send(
      '用 Python 写个脚本，模拟采集 120 个商品页面：每页等 0.5 秒，用 tqdm 显示进度，'
      '描述写「采集商品页」，没装 tqdm 就先装上。放到后台运行，跑完告诉我结果。',
    );
    notes['firstCard'] = await until(() => jobs().isNotEmpty, seconds: 420);
    expect(notes['firstCard'], isTrue, reason: 'No job card appeared');
    await until(() => ((job(0)['percent'] as num?) ?? 0) >= 25, seconds: 120);
    await latest();
    await shot('1-running');
    notes['running'] = job(0);

    await tester.pumpWidget(const SizedBox.shrink());
    phone = true;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 108, bottom: 72);
    await tester.pumpWidget(app());
    await run(const Duration(milliseconds: 800));
    await open();
    await latest();
    await shot('2-running-phone');

    dark = true;
    await desktop();
    await shot('3-running-dark');
    dark = false;
    await desktop();

    notes['done'] = await until(
      () => job(0)['state'] != 'running',
      seconds: 300,
    );
    await until(() => replied(mark) && state() == 'idle', seconds: 300);
    await latest();
    await shot('4-done', settle: 1500);
    notes['ended'] = job(0);
    notes['firstReplies'] = [
      for (final m in all().where(
        (m) => m.seq > mark && m.author.type == 'bot' && m.kind == 'text',
      ))
        '${m.content['text']}',
    ];

    // ---------- a job stopped from its card ----------
    mark = await send('再跑一个一样的脚本，这次采集 2000 条评论，描述写「采集评论」，同样放到后台。');
    notes['secondCard'] = await until(
      () => jobs().length >= 2 && ((job(1)['percent'] as num?) ?? 0) >= 2,
      seconds: 420,
    );
    expect(notes['secondCard'], isTrue, reason: 'No second job card');
    await until(() => state() == 'idle', seconds: 120);
    await latest();
    final stop = key('job-stop-${jobs()[1].messageId}');
    await tester.tap(stop);
    await run(const Duration(milliseconds: 400));
    await shot('5-confirm-stop', settle: 300);
    await tester.tap(stop);
    notes['stopped'] = await until(
      () => job(1)['state'] == 'stopped',
      seconds: 60,
    );
    await until(() => state() == 'idle', seconds: 180);
    await latest();
    await shot('6-stopped', settle: 1500);
    notes['stoppedCard'] = job(1);

    // ---------- a job that fails ----------
    mark = await send(
      '再写一个脚本：模拟采集 80 条库存，每条 0.3 秒，进度格式同上，描述写「采集库存」；'
      '到第 30 条时模拟网络错误，以退出码 1 结束。放到后台运行。',
    );
    notes['thirdCard'] = await until(
      () => jobs().length >= 3 && job(2)['state'] == 'failed',
      seconds: 420,
    );
    await until(() => replied(mark) && state() == 'idle', seconds: 300);
    await latest();
    await shot('7-failed', settle: 1500);
    if (jobs().length >= 3) notes['failedCard'] = job(2);

    tester.view.reset();
    await tester.pumpWidget(const SizedBox.shrink());
    // ignore: avoid_print
    print('TOUR ${jsonEncode(notes)}');
  }, timeout: const Timeout(Duration(minutes: 60)));
}
