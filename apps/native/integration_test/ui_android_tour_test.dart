import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/ui/design.dart';

/// Walks the redesigned client on an Android device at its own size, against
/// a running Relay with a real Node and Hermes, and writes a PNG of each
/// step into the app's cache folder (`ui-037-tour`), to be pulled with adb:
/// the home sections, a conversation with its steps folded under it, the
/// Bot's details and the account as sheets, settings, and a new Bot.
/// Defines: RELAY_URL, QA_TOKEN, QA_NODE, QA_CONVERSATION.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('android tour', (tester) async {
    final client = NekodotClient();
    final navigator = GlobalKey<NavigatorState>();
    final mode = ValueNotifier(ThemeMode.light);
    client.account.token = const String.fromEnvironment('QA_TOKEN');
    await tester.runAsync(() async {
      await client.bootstrap();
      await client.selectNode(const String.fromEnvironment('QA_NODE'));
      while (client.node.conversations.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    final out = Directory('${Directory.systemTemp.path}/ui-037-tour');
    await tester.runAsync(() async {
      if (await out.exists()) await out.delete(recursive: true);
      await out.create(recursive: true);
    });

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
      print('TOUR $name.png');
    }

    final notes = <String, Object?>{
      'size': '${tester.view.physicalSize}',
      'ratio': tester.view.devicePixelRatio,
      'android': Platform.isAndroid,
      'out': out.path,
    };
    const dm = String.fromEnvironment('QA_CONVERSATION');
    final asking = client.node.conversations.firstWhere(
      (c) => c['kind'] != 'group' && c['conversationId'] != dm,
    );
    final talk = '${asking['conversationId']}';
    Finder key(String name) => find.byKey(ValueKey(name));
    Finder section(String id) => key('home-section-$id');
    Future<void> dark(String name) async {
      mode.value = ThemeMode.dark;
      await shot(name);
      mode.value = ThemeMode.light;
      await run(const Duration(milliseconds: 300));
    }

    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: mode,
        builder: (context, value, _) => MaterialApp(
          navigatorKey: navigator,
          debugShowCheckedModeBanner: false,
          navigatorObservers: [nativeRoutes],
          theme: appTheme(Brightness.light, glass: true),
          darkTheme: appTheme(Brightness.dark, glass: true),
          themeMode: value,
          builder: (context, child) => Ambient(child: child!),
          home: HomePage(client: client),
        ),
      ),
    );
    await run(const Duration(milliseconds: 800));
    navigator.currentState!.popUntil((route) => route.isFirst);
    await run(const Duration(milliseconds: 500));

    // Home: the list, its sections, the gallery.
    await tester.tap(section('recent'));
    await shot('home-recent');
    await dark('home-recent-dark');
    await tester.tap(section('dot'));
    await shot('home-dot');
    await tester.tap(section('group'));
    await shot('home-groups');
    await tester.tap(section('space'));
    await shot('home-spaces', settle: 1200);
    await tester.tap(section('recent'));
    await run(const Duration(milliseconds: 500));

    // A conversation: bubbles, composer, the steps folded under it.
    await tester.tap(key('conversation-$talk'));
    await run(const Duration(milliseconds: 1500));
    if (key('chat-latest').evaluate().isNotEmpty) {
      await tester.tap(key('chat-latest'));
    }
    await shot('chat', settle: 1200);
    await dark('chat-dark');
    final fold = key('flow-fold-toggle');
    notes['fold'] = fold.evaluate().isNotEmpty;
    if (fold.evaluate().isNotEmpty) {
      await tester.tap(fold);
      await shot('chat-flow-open', settle: 1500);
      await tester.tap(fold);
      await run(const Duration(milliseconds: 600));
    }
    await tester.tap(find.byTooltip('屏幕'));
    await shot('chat-screen-window', settle: 3000);
    await tester.tap(key('screen-wide'));
    await shot('chat-screen-above', settle: 2000);
    await tester.tap(find.byTooltip('关闭屏幕'));
    await run(const Duration(milliseconds: 600));
    await tester.tap(find.byTooltip('详情'));
    await shot('details-sheet', settle: 2500);
    await dark('details-sheet-dark');
    navigator.currentState!.pop();
    await run(const Duration(milliseconds: 600));
    navigator.currentState!.pop();
    await run(const Duration(milliseconds: 600));

    // The account, settings, and making a Bot.
    await tester.tap(find.byTooltip('账户'));
    await shot('account-sheet', settle: 900);
    await tester.tap(key('account-settings'));
    await shot('settings', settle: 1200);
    navigator.currentState!.pop();
    await run(const Duration(milliseconds: 600));
    await tester.tap(find.byTooltip('新建'));
    await shot('create-menu', settle: 700);
    await tester.tap(find.text('新建 Bot').last);
    await shot('new-bot', settle: 2000);
    navigator.currentState!.pop();
    await run(const Duration(milliseconds: 600));

    client.dispose();
    // ignore: avoid_print
    print('TOUR ${jsonEncode({'done': true, ...notes})}');
  }, timeout: const Timeout(Duration(minutes: 12)));
}
