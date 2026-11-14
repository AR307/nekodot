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

/// Walks the spaces gallery on an Android device at its own size, against a
/// running Relay with a real Node and the spaces a Bot has built, and writes
/// a PNG of each step into the app's cache folder (`ui-037-spaces`), to be
/// pulled with adb: tiles showing what their spaces look like (the pictures
/// are taken out of sight), a space growing out of its tile and going back
/// into it. A copy of each kept picture is written beside the PNGs. At the
/// end it holds a space open for a while (it prints HOLD), so that the
/// device's own screenshot can show the web view, which these PNGs cannot.
/// Defines: RELAY_URL, QA_TOKEN, QA_NODE.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('android spaces tour', (tester) async {
    final client = NekodotClient();
    final navigator = GlobalKey<NavigatorState>();
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
    final out = Directory('${Directory.systemTemp.path}/ui-037-spaces');
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
      print('TOUR $name.png');
    }

    final nodeId = client.selectedNodeId!;
    final notes = <String, Object?>{
      'size': '${tester.view.physicalSize}',
      'ratio': tester.view.devicePixelRatio,
      'android': Platform.isAndroid,
      'out': out.path,
    };
    Finder key(String name) => find.byKey(ValueKey(name));
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
    Future<Map<String, int>> kept() async => {
      for (final space in built)
        space.name:
            await tester.runAsync(() async {
              final file = client.store!.file(
                'spaces/thumbs/$nodeId/${space.spaceId}.jpg',
              );
              return await file.exists() ? await file.length() : 0;
            }) ??
            0,
    };

    // When the newest of the kept pictures was written.
    Future<DateTime?> newest() => tester.runAsync<DateTime?>(() async {
      DateTime? latest;
      for (final space in built) {
        final file = client.store!.file(
          'spaces/thumbs/$nodeId/${space.spaceId}.jpg',
        );
        if (!await file.exists()) continue;
        final at = await file.lastModified();
        if (latest == null || at.isAfter(latest)) latest = at;
      }
      return latest;
    });

    client.workspace.remove('space:$nodeId');
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        debugShowCheckedModeBanner: false,
        navigatorObservers: [nativeRoutes],
        theme: appTheme(Brightness.light, glass: true),
        darkTheme: appTheme(Brightness.dark, glass: true),
        builder: (context, child) => Ambient(child: child!),
        home: HomePage(client: client),
      ),
    );
    await run(const Duration(milliseconds: 800));
    navigator.currentState!.popUntil((route) => route.isFirst);
    await run(const Duration(milliseconds: 500));

    await tester.tap(key('home-section-space'));
    await shot('spaces-first', settle: 500);
    // No space has been opened: the pictures are taken out of sight.
    final watch = Stopwatch()..start();
    notes['pictured'] = await until(
      () => pictured() == built.length,
      seconds: 120,
    );
    notes['picturedSeconds'] = watch.elapsed.inSeconds;
    await shot('spaces', settle: 1200);
    notes['keptOutOfSight'] = await kept();
    await tester.runAsync(() async {
      for (final (index, space) in built.indexed) {
        final file = client.store!.file(
          'spaces/thumbs/$nodeId/${space.spaceId}.jpg',
        );
        if (await file.exists()) await file.copy('${out.path}/kept-$index.jpg');
      }
    });

    // Out of its tile, frame by frame, and back into it.
    await tester.tap(tiles.first);
    await shot('grow-1', settle: 50);
    await shot('grow-2', settle: 70);
    await shot('grow-3', settle: 90);
    await shot('grow-4', settle: 140);
    await shot('space-open', settle: 400);
    await shot('space-live', settle: 5000);
    final open = await newest();
    navigator.currentState!.pop();
    await shot('shrink-1', settle: 50);
    await shot('shrink-2', settle: 70);
    await shot('spaces-back', settle: 900);
    // It has been open: its picture is taken again, out of sight.
    final again = Stopwatch()..start();
    var retaken = false;
    while (!retaken && again.elapsed < const Duration(seconds: 30)) {
      await run(const Duration(milliseconds: 300));
      retaken = (await newest())!.isAfter(open!);
    }
    notes['retakenAfterClose'] = retaken;
    notes['retakenMs'] = again.elapsedMilliseconds;
    notes['keptAfterClose'] = await kept();
    await tester.runAsync(() async {
      for (final (index, space) in built.indexed) {
        final file = client.store!.file(
          'spaces/thumbs/$nodeId/${space.spaceId}.jpg',
        );
        if (await file.exists()) {
          await file.copy('${out.path}/kept-after-close-$index.jpg');
        }
      }
    });

    // Held open for the device's own screenshot.
    await tester.tap(tiles.first);
    await run(const Duration(milliseconds: 5000));
    // ignore: avoid_print
    print('TOUR HOLD');
    await run(const Duration(seconds: 15));
    // ignore: avoid_print
    print('TOUR ${jsonEncode({'done': true, ...notes})}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
