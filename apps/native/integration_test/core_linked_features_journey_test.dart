import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/chat_models.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/data/usage.dart';
import 'package:nekodot_native/features/routines.dart';
import 'package:nekodot_native/features/statistics.dart';
import 'package:nekodot_native/main.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

/// The actual native candidate and the isolated real Node/Relay/Hermes.
/// The configured routine must already have a real completed execution.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('secret delivery, routine follow-up and account statistics', (
    tester,
  ) async {
    if (Platform.isWindows) await DesktopHost.initialize();
    const dm = String.fromEnvironment('QA_CONVERSATION');
    const nodeId = String.fromEnvironment('QA_NODE');
    final evidence = Platform.isAndroid
        ? '${(await getExternalStorageDirectory())!.path}/linked-evidence'
        : const String.fromEnvironment('QA_EVIDENCE_DIR');
    const work = String.fromEnvironment('QA_WORK_DIR');
    SharedPreferences.setMockInitialValues({
      'language': 'en',
      'theme': 'light',
      'notification-requested': true,
    });
    final c = NekodotClient(vault: MemoryVault());
    final capture = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: NekodotApp(client: c),
      ),
    );
    var stage = 'login';
    final passed = <String>[];
    Future<void> until(bool Function() ready, {int seconds = 180}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 120));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(ready(), isTrue, reason: 'Real linked features: $stage');
    }

    Future<void> tap(Finder target) async {
      await until(() => target.evaluate().isNotEmpty, seconds: 30);
      await Scrollable.ensureVisible(
        tester.element(target.first),
        alignment: .35,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(target.first);
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> shot(String name) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        final image =
            await (capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(evidence).create(recursive: true);
        await File('$evidence/$name.png')
            .writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      });
    }

    await until(
      () => find.byKey(const ValueKey('auth-email')).evaluate().isNotEmpty,
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      const String.fromEnvironment('QA_EMAIL'),
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      const String.fromEnvironment('QA_PASSWORD'),
    );
    await tap(find.byKey(const ValueKey('auth-submit')));
    await until(() => c.connection.ready);
    await tester.runAsync(() => c.selectNode(nodeId));
    await until(() => c.online && c.node.conversations.isNotEmpty);
    await tap(find.byKey(ValueKey('conversation-$dm')));
    await tester.runAsync(() => c.loadMessages(dm));
    final botId =
        c.node.conversations.firstWhere(
              (row) => row['conversationId'] == dm,
            )['botId']
            as String;
    List<ChatMessage> messages() => c.node.messages[dm] ?? [];
    Future<void> idle() => until(() => c.node.activities[dm]?.state == 'idle');
    Future<void> send(String text) async {
      final input = find.byKey(const ValueKey('chat-input'));
      await tap(input);
      await tester.enterText(input, text);
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.widget<TextField>(input).controller!.text, text);
      await tap(find.byTooltip('Send'));
      await until(
        () => tester.widget<TextField>(input).controller!.text.isEmpty,
      );
    }

    Future<void> command(String value) async {
      var op = (await tester.runAsync(
        () => c.rpc('commands.execute', {
          'botId': botId,
          'conversationId': dm,
          'command': value,
          'clientMsgId': uid(),
        }),
      ))!;
      while (op['status'] == 'running') {
        await tester.pump(const Duration(milliseconds: 200));
        op = (await tester.runAsync(
          () => c.rpc('operations.get', {'operationId': op['operationId']}),
        ))!;
      }
      expect(op['status'], 'done');
    }

    await idle();
    final original = (await tester.runAsync(
      () => c.rpc('sessions.list', {'botId': botId}),
    ))!['currentSessionId'];
    final marker = 'CORELINKED${DateTime.now().millisecondsSinceEpoch}';
    final first = messages().map((m) => m.messageId).toSet();
    List<ChatMessage> recent() =>
        messages().where((m) => !first.contains(m.messageId)).toList();
    bool replied(String text) => recent().any(
      (m) =>
          m.kind == 'text' &&
          m.author.type == 'bot' &&
          m.status == 'done' &&
          '${m.content['text']}'.contains(text),
    );
    try {
      await command('/new $marker');
      stage = 'real secret request';
      final path = '${work.replaceAll('\\', '/')}/$marker.json';
      final spec = {
        'service': marker,
        'purpose': 'Configure a harmless local regression fixture',
        'fields': [
          {'name': 'api_key', 'label': 'Test API Key', 'kind': 'password'},
        ],
        'target': {'kind': 'file', 'path': path, 'format': 'json'},
      };
      await send(
        'Read the nekodot-secrets skill and create a confidential request using '
        'hermes secret request --spec with this exact JSON: ${jsonEncode(spec)}. '
        'Do not request the value in chat. After creating the card finish this turn. '
        'When delivery resumes the session, respect its reported application state: '
        'do not apply an already-applied reference again. Use execute_code to verify '
        'with Python that the approved JSON file has a nonempty api_key; '
        'print only the boolean, never its value. Reply $marker-APPLIED after success.',
      );
      await until(
        () => recent().any(
          (m) => m.kind == 'secret' && m.content['service'] == marker,
        ),
      );
      await idle();
      await shot('secret-pending');
      final field = find.byKey(const ValueKey('secret-field-api_key'));
      await tap(field);
      final testValue = 'test-only-$marker';
      await tester.enterText(field, testValue);
      await tester.pump();
      expect(
        tester
            .widget<Checkbox>(find.byKey(const ValueKey('secret-save')))
            .value,
        isFalse,
      );
      await tap(find.byKey(const ValueKey('secret-submit')));
      await until(
        () => recent().any(
          (m) =>
              m.kind == 'secret' &&
              m.content['service'] == marker &&
              m.content['state'] == 'applied',
        ),
      );
      await until(() => replied('$marker-APPLIED'));
      await idle();
      // The Windows client shares the fixture host filesystem. Android's runner
      // checks the Node-side file after the journey, not the phone filesystem.
      if (!Platform.isAndroid) {
        final configured = await tester.runAsync(
          () async => jsonDecode(await File(path).readAsString()) as Json,
        );
        expect(configured!['api_key'], testValue);
      }
      expect(
        jsonEncode(recent().map((m) => m.content).toList()).contains(testValue),
        isFalse,
      );
      await shot('secret-applied');
      passed.add(
        'real secret card, encrypted submit, file application and native continuation',
      );

      stage = 'selected webhook result follow-up';
      final routines = objects(
        (await tester.runAsync(
          () => c.rpc('routines.list', {'botId': botId}),
        ))!['routines'],
      );
      final routine = routines.firstWhere(
        (r) => r['name'] == 'Core domain wake',
      );
      final target = {'botId': botId, 'routineId': routine['routineId']};
      final detail = (await tester.runAsync(
        () => c.rpc('routines.get', target),
      ))!;
      final completed = objects(detail['executions'])
          .firstWhere((e) => e['state'] == 'completed');
      final executionIds = objects(detail['executions'])
          .map((e) => e['executionId'])
          .toSet();
      await tap(find.byTooltip('Details'));
      await tap(find.widgetWithText(ListTile, 'Core domain wake'));
      await until(() => find.byType(RoutinePage).evaluate().isNotEmpty);
      await tester.scrollUntilVisible(
        find.byKey(ValueKey(completed['executionId'])),
        400,
        scrollable: find
            .descendant(
              of: find.byType(RoutinePage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tap(find.byKey(ValueKey(completed['executionId'])));
      await tap(
        find.byKey(ValueKey('routine-followup-${completed['executionId']}')),
      );
      expect(
        find.byKey(const ValueKey('routine-followup-chip')),
        findsOneWidget,
      );
      await send(
        'Based only on the selected routine execution record, what number '
        'did it return? Do not rerun the task or use tools. Reply $marker-RESULT and the number.',
      );
      await until(() => replied('$marker-RESULT'));
      await idle();
      expect(
        '${recent().lastWhere((m) => m.kind == 'text' && m.author.type == 'bot').content['text']}',
        contains('899'),
      );
      final after = (await tester.runAsync(
        () => c.rpc('routines.get', target),
      ))!;
      expect(
        objects(after['executions']).map((e) => e['executionId']).toSet(),
        executionIds,
      );
      await shot('routine-followup');
      passed.add(
        'selected real webhook result discussed without rerunning task',
      );

      stage = 'account statistics';
      Navigator.of(tester.element(find.byKey(const ValueKey('chat-input'))))
          .popUntil((route) => route.isFirst);
      await tester.pump(const Duration(milliseconds: 400));
      await tap(find.byTooltip('Settings'));
      await tap(find.byKey(const ValueKey('settings-statistics')));
      await until(() => find.byType(UsageCalendar).evaluate().isNotEmpty);
      await tap(find.byKey(const ValueKey('usage-refresh')));
      await until(
        () =>
            tester
                .widget<IconButton>(find.byKey(const ValueKey('usage-refresh')))
                .onPressed !=
            null,
      );
      final summary = tester
          .widget<UsageCalendar>(find.byType(UsageCalendar))
          .data;
      expect(summary.totals.total, greaterThan(0));
      expect(
        summary.conversations.any((e) => e.entity['kind'] == 'group'),
        isTrue,
      );
      expect(
        summary.routines.any((e) => e.entity['name'] == 'Core domain wake'),
        isTrue,
      );
      expect(
        summary.rows.fold<int>(0, (n, row) => n + row.amount.total),
        summary.totals.total,
      );
      final csv = usageCsv(summary);
      expect(csv.take(3), [239, 187, 191]);
      await tester.runAsync(
        () => File('$evidence/usage.csv').writeAsBytes(csv),
      );
      await shot('statistics-light');
      await tester.pageBack();
      await tap(find.byTooltip('Dark'));
      await tap(find.text('中'));
      await until(() => c.prefs.theme == 'dark' && c.prefs.language == 'zh');
      await tap(find.byKey(const ValueKey('settings-statistics')));
      await until(() => find.byType(UsageCalendar).evaluate().isNotEmpty);
      await until(
        () =>
            Theme.of(tester.element(find.byType(StatisticsPage))).brightness ==
            Brightness.dark,
      );
      expect(find.text('统计'), findsOneWidget);
      await shot('statistics-dark');
      passed.add(
        'live statistics, both categories, CSV aggregate and light/dark presentation',
      );
      stage = 'notification routing';
      c.openNotification({'nodeId': nodeId, 'conversationId': dm});
      await until(
        () =>
            find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty &&
            c.visibleConversation == dm,
      );
      passed.add(
        'notification destination opens its conversation (not OS delivery)',
      );
      debugPrint('QA linked features passed: ${passed.join('; ')}');
    } finally {
      if (c.node.activities[dm]?.state != 'idle') {
        await tester.runAsync(() => c.rpc('runs.stop', {'conversationId': dm}));
        await idle();
      }
      await command('/resume $original');
    }
    binding.reportData = {
      'platform': Platform.operatingSystem,
      'realModel': 'gpt-6.1-sol',
      'fixture': marker,
      'passed': passed,
    };
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 15)));
}
