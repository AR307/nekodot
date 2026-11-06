import 'package:nekodot_native/data/chat_models.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// Actual MoA inference and native scheduled-job writes from the App composer.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('MoA, blueprints and cron execute through native Hermes', (
    tester,
  ) async {
    if (Platform.isWindows) await DesktopHost.initialize();
    final c = NekodotClient()..prefs.language = 'en';
    final botId = const String.fromEnvironment('QA_BOT');
    final login = await c.account.request(
      '/auth/login',
      method: 'POST',
      body: {
        'email': const String.fromEnvironment('QA_EMAIL'),
        'password': const String.fromEnvironment('QA_PASSWORD'),
      },
    );
    c.account.token = login['token'] as String;
    c.selectedNodeId = const String.fromEnvironment('QA_NODE');
    await c.bootstrap();
    addTearDown(c.dispose);
    Future<void> until(bool Function() ready, String step) async {
      final end = DateTime.now().add(const Duration(minutes: 5));
      while (!ready() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 150));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(ready(), isTrue, reason: step);
    }

    await until(() => c.online, 'Node online');
    final conversationId =
        '${c.node.conversations.firstWhere((r) => r['kind'] == 'dm' && r['botId'] == botId)['conversationId']}';
    runApp(
      MaterialApp(
        theme: appTheme(Brightness.light),
        navigatorObservers: [nativeRoutes],
        home: HomePage(client: c),
      ),
    );
    final chat = find.byKey(ValueKey('conversation-$conversationId'));
    await until(() => chat.hitTestable().evaluate().isNotEmpty, 'Open Bot');
    await tester.tap(chat.hitTestable().first);
    final input = find.byKey(const ValueKey('chat-input'));
    await until(() => input.evaluate().isNotEmpty, 'Composer');
    await c.loadMessages(conversationId);
    List<ChatMessage> messages() => c.node.messages[conversationId] ?? [];
    Future<void> submit(String text, {bool rejected = false}) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(input);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.enterText(input, text);
      await tester.pump(const Duration(milliseconds: 300));
      final send = find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == 'Send' && w.onPressed != null,
      );
      await until(() => send.hitTestable().evaluate().isNotEmpty, 'Send $text');
      await tester.tap(send.hitTestable().first);
      if (rejected) {
        await until(
          () => find
              .textContaining('before starting a one-turn model command')
              .evaluate()
              .isNotEmpty,
          'Busy one-turn command is explicitly refused',
        );
        expect(tester.widget<TextField>(input).controller!.text, text);
        await tester.enterText(input, '');
        await tester.pump(const Duration(milliseconds: 150));
        return;
      }
      await until(
        () => tester.widget<TextField>(input).controller!.text.isEmpty,
        'Command completed: $text',
      );
    }

    Future<void> reply(String marker) async {
      await until(
        () => messages().any(
          (r) =>
              r.kind == 'text' &&
              r.author.type == 'bot' &&
              r.status == 'done' &&
              '${r.content['text']}'.contains(marker),
        ),
        'Actual model reply: $marker',
      );
      await until(
        () => c.node.activities[conversationId]?.state == 'idle',
        'Native task settled',
      );
    }

    Future<List<Json>> routines() async =>
        objects((await c.rpc('routines.list', {'botId': botId}))['routines']);
    final original = (await c.rpc('sessions.list', {
      'botId': botId,
    }))['currentSessionId'];
    final bot = c.node.bots.firstWhere((r) => r['botId'] == botId);
    final source = objects((await c.rpc('providers.list'))['sources'])
        .firstWhere((r) => r['sourceId'] == bot['sourceId']);
    final fields = objects(
      (await c.rpc('hermes.settings.get', {'botId': botId}))['fields'],
    );
    final changes = <String, Object?>{
      'moa.default_preset': 'default',
      'moa.presets.default.reference_models': [
        {
          'provider': source['provider'],
          'model': bot['model'],
          'enabled': true,
        },
      ],
      'moa.presets.default.aggregator.provider': source['provider'],
      'moa.presets.default.aggregator.model': bot['model'],
      'moa.save_traces': true,
    };
    final marker = 'NATIVE_ADVANCED_${DateTime.now().millisecondsSinceEpoch}';
    final jobs = <String>[];
    try {
      for (final entry in changes.entries) {
        await c.rpc('hermes.settings.set', {
          'botId': botId,
          'key': entry.key,
          'value': entry.value,
        });
      }
      await submit('/new $marker');
      await submit(
        '/moa Do not use tools. Consider this harmless arithmetic, 19 + 23, then reply exactly $marker-MOA-42.',
      );
      await until(
        () => c.node.activities[conversationId]?.state != 'idle',
        'MoA is actually running',
      );
      await submit('/moa $marker-DO-NOT-STEER', rejected: true);
      await reply('$marker-MOA-42');
      await submit('Do not use tools. Reply exactly $marker-NORMAL.');
      await reply('$marker-NORMAL');
      final session = await c.rpc('sessions.list', {'botId': botId});
      final moaHistory = await c.rpc('sessions.history', {
        'botId': botId,
        'sessionId': session['currentSessionId'],
      });
      expect(
        '${moaHistory['messages']}',
        isNot(contains('$marker-DO-NOT-STEER')),
      );
      debugPrint('QA ADVANCED: actual MoA reply and following normal turn');

      await submit(
        '/blueprint custom-reminder what="$marker-BLUEPRINT" time=23:59 recurrence=weekends deliver=local',
      );
      final blueprint = (await routines()).firstWhere(
        (r) => '${r['prompt']}'.contains('$marker-BLUEPRINT'),
      );
      jobs.add('${blueprint['cronJobId']}');
      await submit('/cron pause ${jobs.last}');
      final keptBlueprint = (await routines()).firstWhere(
        (r) => r['cronJobId'] == jobs.last,
      );
      expect(keptBlueprint['enabled'], isFalse);
      debugPrint('QA ADVANCED: blueprint created a real native cron job');

      await submit(
        '/cron add "0 0 1 1 *" --name "$marker-CRON" --deliver local --prompt "Do not use tools. Reply exactly $marker-CRON-INITIAL."',
      );
      final cron = (await routines()).firstWhere(
        (r) => r['name'] == '$marker-CRON',
      );
      jobs.add('${cron['cronJobId']}');
      await submit('/cron pause ${jobs.last}');
      await submit(
        '/cron edit ${jobs.last} --prompt "Do not use tools. Reply exactly $marker-CRON-UPDATED."',
      );
      final edited = (await routines()).firstWhere(
        (r) => r['cronJobId'] == jobs.last,
      );
      expect(edited['enabled'], isFalse);
      expect(edited['prompt'], contains('$marker-CRON-UPDATED'));
      await submit('/cron resume ${jobs.last}');
      await submit('/cron run ${jobs.last}');
      final detail = await c.rpc('routines.get', {
        'botId': botId,
        'routineId': cron['routineId'],
      });
      expect(
        detail['routine']['native']['latest_execution']['status'],
        'completed',
      );
      final execution = objects(detail['routine']['native']['runs']).first;
      final history = await c.rpc('sessions.history', {
        'botId': botId,
        'sessionId': execution['id'],
      });
      expect(
        objects(history['messages']).any(
          (r) =>
              r['role'] == 'assistant' &&
              '${r['text'] ?? r['content']}'.contains('$marker-CRON-UPDATED'),
        ),
        isTrue,
      );
      await submit('/cron pause ${jobs.last}');
      debugPrint(
        'QA ADVANCED: native cron create/edit/resume/run/pause passed',
      );
    } finally {
      for (final id in jobs) {
        await submit('/cron pause $id');
      }
      for (final key in changes.keys) {
        await c.rpc('hermes.settings.set', {
          'botId': botId,
          'key': key,
          'value': fields.firstWhere((r) => r['key'] == key)['value'],
        });
      }
      if (c.node.activities[conversationId]?.state == 'idle') {
        await submit('/resume $original');
      }
    }
    binding.reportData = {
      'realHermes': true,
      'realModel': true,
      'moaReply': true,
      'referenceAndAggregatorUseSameConfiguredModel': true,
      'normalTurnAfterMoa': true,
      'busyMoaRefusedWithoutSteer': true,
      'blueprintCreatedNativeJob': true,
      'cronCreateEditResumeRunPause': true,
      'jobsPausedAndPreserved': true,
      'profileSettingsRestored': true,
    };
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 20)));
}
