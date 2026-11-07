import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/ui/design.dart';
import 'package:nekodot_native/ui/prompt_card.dart';
import 'package:nekodot_native/ui/message_selection.dart';

void main() {
  testWidgets(
    'typing and clearing keeps the same editor with large phone text',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final input = TextEditingController();
      final focus = FocusNode();
      addTearDown(input.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light, glass: true),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ValueListenableBuilder(
                valueListenable: input,
                builder: (_, value, child) => PromptCard(
                  hasContent: value.text.isNotEmpty,
                  running: false,
                  field: TextField(
                    controller: input,
                    focusNode: focus,
                    maxLines: 7,
                  ),
                  tools: IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.add),
                  ),
                  action: TextButton(
                    onPressed: () {},
                    child: const Text('xhigh'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      final editor = tester.state(find.byType(EditableText));
      await tester.enterText(find.byType(TextField), '中文输入与草稿保留');
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(EditableText)), same(editor));
      expect(focus.hasFocus, isTrue);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(EditableText)), same(editor));
      expect(focus.hasFocus, isTrue);
      expect(input.text, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('selecting a reply keeps the focused composer from moving it', (
    tester,
  ) async {
    var historyFocused = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: StatefulBuilder(
          builder: (context, update) => Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: Focus(
                    onFocusChange: (value) =>
                        update(() => historyFocused = value),
                    child: ListView(
                      reverse: true,
                      children: [
                        MessageSelection(
                          quoteLabel: 'Quote in reply',
                          onQuote: (_) {},
                          child: const Text(
                            'Keep the words still while selecting them.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                PromptCard(
                  holdSize: historyFocused,
                  hasContent: false,
                  running: false,
                  field: const TextField(),
                  tools: const Icon(Icons.add),
                  action: const Icon(Icons.mic),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    final words = find.text('Keep the words still while selecting them.');
    final y = tester.getTopLeft(words).dy;
    final size = tester.getSize(find.byType(PromptCard));
    final point = tester.getTopLeft(words) + const Offset(3, 8);
    final mouse = await tester.startGesture(
      point,
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveTo(point + const Offset(30, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await mouse.moveTo(point + const Offset(140, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(words).dy, y);
    expect(tester.getSize(find.byType(PromptCard)), size);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('selection-quote-bubble')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

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
        expect(
          tester.getSize(find.byType(PromptCard)).width,
          width > 768 ? 720 : width - 48,
        );
        expect(
          tester.getSize(find.byType(PromptCard)).height,
          lessThanOrEqualTo(72),
        );
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
    expect(tester.getSize(find.byType(PromptCard)).width, 720);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(PromptCard)).width, 720);
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
