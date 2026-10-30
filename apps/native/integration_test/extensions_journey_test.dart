import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/extensions.dart';
import 'package:nekodot_native/ui/design.dart';

/// Uses the isolated Node + Relay + recorded-management service, not a widget mock.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const inspect = bool.fromEnvironment('QA_INSPECT');
  testWidgets(
    'native extension search, README preview, full page and back across real RPC',
    (tester) async {
      final client = NekodotClient();
      await client.login(
        const String.fromEnvironment('QA_EMAIL'),
        const String.fromEnvironment('QA_PASSWORD'),
      );
      Future<void> until(bool Function() ready) async {
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (!ready() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 200));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(
          ready(),
          isTrue,
          reason:
              'The native extension journey did not reach its expected state.',
        );
      }

      await client.selectNode(const String.fromEnvironment('QA_NODE'));
      await until(() => client.online);
      runApp(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: ExtensionsPage(client: client, kind: 'plugins'),
        ),
      );
      await until(() => find.byType(TextField).evaluate().isNotEmpty);
      await tester.enterText(find.byType(TextField).first, 'docs-probe');
      await tester.pump(const Duration(milliseconds: 300));
      await until(
        () => find.widgetWithText(ListTile, 'docs-probe').evaluate().isNotEmpty,
      );
      await tester.tap(find.widgetWithText(ListTile, 'docs-probe'));
      await until(
        () => find.text('Native documentation probe').evaluate().isNotEmpty,
      );
      expect(find.text('没有提供仓库信息'), findsOneWidget);
      await tester.ensureVisible(find.text('完整内容'));
      debugPrint('QA: native extension preview ready');
      if (inspect) {
        await tester.pump(const Duration(seconds: 1));
        await Future<void>.delayed(const Duration(seconds: 8));
      }
      await tester.tap(find.text('完整内容'));
      await tester.pumpAndSettle();
      await until(() => find.byType(BackButton).evaluate().isNotEmpty);
      expect(tester.getTopLeft(find.byType(BackButton)).dy, lessThan(120));
      debugPrint('QA: native extension full page ready');
      if (inspect) {
        await tester.pump(const Duration(seconds: 1));
        await Future<void>.delayed(const Duration(seconds: 8));
      }
      await tester.tap(find.byType(BackButton));
      await tester.pump(const Duration(milliseconds: 500));
      await until(() => find.text('完整内容').evaluate().isNotEmpty);
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .controller
            .text,
        'docs-probe',
      );
      expect(find.widgetWithText(ListTile, 'docs-probe'), findsOneWidget);
      expect(tester.takeException(), isNull);
      debugPrint('QA: native extension back and filtered list restored');
      client.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
