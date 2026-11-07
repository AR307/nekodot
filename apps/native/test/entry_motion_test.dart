import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/ui/entry_motion.dart';

double? shownOpacity(WidgetTester tester) {
  final found = find.descendant(
    of: find.byType(EntryMotion),
    matching: find.byType(Opacity),
  );
  return found.evaluate().isEmpty
      ? null
      : tester.widget<Opacity>(found).opacity;
}

void main() {
  testWidgets('A message that just arrived fades and rises in once', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: EntryMotion(play: true, own: true, child: Text('你好')),
      ),
    );
    expect(shownOpacity(tester), 0);
    await tester.pump(const Duration(milliseconds: 60));
    final early = shownOpacity(tester)!;
    expect(early, inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 60));
    expect(shownOpacity(tester)!, greaterThan(early));
    await tester.pumpAndSettle();
    // Settled, it is the message alone again.
    expect(shownOpacity(tester), isNull);
  });

  testWidgets('History and reduced motion show at once', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: EntryMotion(play: false, child: Text('旧消息'))),
    );
    expect(shownOpacity(tester), isNull);
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: EntryMotion(
            key: ValueKey('still'),
            play: true,
            child: Text('新消息'),
          ),
        ),
      ),
    );
    expect(shownOpacity(tester), isNull);
  });
}
