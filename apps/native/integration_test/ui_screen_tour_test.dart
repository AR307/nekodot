import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/auth.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// Walks the screen, search and sign-in against a running Relay with a real
/// Node and Hermes, and writes a PNG of each step: the screen as a small
/// window over a conversation and then beside it, the search panel, and the
/// sign-in page; then the same on a phone.
/// Defines: RELAY_URL, QA_TOKEN, QA_NODE, QA_CONVERSATION, QA_GROUP, TOUR_OUT.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('screen tour', (tester) async {
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
    final out = Directory('$shell/../screen');
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

    Widget app([Widget? home]) => ValueListenableBuilder(
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
        home: home ?? HomePage(client: client),
      ),
    );

    final notes = <String, Object?>{};
    const dm = String.fromEnvironment('QA_CONVERSATION');
    final asking = client.node.conversations.firstWhere(
      (c) => c['kind'] != 'group' && c['conversationId'] != dm,
    );
    final talk = '${asking['conversationId']}';
    Finder key(String name) => find.byKey(ValueKey(name));
    Future<void> dark(String name) async {
      mode.value = ThemeMode.dark;
      await shot(name);
      mode.value = ThemeMode.light;
      await run(const Duration(milliseconds: 300));
    }

    // ---------- desktop ----------
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2;
    client.workspace.remove('category:${client.selectedNodeId}');
    client.workspace.remove('details:${client.selectedNodeId}');
    await tester.pumpWidget(app());
    await run(const Duration(milliseconds: 600));
    await tester.tap(key('conversation-$talk'));
    await run(const Duration(milliseconds: 900));

    // The screen: a small window first, then room beside the conversation.
    await tester.tap(find.byTooltip('屏幕'));
    await shot('desk-light-screen-window', settle: 3500);
    notes['take'] = key('screen-take').evaluate().isNotEmpty;
    await dark('desk-dark-screen-window');
    await tester.tap(key('screen-wide'));
    await shot('desk-light-screen-beside', settle: 2500);
    await dark('desk-dark-screen-beside');
    await tester.tap(find.byTooltip('关闭屏幕'));
    await shot('desk-light-screen-closed', settle: 700);

    // Search is simply there, with what was typed narrowing it.
    await tester.tap(find.byTooltip('搜索 (Ctrl+K)'));
    await shot('desk-light-search', settle: 500);
    final query = key('search-palette-input');
    tester.widget<TextField>(query).controller!.text = 'qa w';
    await shot('desk-light-search-typed', settle: 500);
    await dark('desk-dark-search-typed');
    navigator.currentState!.pop();
    await run(const Duration(milliseconds: 400));

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
    await tester.tap(key('conversation-$talk'));
    await run(const Duration(milliseconds: 1200));
    await tester.tap(find.byTooltip('屏幕'));
    await shot('phone-light-screen-window', settle: 3500);
    await tester.tap(key('screen-wide'));
    await shot('phone-light-screen-above', settle: 2500);
    await dark('phone-dark-screen-above');
    await tester.tap(find.byTooltip('关闭屏幕'));
    await run(const Duration(milliseconds: 600));
    navigator.currentState!.pop();
    await run(const Duration(milliseconds: 600));
    await tester.tap(find.byTooltip('搜索'));
    await run(const Duration(milliseconds: 400));
    await shot('phone-light-search', settle: 500);

    // ---------- sign-in, with an account that is not signed in ----------
    final visitor = NekodotClient();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app(AuthPage(client: visitor)));
    await shot('phone-light-sign-in', settle: 1500);
    await tester.pumpWidget(const SizedBox.shrink());
    glass = false;
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2;
    tester.view.padding = FakeViewPadding.zero;
    await tester.pumpWidget(app(AuthPage(client: visitor)));
    await shot('desk-light-sign-in', settle: 1500);
    await dark('desk-dark-sign-in');
    await tester.pumpWidget(const SizedBox.shrink());
    visitor.dispose();

    tester.view.reset();
    client.dispose();
    // ignore: avoid_print
    print('TOUR ${jsonEncode({'done': true, ...notes})}');
  }, timeout: const Timeout(Duration(minutes: 12)));
}
