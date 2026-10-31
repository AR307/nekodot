import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/ui/design.dart';

/// Requires the isolated real legacy Node/service journey, never production.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'A real legacy service upgrades and its native notice disappears',
    (tester) async {
      final directory = const String.fromEnvironment('QA_DIRECTORY');
      expect(directory, isNotEmpty);
      final c = NekodotClient();
      await tester.runAsync(() async {
        final login = await c.request(
          '/auth/login',
          method: 'POST',
          body: {
            'email': const String.fromEnvironment('QA_EMAIL'),
            'password': const String.fromEnvironment('QA_PASSWORD'),
          },
        );
        c.token = login['token'] as String;
        await c.bootstrap();
      });
      runApp(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: HomePage(client: c),
        ),
      );
      Future<void> until(bool Function() done) async {
        final end = DateTime.now().add(const Duration(minutes: 5));
        while (!done()) {
          if (DateTime.now().isAfter(end)) {
            fail('Isolated service did not finish the upgrade');
          }
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        await tester.pump(const Duration(milliseconds: 300));
      }

      await until(
        () => c.online && find.text('这台电脑需要更新一次').evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('复制命令'));
      await tester.pump();
      await tester.runAsync(() async {
        final value = await Clipboard.getData(Clipboard.kTextPlain);
        expect(value?.text, "curl -fsSL '${c.origin}/install.sh' | bash");
        await File('$directory/native-ready')
            .writeAsString('legacy command copied');
      });
      await until(() => find.text('这台电脑需要更新一次').evaluate().isEmpty && c.online);
      await File('$directory/native-recovered')
          .writeAsString('same client recovered');
      await until(() => File('$directory/native-done').existsSync());
      expect(tester.takeException(), isNull);
      c.dispose();
    },
  );
}
