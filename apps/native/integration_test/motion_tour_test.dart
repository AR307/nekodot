import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/chat.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// Drives the moving parts against a running Relay and writes frames of them:
/// a sent message entering, the jump-to-latest button while reading further
/// up, the search panel, notices and the phone's floating header. Defines:
/// RELAY_URL, QA_TOKEN, QA_NODE, QA_DM, TOUR_OUT.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('motion tour', (tester) async {
    final client = NekodotClient();
    final navigator = GlobalKey<NavigatorState>();
    var glass = false;
    client.account.token = const String.fromEnvironment('QA_TOKEN');
    await tester.runAsync(() async {
      await client.bootstrap();
      await client.selectNode(const String.fromEnvironment('QA_NODE'));
      while (client.node.conversations.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    final out = Directory(const String.fromEnvironment('TOUR_OUT'));
    await tester.runAsync(() => out.create(recursive: true));

    Future<void> run(Duration time) async {
      final end = DateTime.now().add(time);
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 16)),
        );
      }
    }

    Future<void> until(bool Function() done, String what) async {
      final end = DateTime.now().add(const Duration(seconds: 40));
      while (!done()) {
        if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
        await run(const Duration(milliseconds: 50));
      }
    }

    /// The frame on screen now, without letting anything settle first.
    Future<void> capture(String name) async {
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
      print('MOTION ${out.path}/$name.png');
    }

    Widget app(Widget home) => MaterialApp(
      navigatorKey: navigator,
      debugShowCheckedModeBanner: false,
      navigatorObservers: [nativeRoutes],
      theme: appTheme(Brightness.light, glass: glass),
      themeMode: ThemeMode.light,
      builder: (context, child) =>
          glass ? Ambient(child: child!) : WindowChrome(child: child!),
      home: home,
    );

    const dmBot = String.fromEnvironment('QA_DM');
    final dm =
        client.node.conversations
                .where((x) => x['botId'] == dmBot)
                .first['conversationId']
            as String;
    int sent() => (client.node.messages[dm] ?? [])
        .where((m) => m.author.type == 'user')
        .length;
    bool idle() {
      final state = client.node.activities[dm]?.state;
      return state == null || state == 'idle';
    }

    Future<void> send(String text) async {
      final before = sent();
      await tester.enterText(find.byKey(const ValueKey('chat-input')), text);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await until(() => sent() > before, 'the sent message');
    }

    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2;
    await tester.pumpWidget(app(HomePage(client: client)));
    await run(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(ValueKey('conversation-$dm')));
    await run(const Duration(milliseconds: 900));
    await capture('desk-dm-open');

    // A sent message enters from the composer.
    await send('把三篇的标题再列一下');
    // It is still entering when it first shows.
    expect(
      find.descendant(
        of: find.byType(EntryMotion),
        matching: find.byType(Opacity),
      ),
      findsWidgets,
    );
    await run(const Duration(milliseconds: 50));
    await capture('desk-send-50ms');
    await run(const Duration(milliseconds: 90));
    await capture('desk-send-140ms');
    await run(const Duration(milliseconds: 400));
    await capture('desk-send-done');
    await until(idle, 'the reply');
    await run(const Duration(milliseconds: 600));
    await capture('desk-replied');
    for (final text in ['再补一句为什么选这三篇', '顺便给个阅读顺序']) {
      await send(text);
      await until(idle, 'the reply');
    }
    await run(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('chat-latest')), findsOneWidget);

    // Reading further up brings out the button; a reply meanwhile marks it.
    await tester.drag(
      find.byKey(const ValueKey('chat-messages')),
      const Offset(0, 420),
    );
    await run(const Duration(milliseconds: 500));
    await capture('desk-reading-up');
    await tester.runAsync(() => client.send(dm, '还有别的推荐吗'));
    await until(idle, 'the reply while reading up');
    await run(const Duration(milliseconds: 500));
    await capture('desk-reading-up-missed');
    await tester.tap(find.byKey(const ValueKey('chat-latest')));
    await run(const Duration(milliseconds: 600));
    await capture('desk-back-to-latest');

    // Ctrl+K finds a conversation and opens it.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await run(const Duration(milliseconds: 400));
    await capture('desk-search');
    await tester.enterText(
      find.byKey(const ValueKey('search-palette-input')),
      '笔',
    );
    await run(const Duration(milliseconds: 200));
    await capture('desk-search-typed');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await run(const Duration(milliseconds: 700));
    await capture('desk-search-opened');

    // A second notice replaces the first instead of queueing behind it.
    showNotice(navigator.currentContext!, '已复制');
    await run(const Duration(milliseconds: 120));
    showNotice(navigator.currentContext!, '10 个模型');
    await run(const Duration(milliseconds: 500));
    await capture('desk-notice');
    await run(const Duration(milliseconds: 2600));

    // The phone: floating back, title and actions over the messages.
    glass = true;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    tester.view.padding = const FakeViewPadding(
      top: 48 * 2.75,
      bottom: 24 * 2.75,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app(HomePage(client: client)));
    await run(const Duration(milliseconds: 600));
    await capture('phone-home');
    await tester.tap(find.byKey(ValueKey('conversation-$dm')));
    await run(const Duration(milliseconds: 900));
    await capture('phone-dm');
    await tester.drag(
      find.byKey(const ValueKey('chat-messages')),
      const Offset(0, 500),
    );
    await run(const Duration(milliseconds: 500));
    await capture('phone-dm-reading-up');
    expect(find.byType(ChatPage), findsOneWidget);
    tester.view.reset();
    client.dispose();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
