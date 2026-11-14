import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/ui/design.dart';

/// Counts how many times its state has been made.
class _Page extends StatefulWidget {
  static int made = 0;
  const _Page();
  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  void initState() {
    super.initState();
    _Page.made++;
  }

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(key: ValueKey('page'), color: Color(0xff336699));
}

void main() {
  const box = Rect.fromLTWH(100, 200, 160, 100);
  Rect page(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey('page')));

  Future<NavigatorState> open(WidgetTester tester, {Rect? from}) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    _Page.made = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(GrowRoute<void>(const _Page(), from: from));
    await tester.pump();
    return navigator;
  }

  testWidgets('a page grows out of the box that opened it', (tester) async {
    await open(tester, from: box);
    // It starts as the box: the same place, the same width, showing the top
    // of the page at the box's scale.
    await tester.pump(const Duration(milliseconds: 1));
    final first = page(tester);
    expect(first.left, closeTo(box.left, 4));
    expect(first.top, closeTo(box.top, 4));
    expect(first.width, closeTo(box.width, 8));

    await tester.pump(const Duration(milliseconds: 120));
    final middle = page(tester);
    expect(middle.width, greaterThan(first.width));
    expect(middle.width, lessThan(820));

    await tester.pumpAndSettle();
    expect(page(tester), const Rect.fromLTWH(0, 0, 800, 600));
    // The same page from the first frame to the last.
    expect(_Page.made, 1);
  });

  testWidgets('it goes back into the box on the way out', (tester) async {
    final navigator = await open(tester, from: box);
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final leaving = page(tester);
    expect(leaving.width, lessThan(800));
    expect(leaving.left, greaterThan(0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page')), findsNothing);
  });

  testWidgets('with no box it rises into place at full size', (tester) async {
    await open(tester);
    await tester.pump(const Duration(milliseconds: 1));
    final first = page(tester);
    expect(first.size, const Size(800, 600));
    expect(first.top, greaterThan(0));
    await tester.pumpAndSettle();
    expect(page(tester), const Rect.fromLTWH(0, 0, 800, 600));
  });

  testWidgets('a page in a list keeps its state when the list is rebuilt', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    _Page.made = 0;
    final from = ValueNotifier<Rect?>(null);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: ValueListenableBuilder(
          valueListenable: from,
          builder: (context, value, _) => Navigator(
            pages: [
              const GrowPage<void>(
                key: ValueKey('under'),
                child: SizedBox.expand(),
              ),
              if (value != null)
                GrowPage<void>(
                  key: const ValueKey('over'),
                  from: value,
                  child: const _Page(),
                ),
            ],
            onDidRemovePage: (_) {},
          ),
        ),
      ),
    );
    from.value = box;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(page(tester).width, closeTo(box.width, 8));
    await tester.pumpAndSettle();
    expect(page(tester), const Rect.fromLTWH(0, 0, 800, 600));
    // Taken out of the list, it shrinks away.
    from.value = null;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(page(tester).width, lessThan(800));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page')), findsNothing);
    expect(_Page.made, 1);
  });
}
