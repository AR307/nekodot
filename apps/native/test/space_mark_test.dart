import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/data/spaces.dart';
import 'package:nekodot_native/features/space_mark.dart';
import 'package:nekodot_native/ui/design.dart';

Space space({String? icon}) => Space.fromJson({
  'spaceId': 's1',
  'botId': 'b1',
  'conversationId': 'c1',
  'name': 'Water',
  'createdAt': '2026-11-14T00:00:00.000Z',
  'updatedAt': '2026-11-14T00:00:00.000Z',
  'version': 1,
  'archived': false,
  'origins': <String>[],
  'allowedOrigins': <String>[],
  'icon': ?icon,
});

const drawn =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">'
    '<rect width="64" height="64" fill="#1f4d3a"/>'
    '<circle cx="32" cy="32" r="14" fill="#ffffff"/></svg>';

void main() {
  Future<void> show(WidgetTester tester, Space? of) => tester.pumpWidget(
    MaterialApp(
      theme: appTheme(Brightness.light),
      home: Center(child: SpaceMark(space: of, size: 36)),
    ),
  );

  test('a space keeps the icon its Dot drew', () {
    expect(space().icon, isNull);
    expect(space().toJson().containsKey('icon'), isFalse);
    final kept = Space.fromJson(space(icon: drawn).toJson());
    expect(kept.icon, drawn);
  });

  testWidgets('the mark is the drawn icon, in its own square', (tester) async {
    await show(tester, space(icon: drawn));
    await tester.pumpAndSettle();
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byIcon(Symbols.space_dashboard), findsNothing);
    expect(tester.getSize(find.byType(SpaceMark)), const Size(36, 36));
  });

  testWidgets('a space with no icon shows the plain mark of a space', (
    tester,
  ) async {
    await show(tester, space());
    expect(find.byType(SvgPicture), findsNothing);
    expect(find.byIcon(Symbols.space_dashboard), findsOneWidget);
    await show(tester, null);
    expect(find.byIcon(Symbols.space_dashboard), findsOneWidget);
  });

  testWidgets('an icon that cannot be drawn gives way to the plain mark', (
    tester,
  ) async {
    await show(tester, space(icon: '<svg viewBox="0 0 64 64"><path d="M'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Symbols.space_dashboard), findsOneWidget);
  });
}
