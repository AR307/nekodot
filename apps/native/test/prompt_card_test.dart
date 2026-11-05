import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/ui/design.dart';
import 'package:nekodot_native/ui/prompt_card.dart';

void main() {
  for (final width in [1000.0, 390.0]) {
    for (final tool in ['Attach file']) {
      testWidgets('$tool opens from an empty focused capsule at $width px', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final focus = FocusNode();
        addTearDown(focus.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(Brightness.dark),
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Builder(
                    builder: (context) {
                      void open(String title) => showDialog<void>(
                        context: context,
                        builder: (_) => AlertDialog(title: Text(title)),
                      );
                      return PromptCard(
                        field: TextField(focusNode: focus),
                        hasContent: false,
                        running: false,
                        tools: IconButton(
                          tooltip: 'Attach file',
                          onPressed: () => open('Choose file'),
                          icon: const Icon(Icons.add),
                        ),
                        action: IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.mic),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        final button = find.byTooltip('Attach file');
        // Separate mouse down/up with a frame, as a real desktop click does.
        final mouse = await tester.startGesture(
          tester.getCenter(button),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isTrue);
        expect(button.hitTestable(), findsOneWidget);
        await mouse.up();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Choose file'), findsOneWidget);
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(5, 5), kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isFalse);
        expect(tester.getSize(find.byType(PromptCard)).width, 320);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('capsule expands for typing, preserves text, and fits a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final input = TextEditingController();
    addTearDown(input.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: PromptCard(
                field: TextField(controller: input),
                hasContent: false,
                running: false,
                tools: const Icon(Icons.add),
                action: IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.mic),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(PromptCard)).width, 320);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(PromptCard)).width, 480);
    await tester.enterText(find.byType(TextField), '下一条草稿');
    expect(input.text, '下一条草稿');
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(PromptCard)).width,
      lessThanOrEqualTo(342),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
