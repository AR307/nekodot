import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// Walks the home shell against a running Relay with a real Node, Hermes and
/// model, and writes a PNG of each step: the rail and its sections on a
/// desktop, the bar and bottom navigation on a phone, in both themes. One
/// real message is sent so the list shows a working Dot and then its reply.
/// Defines: RELAY_URL, QA_TOKEN, QA_NODE, QA_CONVERSATION, QA_GROUP, TOUR_OUT.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('home shell tour', (tester) async {
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
    final out = Directory(const String.fromEnvironment('TOUR_OUT'));
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

    const dm = String.fromEnvironment('QA_CONVERSATION');
    const room = String.fromEnvironment('QA_GROUP');
    Finder row(String id) => find.byKey(ValueKey('conversation-$id'));
    Finder section(String id) => find.byKey(ValueKey('home-section-$id'));

    // ---------- desktop ----------
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2;
    client.workspace.remove('category:${client.selectedNodeId}');
    await tester.pumpWidget(app());
    await shot('desk-light-recent-empty');
    await tester.tap(row(dm));
    await shot('desk-light-chat-open');
    // One real message: the row shows the working ring, then the reply.
    await tester.enterText(
      find.byKey(const ValueKey('chat-input')),
      '用一句话介绍你自己。',
    );
    await run(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('发送'));
    await shot('desk-light-working', settle: 1800);
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline) &&
        (client.node.activities[dm]?.state ?? 'idle') != 'idle') {
      await run(const Duration(milliseconds: 500));
    }
    await shot('desk-light-replied', settle: 1500);
    await tester.tap(row(room));
    await shot('desk-light-group');
    await tester.tap(section('dot'));
    await shot('desk-light-dot', settle: 150);
    await shot('desk-light-dot-settled');
    await tester.tap(section('group'));
    await shot('desk-light-groups');
    await tester.tap(section('space'));
    await shot('desk-light-spaces');
    await tester.tap(section('plugins'));
    await shot('desk-light-plugins', settle: 1500);
    await tester.tap(section('recent'));
    await shot('desk-light-recent');
    await tester.tap(find.byTooltip('账户'));
    await shot('desk-light-account-menu', settle: 600);
    navigator.currentState!.pop();
    await run(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('新建'));
    await shot('desk-light-create-menu', settle: 600);
    navigator.currentState!.pop();
    await run(const Duration(milliseconds: 300));
    mode.value = ThemeMode.dark;
    await shot('desk-dark-recent');
    await tester.tap(section('dot'));
    await shot('desk-dark-dot');
    await tester.tap(section('recent'));
    await run(const Duration(milliseconds: 400));

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
    await shot('phone-light-recent');
    await tester.tap(section('dot'));
    await shot('phone-light-dot');
    await tester.tap(section('group'));
    await shot('phone-light-groups');
    await tester.tap(section('space'));
    await shot('phone-light-spaces');
    await tester.tap(section('recent'));
    await run(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('新建'));
    await shot('phone-light-create-menu', settle: 600);
    navigator.currentState!.pop();
    await run(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('搜索'));
    await run(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const ValueKey('home-search')), 'qa w');
    await shot('phone-light-search');
    await tester.tap(find.byTooltip('清除'));
    await run(const Duration(milliseconds: 300));
    await tester.tap(row(dm));
    await shot('phone-light-chat');
    navigator.currentState!.pop();
    await run(const Duration(milliseconds: 500));
    mode.value = ThemeMode.dark;
    await shot('phone-dark-recent');

    tester.view.reset();
    client.dispose();
    // ignore: avoid_print
    print('TOUR ${jsonEncode({'done': true})}');
  }, timeout: const Timeout(Duration(minutes: 12)));
}
