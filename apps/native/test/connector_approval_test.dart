import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/connector_approval.dart';
import 'package:nekodot_native/ui/design.dart';

void main() {
  for (final (choice, result) in [
    ('once', '允许一次'),
    ('always', '总是允许'),
    ('deny', '拒绝'),
  ]) {
    testWidgets('connector $choice folds after acknowledgement, not on tap', (
      tester,
    ) async {
      final client = NekodotClient();
      addTearDown(client.dispose);
      var pending = true;
      String? sending;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return ConnectorApprovalCard(
                  client: client,
                  bot: null,
                  details: const {
                    'title': 'Create an issue',
                    'service': {'name': 'GitHub'},
                    'account': 'Test account',
                    'arguments': {'title': 'Test issue'},
                  },
                  pending: pending,
                  sending: sending,
                  choices: const ['once', 'always', 'deny'],
                  result: result,
                  denied: choice == 'deny',
                  unanswered: false,
                  onRespond: (value) async => update(() => sending = value),
                  error: '',
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('详细信息'));
      await tester.pumpAndSettle();
      expect(find.text('Test issue'), findsOneWidget);
      final before = tester.getSize(find.byType(ChatCard)).height;

      await tester.tap(find.byKey(ValueKey('connector-approval-$choice')));
      await tester.pump();
      expect(sending, choice);
      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('Test issue'), findsOneWidget);

      update(() {
        pending = false;
        sending = null;
      });
      await tester.pumpAndSettle();
      expect(find.text(result), findsOneWidget);
      expect(find.text('GitHub'), findsNothing);
      expect(find.text('详细信息'), findsNothing);
      expect(find.text('Test issue'), findsNothing);
      expect(
        tester.getSize(find.byType(ChatCard)).height,
        lessThan(before),
      );

      await tester.tap(
        find.byKey(const ValueKey('connector-approval-summary')),
      );
      await tester.pumpAndSettle();
      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('Test issue'), findsNothing);
      for (final action in ['once', 'always', 'deny']) {
        expect(
          find.byKey(ValueKey('connector-approval-$action')),
          findsNothing,
        );
      }
      await tester.tap(find.text('详细信息'));
      await tester.pumpAndSettle();
      expect(find.text('Test issue'), findsOneWidget);

      // A restored, already-answered card starts collapsed as well.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: Scaffold(
            body: ConnectorApprovalCard(
              client: client,
              bot: null,
              details: const {
                'title': 'Create an issue',
                'service': {'name': 'GitHub'},
                'account': 'Test account',
                'arguments': {'title': 'Test issue'},
              },
              pending: false,
              sending: null,
              choices: const [],
              result: result,
              denied: choice == 'deny',
              unanswered: false,
              onRespond: (_) async => fail('Answered card cannot respond'),
              error: '',
            ),
          ),
        ),
      );
      expect(find.text(result), findsOneWidget);
      expect(find.text('详细信息'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
