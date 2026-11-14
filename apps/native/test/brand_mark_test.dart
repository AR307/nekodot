import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/ui/auth_layout.dart';
import 'package:nekodot_native/ui/brand_mark.dart';
import 'package:nekodot_native/ui/design.dart';

void main() {
  testWidgets('the wordmark carries nekodot\'s mark in the theme\'s ink', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: const Center(child: AuthWordmark()),
      ),
    );
    await tester.pumpAndSettle();
    final mark = tester.widget<SvgPicture>(
      find.descendant(
        of: find.byType(BrandMark),
        matching: find.byType(SvgPicture),
      ),
    );
    final ink = tester.element(find.byType(BrandMark)).tone.ink;
    expect(mark.colorFilter, ColorFilter.mode(ink, BlendMode.srcIn));
    expect(tester.getSize(find.byType(BrandMark)), const Size(28, 28));
    expect(tester.takeException(), isNull);
  });
}
