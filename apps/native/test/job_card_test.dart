import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/job_card.dart';
import 'package:nekodot_native/ui/design.dart';

class JobClient extends NekodotClient {
  final stops = <String>[];
  JobClient() {
    prefs.language = 'en';
    selectedNodeId = 'node';
    connection.ready = true;
    node.online = true;
  }
  @override
  Future<Json> rpc(
    String method, [
    Json params = const {},
    String? target,
  ]) async {
    if (method != 'jobs.stop') throw StateError('Unexpected request: $method');
    stops.add('${params['messageId']}');
    return {};
  }
}

Future<void> show(WidgetTester tester, NekodotClient client, Json content) =>
    tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 480,
              child: JobCard(
                client: client,
                messageId: 'job-1',
                content: content,
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  test('time reads as a clock', () {
    expect(jobClock(37), '0:37');
    expect(jobClock(67), '1:07');
    expect(jobClock(3723), '1:02:03');
  });

  testWidgets(
    'a running job shows how far, how fast and how long is left, and stops on a second tap',
    (tester) async {
      final client = JobClient();
      await show(tester, client, {
        'botId': 'nk-abcdef',
        'label': 'Collecting pages',
        'state': 'running',
        'done': '450',
        'total': '1000',
        'percent': 45,
        'rate': '14.95it/s',
        'etaSeconds': 37,
      });
      await tester.pumpAndSettle();
      expect(find.text('Collecting pages'), findsOneWidget);
      expect(find.text('45%'), findsOneWidget);
      expect(find.text('450 / 1000'), findsOneWidget);
      expect(find.text('14.95it/s'), findsOneWidget);
      expect(find.text('0:37 left'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(.45, .001));

      await tester.tap(find.byKey(const ValueKey('job-stop-job-1')));
      await tester.pump();
      expect(client.stops, isEmpty);
      expect(find.text('Confirm stop'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('job-stop-job-1')));
      await tester.pump();
      expect(client.stops, ['job-1']);
    },
  );

  testWidgets('a job without a total still moves, with no stop while offline', (
    tester,
  ) async {
    final client = JobClient()..node.online = false;
    await show(tester, client, {
      'botId': 'nk-abcdef',
      'label': 'Scraping',
      'state': 'running',
      'done': '450',
      'rate': '14.95it/s',
    });
    expect(find.text('450'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('job-stop-job-1')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('an ended job folds to one line saying how it ended', (
    tester,
  ) async {
    final client = JobClient();
    await show(tester, client, {
      'botId': 'nk-abcdef',
      'label': 'Collecting pages',
      'state': 'done',
      'done': '1000',
      'total': '1000',
      'percent': 100,
      'elapsedSeconds': 67,
      'exitCode': 0,
    });
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('1000 / 1000'), findsOneWidget);
    expect(find.text('took 1:07'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('job-stop-job-1')), findsNothing);

    await show(tester, client, {
      'botId': 'nk-abcdef',
      'label': 'collect.py',
      'state': 'failed',
      'elapsedSeconds': 5,
      'exitCode': 1,
    });
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('exit code 1'), findsOneWidget);
  });
}
