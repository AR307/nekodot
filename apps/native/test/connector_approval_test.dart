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
    testWidgets('connector $choice folds on tap and reopens on send failure', (
      tester,
    ) async {
      final client = NekodotClient();
      addTearDown(client.dispose);
      var pending = true;
      String? sending;
      var error = '';
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
                  onRespond: (value) async => update(() {
                    sending = value;
                    error = '';
                  }),
                  error: error,
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
      expect(find.text('GitHub'), findsNothing);
      expect(find.text('Test issue'), findsNothing);
      expect(find.byType(ShiningText), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getSize(find.byType(ChatCard)).height, lessThan(before));

      // A failed submission must reopen the decision rather than look accepted.
      update(() {
        sending = null;
        error = 'Request failed. Try again.';
      });
      await tester.pumpAndSettle();
      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text(error), findsOneWidget);
      expect(
        find.byKey(ValueKey('connector-approval-$choice')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(ValueKey('connector-approval-$choice')));
      await tester.pump();
      expect(find.text('GitHub'), findsNothing);

      update(() {
        pending = false;
        sending = null;
        error = '';
      });
      await tester.pumpAndSettle();
      expect(find.text(result), findsOneWidget);
      expect(find.text('GitHub'), findsNothing);
      expect(find.text('详细信息'), findsNothing);
      expect(find.text('Test issue'), findsNothing);
      expect(tester.getSize(find.byType(ChatCard)).height, lessThan(before));

      await tester.tap(
        find.byKey(const ValueKey('connector-approval-summary')),
      );
      await tester.pumpAndSettle();
      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('Test issue'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('connector-approval-details')),
        findsNothing,
      );
      for (final action in ['once', 'always', 'deny']) {
        expect(
          find.byKey(ValueKey('connector-approval-$action')),
          findsNothing,
        );
      }
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

  testWidgets('narrow approval keeps long details readable with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = NekodotClient();
    client.prefs.language = 'en';
    addTearDown(client.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.dark, glass: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(1.5),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: ConnectorApprovalCard(
              client: client,
              bot: const {
                'displayName': 'My project review assistant',
                'avatar': {'color': '#4682E2', 'shape': 'dot'},
              },
              details: const {
                'title': 'Create an issue in the team project repository',
                'service': {'name': 'GitHub Enterprise'},
                'account': 'Project review account',
                'arguments': {
                  'repository': 'team/project-release-review',
                  'body':
                      'Prepare the release notes and review the open tasks.',
                  'assignees': <String>[],
                },
              },
              pending: true,
              sending: null,
              choices: const ['once', 'deny'],
              result: 'Not answered',
              denied: false,
              unanswered: true,
              onRespond: (_) async {},
              error: '',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('connector-approval-always')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('connector-approval-details')));
    await tester.pumpAndSettle();
    expect(find.text('team/project-release-review'), findsOneWidget);
    expect(find.text('[]'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.byType(AnimatedSize), findsNothing);
  });
}
