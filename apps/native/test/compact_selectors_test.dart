import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/features/bot_details.dart';
import 'package:nekodot_native/ui/design.dart';

void main() {
  for (final phone in [false, true]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets('compact language selector remains usable ($phone, $scale)', (
        tester,
      ) async {
        var selected = 'zh';
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(Brightness.light, glass: phone),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Center(
                  child: StatefulBuilder(
                    builder: (context, update) => Segment<String>(
                      value: selected,
                      options: const {'zh': Text('中'), 'en': Text('EN')},
                      onChanged: (value) => update(() => selected = value),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final height = tester
            .getSize(find.byKey(const ValueKey('segment-track')))
            .height;
        if (scale == 1) expect(height, phone ? 40 : 32);
        if (phone) {
          for (final item in find.byType(InkWell).evaluate()) {
            expect(
              tester.getSize(find.byWidget(item.widget)).height,
              greaterThanOrEqualTo(48),
            );
            expect(
              tester.getSize(find.byWidget(item.widget)).width,
              greaterThanOrEqualTo(48),
            );
          }
        }
        await tester.tap(find.text('EN'));
        await tester.pumpAndSettle();
        expect(selected, 'en');
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'detail tabs track tap and page swipe using the compact selector',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.dark, glass: true),
          home: const DefaultTabController(
            length: 2,
            child: Scaffold(
              body: Column(
                children: [
                  DetailTabs(labels: ['设置', '文件']),
                  Expanded(
                    child: TabBarView(
                      children: [Text('Settings page'), Text('Files page')],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('文件'));
      await tester.pumpAndSettle();
      expect(find.text('Files page').hitTestable(), findsOneWidget);
      await tester.drag(find.byType(TabBarView), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(find.text('Settings page').hitTestable(), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('segment-track'))).height,
        40,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
