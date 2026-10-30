import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/auth.dart';
import 'package:nekodot_native/features/bot_details.dart';
import 'package:nekodot_native/features/bot_editor.dart';
import 'package:nekodot_native/features/extensions.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/pairing.dart';
import 'package:nekodot_native/features/settings.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/screen/viewer.dart';
import 'package:nekodot_native/ui/design.dart';
import 'package:window_manager/window_manager.dart';

/// Walks the real screens against a running Relay and writes a PNG of each, at
/// phone and desktop size in both themes, for design review. Defines:
/// RELAY_URL, QA_TOKEN, QA_NODE, QA_DM, QA_GROUP, TOUR_OUT.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('design tour', (tester) async {
    final client = NekodotClient();
    final navigator = GlobalKey<NavigatorState>();
    final mode = ValueNotifier(ThemeMode.light);
    var glass = true;
    client.token = const String.fromEnvironment('QA_TOKEN');
    await tester.runAsync(() async {
      await client.bootstrap();
      await client.selectNode(const String.fromEnvironment('QA_NODE'));
      while (client.node.conversations.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    Future<Directory> output() async {
      if (const bool.hasEnvironment('TOUR_OUT')) {
        return Directory(const String.fromEnvironment('TOUR_OUT'));
      }
      return Directory.systemTemp;
    }

    final out = await tester.runAsync(output);
    await tester.runAsync(() => out!.create(recursive: true));

    Future<void> run(Duration time) async {
      final end = DateTime.now().add(time);
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 40));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
      }
    }

    Future<void> shot(String name) async {
      await run(const Duration(milliseconds: 900));
      final view = tester.binding.renderViews.first;
      final layer = view.debugLayer! as OffsetLayer;
      final size = tester.view.physicalSize;
      await tester.runAsync(() async {
        final ui.Image image = await layer.toImage(Offset.zero & size);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${out!.path}/$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      // ignore: avoid_print
      print('TOUR ${out!.path}/$name.png');
    }

    Future<void> open(Widget page, String name) async {
      pushPage(navigator.currentContext!, page);
      await shot(name);
      navigator.currentState!.pop();
      await run(const Duration(milliseconds: 400));
    }

    Widget app(Widget home) => ValueListenableBuilder(
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
        home: home,
      ),
    );

    final bot = client.node.bots
        .where((b) => b['botId'] == const String.fromEnvironment('QA_DM'))
        .first;
    final group = client.node.groups
        .where((g) => g['groupId'] == const String.fromEnvironment('QA_GROUP'))
        .first;
    Finder row(String id) => find.byKey(ValueKey('conversation-$id'));
    final dm = client.node.conversations
        .where((x) => x['botId'] == bot['botId'])
        .first['conversationId'];
    final room = client.node.conversations
        .where((x) => x['groupId'] == group['groupId'])
        .first['conversationId'];

    final android = Platform.isAndroid;
    for (final (label, size, ratio, inset) in [
      ('phone', const Size(1080, 2340), 2.75, const [48.0, 24.0]),
      if (!android) ('desk', const Size(2560, 1600), 2.0, const [0.0, 0.0]),
    ]) {
      glass = label == 'phone';
      // A phone keeps its own screen, so the real insets are in the picture.
      if (!android) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = ratio;
        tester.view.padding = FakeViewPadding(
          top: inset[0] * ratio,
          bottom: inset[1] * ratio,
        );
      }
      for (final theme in [ThemeMode.light, ThemeMode.dark]) {
        mode.value = theme;
        final tag = '$label-${theme.name}';
        await tester.pumpWidget(app(AuthPage(client: client)));
        await shot('$tag-auth');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(app(HomePage(client: client)));
        await shot('$tag-home');
        await tester.tap(find.byTooltip('新建'));
        await shot('$tag-menu');
        navigator.currentState!.pop();
        await run(const Duration(milliseconds: 300));
        await tester.tap(row('$dm'));
        await shot('$tag-dm');
        if (label == 'phone') {
          navigator.currentState!.pop();
          await run(const Duration(milliseconds: 400));
        }
        await tester.tap(row('$room'));
        await shot('$tag-group');
        if (label == 'phone') {
          navigator.currentState!.pop();
          await run(const Duration(milliseconds: 400));
        }
        if (label == 'desk') {
          await tester.tap(row('$dm'));
          await run(const Duration(milliseconds: 500));
          await tester.tap(find.byTooltip('详情'));
          await shot('$tag-panel');
          await tester.tap(find.byTooltip('Skills 与插件'));
          await shot('$tag-dialog');
          navigator.currentState!.pop();
          await run(const Duration(milliseconds: 300));
          await tester.tap(find.byTooltip('关闭'));
          await run(const Duration(milliseconds: 300));
        }
        await open(BotDetails(client: client, bot: bot), '$tag-details');
        pushPage(
          navigator.currentContext!,
          BotDetails(client: client, bot: bot),
        );
        await run(const Duration(milliseconds: 500));
        await tester.tap(find.text('记忆').first);
        await shot('$tag-memory');
        navigator.currentState!.pop();
        await run(const Duration(milliseconds: 400));
        await open(ScreenPage(client: client, bot: bot), '$tag-screen');
        await open(BotEditor(client: client, existing: bot), '$tag-editor');
        await open(
          BotEditor(client: client, group: true, existing: group),
          '$tag-group-editor',
        );
        await open(SettingsPage(client: client), '$tag-settings');
        await open(SourcesPage(client: client), '$tag-sources');
        await open(
          ExtensionsPage(client: client, kind: 'skills'),
          '$tag-skills',
        );
        await open(PairingPage(client: client), '$tag-pairing');
        await tester.pumpWidget(const SizedBox.shrink());
        await run(const Duration(milliseconds: 200));
      }
    }
    tester.view.reset();
    glass = android;
    // Leave the real window up so the system backdrop can be captured.
    if (!android) {
      await tester.runAsync(() async {
        await windowManager.ensureInitialized();
        await windowManager.setTitleBarStyle(
          TitleBarStyle.hidden,
          windowButtonVisibility: false,
        );
      });
    }
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      mode.value = theme;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(app(HomePage(client: client)));
      await run(const Duration(milliseconds: 600));
      await tester.tap(row('$room'));
      await run(const Duration(milliseconds: 800));
      // ignore: avoid_print
      print('TOUR HOLD ${theme.name}');
      await run(const Duration(seconds: 8));
    }
    client.dispose();
    // ignore: avoid_print
    print('TOUR ${jsonEncode({'done': true})}');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
