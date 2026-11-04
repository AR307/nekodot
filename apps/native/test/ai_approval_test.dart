import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/ui/ai_approval.dart';
import 'package:nekodot_native/ui/design.dart';

const options = [
  AIApprovalOption(
    id: 'once',
    label: 'Allow once',
    resultLabel: 'Allowed once',
    detail: 'Only this operation',
  ),
  AIApprovalOption(id: 'deny', label: 'Deny', destructive: true),
];

Widget host(AIApproval card) => MaterialApp(
  theme: appTheme(Brightness.light),
  home: Scaffold(body: SingleChildScrollView(child: card)),
);

void main() {
  testWidgets('optional callback supports standalone decisions', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const AIApproval(question: 'Run?', options: options)),
    );
    await tester.tap(find.text('Allow once'));
    await tester.pumpAndSettle();
    expect(find.text('Allowed once'), findsOneWidget);
    expect(find.text('Deny'), findsNothing);
  });

  testWidgets(
    'waits for submission, blocks duplicates and collapses on success',
    (tester) async {
      final request = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        host(
          AIApproval(
            question: 'Run this operation?',
            options: options,
            onDecide: (_) {
              calls++;
              return request.future;
            },
          ),
        ),
      );
      await tester.tap(find.text('Allow once'));
      await tester.pump();
      await tester.tap(find.text('Deny'));
      expect(calls, 1);
      expect(find.text('Allowed once'), findsNothing);
      request.complete();
      await tester.pumpAndSettle();
      expect(find.text('Allowed once'), findsOneWidget);
      expect(find.text('Only this operation'), findsOneWidget);
      expect(find.text('Deny'), findsNothing);
    },
  );

  testWidgets('failed submission leaves choices available for retry', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      host(
        AIApproval(
          question: 'Run this operation?',
          options: options,
          onDecide: (_) async {
            if (++calls == 1) throw Exception('Connection lost');
          },
        ),
      ),
    );
    await tester.tap(find.text('Allow once'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Connection lost'), findsOneWidget);
    expect(find.text('Deny'), findsOneWidget);
    await tester.tap(find.text('Allow once'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Allowed once'), findsOneWidget);
  });

  testWidgets('external decision and stopped history never offer choices', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      host(
        const AIApproval(
          question:
              'Run a long operation with a very long command and description?',
          options: options,
        ),
      ),
    );
    await tester.pumpWidget(
      host(
        const AIApproval(
          question:
              'Run a long operation with a very long command and description?',
          options: options,
          resolvedId: 'deny',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Allow once'), findsNothing);
    expect(find.text('Deny'), findsOneWidget);
    await tester.pumpWidget(
      host(
        const AIApproval(
          question: 'Run?',
          options: options,
          resolvedLabel: 'Stopped',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Stopped'), findsOneWidget);
    expect(find.text('Deny'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
