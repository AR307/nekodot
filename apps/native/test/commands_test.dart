import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/commands.dart';
import 'package:nekodot_native/ui/design.dart';

void main() {
  testWidgets(
    'phone command picker keeps usable actions first and explains other commands',
    (tester) async {
      final client = NekodotClient()..language = 'en';
      String? selected;
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: Scaffold(
            body: CommandPalette(
              client: client,
              botId: 'bot',
              members: const [],
              query: '/',
              loading: false,
              entries: const [
                {
                  'name': '/history',
                  'description': 'Show native history',
                  'availability': 'app',
                },
                {
                  'name': '/new',
                  'description': 'Start a session',
                  'availability': 'not-integrated',
                },
                {
                  'name': '/redraw',
                  'description': 'Repaint terminal',
                  'availability': 'terminal',
                },
              ],
              onBot: (_) {},
              onRefresh: () {},
              onSelect: (name) => selected = name,
            ),
          ),
        ),
      );
      expect(find.text('/history'), findsOneWidget);
      expect(find.text('App action'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, '/history'));
      expect(selected, '/history');
      await tester.tap(find.text('Other commands (2)'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ListTile>(find.widgetWithText(ListTile, '/new')).enabled,
        isFalse,
      );
      expect(find.text('Not connected'), findsOneWidget);
      expect(find.text('Server terminal'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      client.dispose();
    },
  );
}
