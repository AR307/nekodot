import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/ui/design.dart';

Widget host(
  Widget child, {
  bool phone = false,
  bool reduced = false,
  VoidCallback? onRootBack,
}) => MaterialApp(
  theme: appTheme(
    Brightness.light,
    glass: phone,
  ).copyWith(platform: phone ? TargetPlatform.android : TargetPlatform.windows),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
    child: child!,
  ),
  home: Builder(
    builder: (context) => PopScope(
      canPop:
          onRootBack == null || ModalRoute.of(context)!.willHandlePopInternally,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onRootBack?.call();
      },
      child: Scaffold(body: child),
    ),
  ),
);

void main() {
  testWidgets('computer menu selects by keyboard, reverses and dismisses', (
    tester,
  ) async {
    String? chosen;
    await tester.pumpWidget(
      host(
        Align(
          alignment: Alignment.topLeft,
          child: ActionMenu<String>(
            tooltip: 'Computer',
            onSelected: (value) => chosen = value,
            items: const [
              MenuAction(value: 'one', label: 'Computer 1', selected: true),
              MenuAction(value: 'two', label: 'Computer 2'),
              null,
              MenuAction(value: 'add', label: 'Add computer'),
            ],
          ),
        ),
      ),
    );
    final anchor = find.byTooltip('Computer');
    await tester.tapAt(tester.getCenter(anchor));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final fade = find.ancestor(
      of: find.byType(MenuCard),
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(fade).opacity, inExclusiveRange(0, 1));
    // Repeated clicks reverse the actual animation, not a queued timer.
    await tester.tapAt(tester.getCenter(anchor));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.tapAt(tester.getCenter(anchor));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(chosen, 'two');
    expect(find.byType(MenuCard), findsNothing);
    await tester.tap(anchor);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(MenuCard), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(MenuCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long options scroll at the window edge without click-through', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var outside = 0;
    var pointerDowns = 0;
    int? chosen;
    await tester.pumpWidget(
      host(
        Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: Listener(
                onPointerDown: (_) => pointerDowns++,
                child: TextButton(
                  onPressed: () => outside++,
                  child: const Text('Outside'),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: ActionMenu<int>(
                tooltip: 'Options',
                alignEnd: true,
                onSelected: (value) => chosen = value,
                items: [
                  const MenuAction(
                    value: -1,
                    label: 'Unavailable',
                    enabled: false,
                  ),
                  for (var i = 0; i < 30; i++)
                    MenuAction(
                      value: i,
                      label: 'Model $i with a long provider description',
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byTooltip('Options'));
    await tester.pumpAndSettle();
    final bounds = tester.getRect(find.byType(MenuCard));
    expect(bounds.left, greaterThanOrEqualTo(12));
    expect(bounds.right, lessThanOrEqualTo(468));
    expect(bounds.top, greaterThanOrEqualTo(12));
    expect(bounds.bottom, lessThanOrEqualTo(588));
    await tester.tap(find.text('Unavailable'));
    await tester.pumpAndSettle();
    expect(chosen, isNull);
    final last = find.text('Model 29 with a long provider description');
    await tester.scrollUntilVisible(
      last,
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(chosen, 29);
    await tester.tap(find.byTooltip('Options'));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.text('Outside')));
    await tester.pumpAndSettle();
    expect(outside, 0);
    expect(
      pointerDowns,
      0,
      reason: 'a native view receives raw pointer events',
    );
    expect(find.byType(MenuCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone dropdown keeps touch size, selection and system back', (
    tester,
  ) async {
    String? chosen;
    var backgroundRequested = false;
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      host(
        Center(
          child: SizedBox(
            width: 300,
            child: MenuSelect<String>(
              value: 'one',
              label: 'Dot',
              options: const [('one', 'Dot 1'), ('two', 'Dot 2')],
              onChanged: (value) => chosen = value,
            ),
          ),
        ),
        phone: true,
        onRootBack: () => backgroundRequested = true,
      ),
    );
    await tester.tap(find.byType(InputDecorator));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(MenuCard), findsOneWidget);
    final bounds = tester.getRect(find.byType(MenuCard));
    expect(bounds.width, 300);
    expect(bounds.height, lessThan(150));
    final field = tester.getRect(find.byType(InputDecorator));
    expect(bounds.left, field.left);
    expect((bounds.top - field.bottom).abs(), lessThan(10));
    final option = find.byKey(const ValueKey('select-two'));
    expect(tester.getSize(option).height, greaterThanOrEqualTo(48));
    await tester.tap(option);
    await tester.pumpAndSettle();
    expect(chosen, 'two');
    expect(find.byType(MenuCard), findsNothing);
    await tester.tap(find.byType(InputDecorator));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(MenuCard), findsNothing);
    expect(find.byType(InputDecorator), findsOneWidget);
    expect(backgroundRequested, isFalse);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(backgroundRequested, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion opens and closes the actual menu immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ActionMenu<int>(
          tooltip: 'More',
          items: const [MenuAction(value: 1, label: 'Rename')],
          onSelected: (_) {},
        ),
        reduced: true,
      ),
    );
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    expect(find.byType(MenuCard), findsOneWidget);
    final fade = find.ancestor(
      of: find.byType(MenuCard),
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(fade).opacity, 1);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(MenuCard), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
