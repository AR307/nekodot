import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/ui/design.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

// Real native client + isolated Relay/Node/Hermes/model, not a recorded service.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'secret continuation accepts steer, finishes, then creates a session',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'language': 'en',
        'notification-requested': true,
      });
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      final client = NekodotClient(vault: MemoryVault())..prefs.language = 'en';
      addTearDown(client.dispose);
      final capture = GlobalKey();
      Future<void> until(
        bool Function() ready,
        String label, {
        int seconds = 300,
      }) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!ready() && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 150));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 150)),
          );
        }
        expect(ready(), isTrue, reason: label);
      }

      Future<void> tap(Finder finder) async {
        await until(
          () => finder.evaluate().isNotEmpty,
          'Missing control: $finder',
        );
        await Scrollable.ensureVisible(
          tester.element(finder.first),
          alignment: .5,
        );
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(finder.first);
        await tester.pump(const Duration(milliseconds: 200));
      }

      await tester.runAsync(() async {
        final login = await client.account.request(
          '/auth/login',
          method: 'POST',
          body: {
            'email': const String.fromEnvironment('QA_EMAIL'),
            'password': const String.fromEnvironment('QA_PASSWORD'),
          },
        );
        client.account.token = login['token'];
        await client.bootstrap();
        await client.selectNode(const String.fromEnvironment('QA_NODE'));
      });
      await until(
        () => client.online && client.node.bots.isNotEmpty,
        'Real Node online',
      );
      final bot = client.node.bots.firstWhere(
        (b) => b['displayName'] == 'Core Blue',
      );
      final botId = '${bot['botId']}';
      final dm = client.node.conversations.firstWhere(
        (c) => c['kind'] == 'dm' && c['botId'] == botId,
      );
      final id = '${dm['conversationId']}';
      final before = (await tester.runAsync(
        () => client.rpc('sessions.list', {'botId': botId}),
      ))!;
      runApp(
        MaterialApp(
          theme: appTheme(Brightness.light),
          navigatorObservers: [nativeRoutes],
          home: RepaintBoundary(
            key: capture,
            child: HomePage(client: client),
          ),
        ),
      );
      await tap(find.byKey(ValueKey('conversation-$id')));
      final input = find.byKey(const ValueKey('chat-input'));
      await until(() => input.evaluate().isNotEmpty, 'Composer visible');
      final service =
          'Session continuation ${DateTime.now().millisecondsSinceEpoch}';
      final spec = {
        'service': service,
        'purpose': 'Verify session switching after a confidential continuation',
        'fields': [
          {'name': 'QA_VALUE', 'label': 'API Key', 'kind': 'password'},
        ],
        'target': {
          'kind': 'file',
          'path':
              '${const String.fromEnvironment('QA_WORK_DIR')}/session-continuation.env',
          'format': 'env',
        },
      };
      await tester.enterText(
        input,
        'This is an isolated acceptance task. Read the nekodot-secrets skill, then use terminal '
        'to run hermes secret request --spec with this exact metadata JSON: ${jsonEncode(spec)}. '
        'Finish this turn after requesting the card. After I submit the card, use terminal '
        'in the foreground (not background) with timeout 40 to run Python that sleeps 20 seconds '
        'and prints SECRET_STEER_TOOL_OK, exactly once. Do not read or print the secret value. '
        'Then reply SECRET_CONTINUATION_FINISHED. Do not repeat completed tools.',
      );
      await tap(find.byTooltip('Send'));
      await until(
        () => (client.node.messages[id] ?? []).any(
          (m) => m.kind == 'secret' && m.content['service'] == service,
        ),
        'Model created confidential card',
      );
      final card = (client.node.messages[id] ?? []).lastWhere(
        (m) => m.kind == 'secret' && m.content['service'] == service,
      );
      final requestId = '${card.content['requestId']}';
      await until(
        () => client.node.activities[id]?.state == 'idle',
        'Request turn completed',
      );
      final field = find.byKey(const ValueKey('secret-field-QA_VALUE'));
      await until(() => field.evaluate().isNotEmpty, 'Secret input visible');
      await Scrollable.ensureVisible(tester.element(field), alignment: .5);
      await tester.enterText(field, 'harmless-session-acceptance-value');
      await tester.pump();
      await tap(find.byKey(const ValueKey('secret-submit')));
      await until(
        () => (client.node.messages[id] ?? []).any(
          (m) =>
              m.kind == 'tool' &&
              m.status == 'streaming' &&
              jsonEncode(m.content).contains('SECRET_STEER_TOOL_OK'),
        ),
        'Real continuation tool started',
      );
      final runId = client.node.activities[id]?.runId;
      expect(runId, isNotNull);
      await tester.enterText(
        input,
        'Keep the current task. Append SESSION_STEER_OK to the final reply. '
        'Do not rerun the sleep or any earlier completed tool.',
      );
      await tap(find.byTooltip('Send'));
      await until(
        () => (client.node.messages[id] ?? []).any(
          (m) =>
              m.kind == 'text' &&
              m.author.type == 'bot' &&
              m.status == 'done' &&
              '${m.content['text']}'.contains('SESSION_STEER_OK'),
        ),
        'Real steered reply completed',
      );
      await until(
        () => client.node.activities[id]?.state == 'idle',
        'Continuation is idle',
      );
      await tap(find.byKey(const ValueKey('chat-sessions')));
      await tap(find.byKey(const ValueKey('new-native-session')));
      await tester.enterText(
        find.byKey(const ValueKey('native-session-title')),
        'Secret continuation regression',
      );
      await tap(find.byKey(const ValueKey('create-native-session')));
      await until(
        () => input.evaluate().isNotEmpty,
        'New session returned to chat',
      );
      final after = (await tester.runAsync(
        () => client.rpc('sessions.list', {'botId': botId}),
      ))!;
      expect(after['currentSessionId'], isNot(before['currentSessionId']));
      expect(find.textContaining('Finish or stop this Bot'), findsNothing);
      final history = (await tester.runAsync(
        () => client.rpc('sessions.history', {
          'botId': botId,
          'sessionId': after['currentSessionId'],
        }),
      ))!;
      expect(history['messages'], isEmpty);
      await tester.runAsync(() async {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
        const root = String.fromEnvironment('QA_EVIDENCE_DIR');
        await Directory(root).create(recursive: true);
        await File('$root/secret-continuation-new-session.png')
            .writeAsBytes(bytes);
        await File('$root/secret-continuation-new-session.json').writeAsString(
          jsonEncode({
            'botId': botId,
            'conversationId': id,
            'requestId': requestId,
            'runId': runId,
            'beforeSession': before['currentSessionId'],
            'afterSession': after['currentSessionId'],
            'newSessionEmpty': true,
            'model': bot['model'],
          }),
        );
        image.dispose();
      });
    },
  );
}
