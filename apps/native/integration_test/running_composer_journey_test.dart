import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/settings.dart';
import 'package:nekodot_native/features/source_models.dart';
import 'package:nekodot_native/main.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('running chat keeps input, reasoning and stop clickable', (
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
    var stage = 'login';
    Future<void> until(bool Function() ready, {int seconds = 120}) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(ready(), isTrue, reason: stage);
    }

    Future<void> click(Finder target) async {
      await until(() => target.evaluate().isNotEmpty);
      await tester.ensureVisible(target);
      await tester.pump(const Duration(milliseconds: 300));
      expect(target.hitTestable(), findsOneWidget, reason: stage);
      final mouse = await tester.startGesture(
        tester.getCenter(target),
        kind: Platform.isAndroid
            ? ui.PointerDeviceKind.touch
            : ui.PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await mouse.up();
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> shot(String name) async {
      await tester.runAsync(() async {
        final picture =
            await (capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = (await picture.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        final dir = Platform.isAndroid
            ? '${(await getExternalStorageDirectory())!.path}/composer-provider-evidence'
            : const String.fromEnvironment('QA_EVIDENCE_DIR');
        await Directory(dir).create(recursive: true);
        await File('$dir/$name.png').writeAsBytes(bytes);
        picture.dispose();
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
    await click(find.byKey(const ValueKey('auth-submit')));
    await until(() => c.connection.ready);
    await tester.runAsync(
      () => c.selectNode(const String.fromEnvironment('QA_NODE')),
    );
    await until(() => c.online && c.node.bots.isNotEmpty);
    const dm = String.fromEnvironment('QA_CONVERSATION');
    await click(find.byKey(const ValueKey('conversation-$dm')));
    final bot = c.node.conversations.firstWhere(
      (v) => v['conversationId'] == dm,
    )['botId'];
    final input = find.byKey(const ValueKey('chat-input'));
    final toggle = find.byKey(const ValueKey('reasoning-toggle'));
    for (final theme
        in const bool.fromEnvironment('QA_SOURCE_ONLY')
            ? <String>[]
            : ['light', 'dark']) {
      final previousIds = (c.node.messages[dm] ?? [])
          .map((m) => m.messageId)
          .toSet();
      await c.prefs.update(appearance: theme);
      stage = '$theme send real task';
      await until(() => toggle.evaluate().isNotEmpty);
      await click(input);
      await tester.enterText(
        input,
        'Use your terminal tool to run a Python command that sleeps for 60 seconds and then prints COMPOSER_LIVE_OK. Do not simulate this.',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await click(find.byTooltip('Send'));
      await until(
        () =>
            c.node.activities[dm]?.state == 'running' ||
            find.byTooltip('Stop').evaluate().isNotEmpty,
      );
      await until(
        () => tester.widget<TextField>(input).controller!.text.isEmpty,
      );
      await until(() => c.node.activities[dm]?.runId != null);
      final activeRun = c.node.activities[dm]!.runId;
      stage = '$theme click running input';
      await click(input);
      expect(
        tester.widget<TextField>(input).focusNode!.hasFocus,
        isTrue,
        reason: stage,
      );
      await tester.enterText(input, '下一条草稿 retained while running');
      await tester.pump(const Duration(milliseconds: 300));
      stage = '$theme adjust reasoning during run';
      await click(toggle);
      await until(
        () =>
            find
                .byKey(const ValueKey('reasoning-slider'))
                .evaluate()
                .isNotEmpty ||
            find.widgetWithText(ListTile, 'low').evaluate().isNotEmpty,
      );
      final desired = theme == 'light' ? 'low' : 'medium';
      await click(
        Platform.isAndroid
            ? find.widgetWithText(ListTile, desired).last
            : find.widgetWithText(TextButton, desired).last,
      );
      await until(
        () =>
            find.byKey(const ValueKey('reasoning-slider')).evaluate().isEmpty &&
            find.widgetWithText(ListTile, 'low').evaluate().isEmpty,
      );
      await until(
        () =>
            tester
                .widget<Text>(find.byKey(const ValueKey('reasoning-current')))
                .data ==
            desired,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('reasoning-current')))
            .data,
        desired,
      );
      await shot('running-composer-$theme');
      stage = '$theme stop original run';
      await click(find.byTooltip('Stop'));
      debugPrint(
        'QA after mouse stop: activity=${c.node.activities[dm]?.toJson()} queue=${c.deliveries.items.map((x) => {'method': x['method'], 'state': x['state'], 'error': x['error']}).toList()}',
      );
      await shot('running-composer-after-stop-$theme');
      await until(() => c.node.activities[dm]?.state == 'idle', seconds: 25);
      expect(
        (c.node.messages[dm] ?? []).any(
          (m) => !previousIds.contains(m.messageId) && m.status == 'cancelled',
        ),
        isTrue,
      );
      debugPrint('QA stopped native admission $activeRun');
      expect(
        tester.widget<TextField>(input).controller!.text,
        '下一条草稿 retained while running',
      );
      await click(input);
      expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
      await tester.enterText(
        input,
        'Only reply with COMPOSER_NEXT_TURN_OK. No tools.',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await click(find.byTooltip('Send'));
      await until(() => find.byTooltip('Stop').evaluate().isNotEmpty);
      await until(() => c.node.activities[dm]?.state == 'idle');
      final reasoning = await tester.runAsync(
        () => c.rpc('models.reasoning.get', {'botId': bot}),
      );
      expect(reasoning!['effort'], desired);
      expect(
        (c.node.messages[dm] ?? []).any(
          (m) =>
              !previousIds.contains(m.messageId) &&
              m.author.type == 'bot' &&
              '${m.content['text']}'.contains('COMPOSER_NEXT_TURN_OK'),
        ),
        isTrue,
      );
      debugPrint(
        'QA $theme mouse input / deferred reasoning / stop / next real turn passed',
      );
    }
    stage = 'custom source protocol picker';
    if (Platform.isAndroid) {
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 400));
    }
    final sources = await tester.runAsync(() => c.rpc('providers.list'));
    final source = objects(sources!['sources'])
        .firstWhere((s) => s['name'] == 'Model Catalog QA');
    if (find.byTooltip('Account').evaluate().isNotEmpty) {
      await click(find.byTooltip('Account'));
      await click(find.text('Settings'));
    } else {
      await click(find.byTooltip('Settings'));
    }
    if (find.text('Model sources').evaluate().isEmpty) {
      await click(find.text('All Bots'));
    }
    await click(find.text('Model sources'));
    await click(find.widgetWithText(ListTile, '${source['name']}').last);
    expect(find.byType(CustomSourcePage), findsOneWidget);
    var currentLabel = source['apiMode'] == 'codex_responses'
        ? 'Responses'
        : 'Chat Completions';
    for (final pair in [
      ('Responses', 'codex_responses'),
      ('Chat Completions', 'chat_completions'),
    ]) {
      await click(find.text(currentLabel).first);
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Gemini · generateContent'), findsOneWidget);
      await shot('protocol-options-${Platform.operatingSystem}');
      await click(find.text(pair.$1).last);
      currentLabel = pair.$1;
      await click(find.text('Save'));
      await until(
        () =>
            tester
                .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
                .onPressed !=
            null,
      );
      await until(
        () => find
            .byKey(const ValueKey('source-model-count'))
            .evaluate()
            .isNotEmpty,
      );
      final saved = await tester.runAsync(() => c.rpc('providers.list'));
      expect(
        objects(saved!['sources'])
            .firstWhere((s) => s['sourceId'] == source['sourceId'])['apiMode'],
        pair.$2,
      );
      await tester.enterText(
        find.byKey(const ValueKey('source-model-search')),
        'gpt-6.1-sol',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await click(find.byKey(const ValueKey('source-model-gpt-6.1-sol')));
      await until(() => find.byType(ModelCapabilities).evaluate().isNotEmpty);
      await tester.pump(const Duration(milliseconds: 300));
      await until(
        () =>
            find.byKey(const ValueKey('source-test')).evaluate().isNotEmpty &&
            tester
                    .widget<TextButton>(
                      find.byKey(const ValueKey('source-test')),
                    )
                    .onPressed !=
                null,
      );
      await click(find.byKey(const ValueKey('source-test')));
      await until(
        () => find.text('Connection test passed').evaluate().isNotEmpty,
      );
      final tested = await tester.runAsync(() => c.rpc('operations.list'));
      final native = objects(tested!['operations']).firstWhere(
        (op) => op['kind'] == 'provider-test',
      )['results'][0]['native'];
      expect(native['apiMode'], pair.$2);
      expect(native['actualModel'], 'gpt-6.1-sol');
      await shot('protocol-${pair.$2}-${Platform.operatingSystem}');
      debugPrint(
        'QA actual native source selection and model call passed: ${pair.$2}',
      );
    }
    expect(tester.takeException(), isNull);
    debugPrint(
      'QA COMPOSER AND PROVIDER JOURNEY PASSED ${Platform.operatingSystem}',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 12)));
}
