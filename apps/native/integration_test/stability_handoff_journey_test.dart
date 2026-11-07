import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/routines.dart';
import 'package:nekodot_native/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

// Real candidate UI + real Relay/Node/Hermes/model. No injected tool events.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('single-field delivery, webhook setup and focus recovery', (
    tester,
  ) async {
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
    const dm = String.fromEnvironment('QA_CONVERSATION');
    const group = String.fromEnvironment('QA_GROUP');
    const work = String.fromEnvironment('QA_WORK_DIR');
    const evidence = String.fromEnvironment('QA_EVIDENCE_DIR');
    Future<void> until(
      bool Function() ready, {
      String what = '',
      int seconds = 240,
    }) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 150));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(ready(), isTrue, reason: what);
    }

    Future<void> tap(Finder f) async {
      await until(() => f.evaluate().isNotEmpty, what: '$f');
      await Scrollable.ensureVisible(tester.element(f.first), alignment: .4);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(f.first);
      await tester.pump(const Duration(milliseconds: 300));
    }

    var surfaceConverted = false;
    Future<void> shot(String name) async {
      await tester.pump(const Duration(milliseconds: 400));
      if (Platform.isWindows) {
        await tester.runAsync(() async {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
          await Directory(evidence).create(recursive: true);
          await File('$evidence/$name.png').writeAsBytes(bytes);
          image.dispose();
        });
      } else {
        if (!surfaceConverted) {
          await binding.convertFlutterSurfaceToImage();
          surfaceConverted = true;
        }
        await tester.pump();
        await binding.takeScreenshot(name);
      }
    }

    Future<void> open(String id) async {
      final input = find.byKey(const ValueKey('chat-input'));
      if (input.evaluate().isNotEmpty && Platform.isAndroid) {
        await tester.pageBack();
        await until(() => input.evaluate().isEmpty);
      }
      await tap(find.byKey(ValueKey('conversation-$id')));
      await tester.runAsync(() => c.loadMessages(id));
    }

    Future<void> send(String text) async {
      final field = find.byKey(const ValueKey('chat-input'));
      await tap(field);
      await tester.enterText(field, text);
      await tap(find.byTooltip('Send'));
      await until(
        () => tester.widget<TextField>(field).controller!.text.isEmpty,
      );
    }

    bool idle(String id) => (c.node.activities[id]?.state ?? 'idle') == 'idle';
    bool result(String id, String marker) => (c.node.messages[id] ?? []).any(
      (m) =>
          m.author.type == 'bot' &&
          m.kind == 'text' &&
          m.status == 'done' &&
          '${m.content['text']}'.contains(marker),
    );
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
    await tester.runAsync(
      () => c.selectNode(const String.fromEnvironment('QA_NODE')),
    );
    await until(() => c.online && idle(dm) && idle(group));
    await open(dm);
    final interruptedCard = (c.node.messages[dm] ?? [])
        .where(
          (m) =>
              m.kind == 'secret' &&
              m.content['state'] == 'pending' &&
              '${m.content['service']}'.startsWith('Handoff-'),
        )
        .firstOrNull;
    final suffix = interruptedCard == null
        ? DateTime.now().millisecondsSinceEpoch
        : int.parse(
            '${interruptedCard.content['service']}'.substring(
              'Handoff-'.length,
            ),
          );
    final marker = 'HANDOFF_KEYS_$suffix';
    final target = '$work/approved-$suffix.env'.replaceAll('\\', '/');
    final spec = {
      'service': 'Handoff-$suffix',
      'purpose': 'Configure two test API fields',
      'fields': [
        {'name': 'FIRST_KEY', 'label': 'First key', 'kind': 'password'},
      ],
      'target': {'kind': 'file', 'path': target, 'format': 'env'},
    };
    if (interruptedCard == null) {
      await send(
        'Read the nekodot-secrets skill. Configure two harmless test API keys in $target using separate confidential cards. First run hermes secret request with this spec JSON (quote correctly for your terminal): ${jsonEncode(spec)}. After delivery request SECOND_KEY with label Second key, same service purpose and target, as the second card. Finish each requesting turn. After both are delivered, use an actual tool to load the approved env file and check both fields are nonempty without printing either value. Reply $marker only after checking. Never ask for either value in chat.',
      );
    }
    // Resume an interrupted UI journey without re-delivering completed fields.
    final pending = (c.node.messages[dm] ?? [])
        .where(
          (m) =>
              m.kind == 'secret' &&
              m.content['service'] == 'Handoff-$suffix' &&
              ['delivered', 'applied'].contains(m.content['state']),
        )
        .map((m) => '${m.content['requestId']}')
        .toList();
    final deliveredCount = pending.length;
    for (final field in ['FIRST_KEY', 'SECOND_KEY']) {
      if ((field == 'FIRST_KEY' ? 0 : 1) < deliveredCount) continue;
      final finder = find.byKey(ValueKey('secret-field-$field'));
      await until(() => finder.evaluate().isNotEmpty, what: 'card $field');
      await until(() => idle(dm), what: 'requesting turn finished');
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.key is ValueKey &&
              '${(w.key as ValueKey).value}'.startsWith('secret-field-'),
        ),
        findsOneWidget,
      );
      final active = (c.node.messages[dm] ?? [])
          .where(
            (m) =>
                m.kind == 'secret' &&
                [
                  'pending',
                  'failed',
                  'redelivery',
                ].contains(m.content['state']),
          )
          .toList();
      expect(active, hasLength(1));
      pending.add('${active.single.content['requestId']}');
      debugPrint('QA handoff: one $field card observed');
      await shot('single-card-$field');
      await tap(finder);
      await tester.enterText(finder, 'harmless-$field-$suffix');
      await tap(find.byKey(const ValueKey('secret-submit')));
      await until(
        () => !finder.evaluate().isNotEmpty,
        what: 'delivered $field',
      );
    }
    await until(
      () => idle(dm) && result(dm, marker),
      what: 'actual config use',
    );
    expect(pending.toSet(), hasLength(2));
    final deliveredMessages = jsonEncode(
      (c.node.messages[dm] ?? []).map((m) => m.content).toList(),
    );
    for (final field in ['FIRST_KEY', 'SECOND_KEY']) {
      expect(deliveredMessages, isNot(contains('harmless-$field-$suffix')));
    }
    if (Platform.isWindows) {
      final saved = await tester.runAsync(() => File(target).readAsString());
      expect(saved, contains('harmless-FIRST_KEY-$suffix'));
      expect(saved, contains('harmless-SECOND_KEY-$suffix'));
    }
    await shot('two-cards-delivered');
    debugPrint('QA handoff: both keys applied and actually read');

    // The actual socket survives ordinary app focus changes while a real RPC is pending.
    final before = Platform.isWindows
        ? File('$work/relay.log')
              .readAsLinesSync()
              .where((l) => l.contains('/ws/client'))
              .length
        : 0;
    await tester.runAsync(() async {
      final rpc = c.rpc('routines.list', {
        'botId': c.node.conversations.firstWhere(
          (v) => v['conversationId'] == dm,
        )['botId'],
      });
      for (var i = 0; i < 3; i++) {
        c.pause();
        c.resume();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await rpc;
    });
    expect(c.connection.ready, isTrue);
    if (Platform.isWindows) {
      expect(
        File('$work/relay.log')
            .readAsLinesSync()
            .where((l) => l.contains('/ws/client'))
            .length,
        before,
      );
    }

    await open(group);
    final name = 'Handoff hook $suffix';
    await send(
      'Create one webhook-only routine named $name using the nekodot-routines skill and hermes routine create. Its fixed prompt is Reply HOOK_$suffix. No cron. Ask me to configure its card and finish. Do not hand off.',
    );
    await until(
      () => (c.node.messages[group] ?? []).any(
        (m) => m.kind == 'routine' && m.content['name'] == name,
      ),
      what: 'webhook card in source group',
    );
    await until(() => idle(group));
    final message = (c.node.messages[group] ?? []).lastWhere(
      (m) => m.kind == 'routine' && m.content['name'] == name,
    );
    final card = find.byWidgetPredicate(
      (w) =>
          w is RoutineCard &&
          w.content['routineId'] == message.content['routineId'],
    );
    await until(() => card.evaluate().isNotEmpty);
    await tap(
      find.descendant(
        of: card,
        matching: find.widgetWithText(TextButton, 'Webhook'),
      ),
    );
    await until(
      () => find.text('Connect & deliver securely').evaluate().isNotEmpty,
    );
    await shot('webhook-configuration');
    await tap(find.text('Connect & deliver securely'));
    final params = {
      'botId': message.content['botId'],
      'routineId': message.content['routineId'],
    };
    Json? details;
    await tester.runAsync(() async {
      details = await c.rpc('routines.get', params);
    });
    expect(object(details!['routine'])['granted'], isTrue);
    await tester.runAsync(() async {
      // External caller against this isolated Relay; production test RPC
      // intentionally requires a public HTTPS deployment. No security override.
      final credentials = await c.rpc('routines.credentials', params);
      final http = HttpClient();
      final request = await http.postUrl(Uri.parse('${credentials['url']}'));
      request.headers.set('Authorization', 'Bearer ${credentials['secret']}');
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('X-Request-ID', 'handoff-$suffix');
      request.write(
        jsonEncode({'event_type': 'test', 'message': 'controlled acceptance'}),
      );
      final response = await request.close();
      expect(response.statusCode, inInclusiveRange(200, 299));
      await response.drain<void>();
      http.close();
    });
    final resultConversation =
        c.node.conversations.firstWhere(
              (v) =>
                  v['kind'] == 'dm' && v['botId'] == message.content['botId'],
            )['conversationId']
            as String;
    await tester.runAsync(() => c.loadMessages(resultConversation));
    await until(
      () => result(resultConversation, 'HOOK_$suffix'),
      what: 'real webhook result returned to owning Bot',
      seconds: 420,
    );
    await shot('webhook-granted');
    await tester.runAsync(() => c.prefs.update(appearance: 'dark'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await shot('webhook-dark');
    binding.reportData = {
      ...?binding.reportData,
      'singleFieldCards': pending.length,
      'actualConfigRead': true,
      'focusPreservedSocket': true,
      'sourceGroupWebhookCard': true,
      'grantedWebhook': true,
      'webhookResultDelivered': true,
      'webhookTransport': 'isolated Relay HTTP, not public HTTPS',
      'realModel': 'gpt-6.1-sol',
    };
    await tester.pumpWidget(const SizedBox());
  }, timeout: const Timeout(Duration(minutes: 15)));
}
