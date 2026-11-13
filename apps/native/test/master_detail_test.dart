import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/ui/design.dart';

/// Three rows that each open a page naming them. A row asks the list beside
/// it whether its page is the one open.
class _Rows extends StatelessWidget {
  const _Rows();
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      for (final name in const ['a', 'b', 'c'])
        Builder(
          builder: (context) => ListTile(
            key: ValueKey('row-$name'),
            selected: MasterDetail.shows(context, name),
            title: Text('row $name'),
            onTap: () => pushPage(
              context,
              Scaffold(
                body: Center(
                  child: TextButton(
                    key: ValueKey('close-$name'),
                    onPressed: () => Navigator.pop(context),
                    child: Text('page $name'),
                  ),
                ),
              ),
              row: name,
            ),
          ),
        ),
    ],
  );
}

void main() {
  Future<void> show(WidgetTester tester, Size size, {Widget? initial}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Scaffold(
          body: MasterDetail(
            master: const _Rows(),
            initial: initial,
            initialRow: initial == null ? null : 'b',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool marked(WidgetTester tester, String name) =>
      tester.widget<ListTile>(find.byKey(ValueKey('row-$name'))).selected;

  testWidgets('the row whose page is beside the list is marked', (
    tester,
  ) async {
    await show(tester, const Size(1000, 600));
    expect(
      [for (final n in 'abc'.split('')) marked(tester, n)],
      [false, false, false],
    );

    await tester.tap(find.byKey(const ValueKey('row-a')));
    await tester.pumpAndSettle();
    expect(find.text('page a'), findsOneWidget);
    expect(find.text('row a'), findsOneWidget);
    expect(marked(tester, 'a'), isTrue);
    expect(marked(tester, 'b'), isFalse);

    // Another row takes its place and the mark with it.
    await tester.tap(find.byKey(const ValueKey('row-c')));
    await tester.pumpAndSettle();
    expect(find.text('page a'), findsNothing);
    expect(find.text('page c'), findsOneWidget);
    expect(marked(tester, 'a'), isFalse);
    expect(marked(tester, 'c'), isTrue);
  });

  testWidgets('the mark goes when the page closes', (tester) async {
    await show(tester, const Size(1000, 600));
    await tester.tap(find.byKey(const ValueKey('row-b')));
    await tester.pumpAndSettle();
    expect(marked(tester, 'b'), isTrue);
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pumpAndSettle();
    expect(find.text('page b'), findsNothing);
    expect(marked(tester, 'b'), isFalse);
  });

  testWidgets('what stands there at first marks its row', (tester) async {
    await show(
      tester,
      const Size(1000, 600),
      initial: const Scaffold(body: Text('page b')),
    );
    expect(find.text('page b'), findsOneWidget);
    expect(marked(tester, 'b'), isTrue);
    await tester.tap(find.byKey(const ValueKey('row-a')));
    await tester.pumpAndSettle();
    expect(marked(tester, 'b'), isFalse);
    expect(marked(tester, 'a'), isTrue);
  });

  testWidgets('with no room beside it a row opens over the list, unmarked', (
    tester,
  ) async {
    await show(tester, const Size(600, 600));
    await tester.tap(find.byKey(const ValueKey('row-a')));
    await tester.pumpAndSettle();
    expect(find.text('page a'), findsOneWidget);
    expect(find.text('row a'), findsNothing);
    Navigator.pop(tester.element(find.text('page a')));
    await tester.pumpAndSettle();
    expect(marked(tester, 'a'), isFalse);
  });
}
