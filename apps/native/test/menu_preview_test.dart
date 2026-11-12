import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/menu_preview.dart';

void main() {
  testWidgets(
    'compare A motion with selection, keyboard, reversal and phone sheets',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const directory = String.fromEnvironment('MENU_PREVIEW_EVIDENCE');
      final shadowsDisabled = debugDisableShadows;
      if (directory.isNotEmpty) {
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = shadowsDisabled);
        await (FontLoader('Nunito')
              ..addFont(rootBundle.load('assets/fonts/nunito-400.ttf'))
              ..addFont(rootBundle.load('assets/fonts/nunito-600.ttf')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        if (Platform.isWindows) {
          await tester.runAsync(() async {
            await (FontLoader('Microsoft YaHei UI')..addFont(
                  File('${Platform.environment['WINDIR']}/Fonts/msyh.ttc')
                      .readAsBytes()
                      .then(ByteData.sublistView),
                ))
                .load();
          });
        }
      }
      await tester.pumpWidget(const MenuPreviewApp());
      await tester.pumpAndSettle();

      Future<void> capture(String name) async {
        if (directory.isEmpty) return;
        final canvas = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('menu-preview-canvas')),
        );
        await tester.runAsync(() async {
          final image = await canvas.toImage(pixelRatio: 1.5);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(directory).create(recursive: true);
          await File('$directory/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.tap(find.byKey(const ValueKey('menu-preview-play')));
      await tester.pumpAndSettle();
      await capture('desktop-light');
      await tester.tapAt(const Offset(32, 100));
      await tester.pumpAndSettle();

      for (final variant in ['A1', 'A2', 'A3']) {
        await tester.tap(find.byKey(ValueKey('open-model-$variant')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 45));
        final motion = find.byKey(ValueKey('motion-$variant-model'));
        expect(tester.widget<Opacity>(motion).opacity, inExclusiveRange(0, 1));
        expect(
          find.byKey(ValueKey('popup-model-$variant-gpt-6-astra')),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        // Closing keeps the overlay until the exit motion has finished.
        expect(motion, findsOneWidget);
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('popup-model-$variant-gpt-6-astra')),
          findsNothing,
        );

        await tester.tap(find.byKey(ValueKey('open-model-$variant')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('popup-model-$variant-gpt-6-astra')),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(ValueKey('open-model-$variant')),
            matching: find.text('gpt-6-astra'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('popup-model-$variant-gpt-6-astra')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(ValueKey('open-model-$variant')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('popup-model-$variant-gpt-6.1-sol')),
        );
        await tester.pumpAndSettle();

        // A rapid toggle reverses from the current position instead of flashing
        // or allowing an old close callback to hide the reopened menu.
        await tester.tap(find.byKey(ValueKey('open-model-$variant')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tap(find.byKey(ValueKey('open-model-$variant')));
        await tester.pump(const Duration(milliseconds: 20));
        await tester.tap(find.byKey(ValueKey('open-model-$variant')));
        await tester.pumpAndSettle();
        expect(motion, findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(motion, findsNothing);
        expect(
          find.descendant(
            of: find.byKey(ValueKey('open-model-$variant')),
            matching: find.text('gpt-6-astra'),
          ),
          findsOneWidget,
        );
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byKey(const ValueKey('menu-preview-theme')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-preview-play')));
      await tester.pumpAndSettle();
      await capture('desktop-dark');
      await tester.tapAt(const Offset(32, 100));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-preview-language')));
      await tester.pumpAndSettle();
      for (final variant in ['A1', 'A2', 'A3']) {
        await tester.tap(find.byKey(ValueKey('actions-anchor-$variant')));
        await tester.pumpAndSettle();
        expect(find.text('Edit with Dot'), findsOneWidget);
        await tester.tap(find.text('Rename'));
        await tester.pumpAndSettle();
        expect(find.text('Edit with Dot'), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('menu-preview-language')));

      await tester.tap(find.byKey(const ValueKey('menu-preview-device')));
      await tester.pumpAndSettle();
      await capture('phone-dark');
      await tester.tap(find.byKey(const ValueKey('menu-preview-theme')));
      await tester.pumpAndSettle();
      await capture('phone-light');
      for (final variant in ['A1', 'A2', 'A3']) {
        final option = find.byKey(ValueKey('phone-option-$variant-gpt-6-luna'));
        final button = find.descendant(
          of: option,
          matching: find.byType(MenuItemButton),
        );
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        await tester.tap(option);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(ValueKey('phone-model-$variant')),
            matching: find.text('gpt-6-luna'),
          ),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('menu-preview-device')));
      await tester.pumpAndSettle();
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pump();
      for (final variant in ['A1', 'A2', 'A3']) {
        await tester.tap(find.byKey(ValueKey('open-model-$variant')));
        await tester.pump();
        expect(
          tester
              .widget<Opacity>(find.byKey(ValueKey('motion-$variant-model')))
              .opacity,
          1,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(find.byKey(ValueKey('motion-$variant-model')), findsNothing);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      debugDisableShadows = shadowsDisabled;
    },
  );
}
