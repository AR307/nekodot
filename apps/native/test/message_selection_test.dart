import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/ui/message_selection.dart';

void main() {
  testWidgets('mouse selection offers a quote and preserves exact words', (
    tester,
  ) async {
    String? quote;
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(
          body: ListView(
            controller: scroll,
            children: [
              MessageSelection(
                quoteLabel: 'Quote in reply',
                onQuote: (value) => quote = value,
                child: const Text('Selected words stay intact.'),
              ),
              const SizedBox(height: 1500),
            ],
          ),
        ),
      ),
    );
    Future<void> select() async {
      final rect = tester.getRect(find.text('Selected words stay intact.'));
      final gesture = await tester.startGesture(
        rect.topLeft + const Offset(2, 8),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(rect.topLeft + const Offset(30, 8));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveTo(rect.topLeft + const Offset(140, 8));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('selection-quote-bubble')),
        findsNothing,
      );
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await select();
    expect(
      find.byKey(const ValueKey('selection-quote-bubble')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('selection-quote-bubble')));
    await tester.pumpAndSettle();
    expect(quote, isNotEmpty);
    expect('Selected words stay intact.', contains(quote!));
    expect(find.byKey(const ValueKey('selection-quote-bubble')), findsNothing);

    await select();
    scroll.jumpTo(10);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('selection-quote-bubble')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });
}
