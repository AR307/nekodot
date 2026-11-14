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

/// Walks the spaces gallery against a running Relay with a real Node and the
/// spaces a Bot has built, and writes a PNG of each step: tiles showing what
/// their spaces look like (the pictures are taken out of sight), a space
/// growing out of its tile frame by frame, and going back into it; then the
/// same on a phone. A copy of each kept picture is written beside the PNGs.
/// The web view itself is a texture and does not appear in these PNGs.
/// Defines: RELAY_URL, QA_TOKEN, QA_NODE, TOUR_OUT.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('spaces tour', (tester) async {
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
      // As on a device that has opened no space yet: no pictures are kept.
      await client.store!.write('spaces/thumbs', {});
      await client.spaces.thumbs.open(client.store!);
    });
    const shell = String.fromEnvironment('TOUR_OUT');
    final out = Directory('$shell/../spaces');
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
    final nodeId = client.selectedNodeId!;
    Finder key(String name) => find.byKey(ValueKey(name));
    Finder section(String id) => key('home-section-$id');
    final built = client.node.spaces.values
        .where((space) => !space.archived && space.version > 0)
        .toList();
    notes['spaces'] = built.length;
    int pictured() => built
        .where(
          (space) =>
              client.spaces.thumbs.version(nodeId, space.spaceId) ==
              space.version,
        )
        .length;
    final tiles = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('space-tile-'),
    );
    Future<void> dark(String name) async {
      mode.value = ThemeMode.dark;
      await shot(name);
      mode.value = ThemeMode.light;
      await run(const Duration(milliseconds: 300));
    }

    // ---------- desktop ----------
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2;
    client.workspace.remove('category:$nodeId');
    client.workspace.remove('details:$nodeId');
    client.workspace.remove('space:$nodeId');
    await tester.pumpWidget(app());
    await run(const Duration(milliseconds: 600));

    await tester.tap(section('space'));
    notes['picturedBefore'] = pictured();
    await shot('desk-light-spaces-first', settle: 500);
    // No space has been opened: the pictures are taken out of sight.
    final watch = Stopwatch()..start();
    notes['pictured'] = await until(
      () => pictured() == built.length,
      seconds: 90,
    );
    notes['picturedSeconds'] = watch.elapsed.inSeconds;
    await shot('desk-light-spaces', settle: 1200);
    await dark('desk-dark-spaces');
    await tester.runAsync(() async {
      for (final space in built) {
        final kept = client.store!.file(
          'spaces/thumbs/$nodeId/${space.spaceId}.jpg',
        );
        if (await kept.exists()) {
          await kept.copy('${out.path}/kept-${space.name}.jpg');
        }
      }
    });

    // Out of its tile, frame by frame.
    await tester.tap(tiles.first);
    await shot('desk-grow-1', settle: 50);
    await shot('desk-grow-2', settle: 70);
    await shot('desk-grow-3', settle: 90);
    await shot('desk-grow-4', settle: 140);
    await shot('desk-space-open', settle: 400);
    await shot('desk-space-live', settle: 4000);
    // And back into it.
    await tester.tap(find.byTooltip('返回'));
    await shot('desk-shrink-1', settle: 50);
    await shot('desk-shrink-2', settle: 70);
    await shot('desk-spaces-back', settle: 900);
    // The second tile, in the dark.
    mode.value = ThemeMode.dark;
    await run(const Duration(milliseconds: 400));
    await tester.tap(tiles.last);
    await shot('desk-dark-grow', settle: 110);
    await shot('desk-dark-space-open', settle: 1200);
    await tester.tap(find.byTooltip('返回'));
    await run(const Duration(milliseconds: 900));
    mode.value = ThemeMode.light;
    await run(const Duration(milliseconds: 300));

    // ---------- phone ----------
    await tester.pumpWidget(const SizedBox.shrink());
    glass = true;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 108, bottom: 72);
    client.workspace.remove('space:$nodeId');
    await tester.pumpWidget(app());
    await run(const Duration(milliseconds: 600));
    navigator.currentState!.popUntil((route) => route.isFirst);
    await run(const Duration(milliseconds: 500));
    await tester.tap(section('space'));
    await shot('phone-light-spaces', settle: 1500);
    await dark('phone-dark-spaces');
    await tester.tap(tiles.first);
    await shot('phone-grow-1', settle: 50);
    await shot('phone-grow-2', settle: 70);
    await shot('phone-grow-3', settle: 90);
    await shot('phone-grow-4', settle: 140);
    await shot('phone-space-open', settle: 400);
    await shot('phone-space-live', settle: 4000);
    navigator.currentState!.pop();
    await shot('phone-shrink-1', settle: 50);
    await shot('phone-shrink-2', settle: 70);
    await shot('phone-spaces-back', settle: 900);

    tester.view.reset();
    client.dispose();
    // ignore: avoid_print
    print('TOUR ${jsonEncode({'done': true, ...notes})}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
