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
  testWidgets('a running turn keeps the input and reasoning level usable', (
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
      await tester.tap(target);
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
    stage = 'conversation opens its composer';
    await until(() => input.hitTestable().evaluate().isNotEmpty);
    final toggle = find.byKey(const ValueKey('reasoning-toggle'));
    Future<Json> reasoning() async => (await tester.runAsync(
      () => c.rpc('models.reasoning.get', {'botId': bot}),
    ))!;
    String? shownLevel() => tester
        .widget<Text>(find.byKey(const ValueKey('reasoning-current')))
        .data;
    bool working() => (c.node.activities[dm]?.state ?? 'idle') != 'idle';
    final sourceOnly = const bool.fromEnvironment('QA_SOURCE_ONLY');
    final original = sourceOnly ? null : (await reasoning())['effort'];
    debugPrint('QA conversation composer visible; reasoning loaded');
    for (final theme in sourceOnly ? <String>[] : ['light', 'dark']) {
      final previousIds = (c.node.messages[dm] ?? [])
          .map((m) => m.messageId)
          .toSet();
      bool replied(String marker) => (c.node.messages[dm] ?? []).any(
        (m) =>
            !previousIds.contains(m.messageId) &&
            m.author.type == 'bot' &&
            m.status == 'done' &&
            '${m.content['text']}'.contains(marker),
      );
      await c.prefs.update(appearance: theme);
      stage = '$theme send a long real turn';
      await until(() => toggle.evaluate().isNotEmpty);
      await click(input);
      await tester.enterText(
        input,
        'Answer this yourself in the chat, without tools or delegation: write about 500 words on how tides work, then end with the exact line COMPOSER_LONG_OK.',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await click(find.byTooltip('Send'));
      await until(working);
      await until(
        () => tester.widget<TextField>(input).controller!.text.isEmpty,
      );
      stage = '$theme type the next draft during the turn';
      await click(input);
      expect(
        tester.widget<TextField>(input).focusNode!.hasFocus,
        isTrue,
        reason: stage,
      );
      await tester.enterText(input, '下一条草稿 retained while running');
      await tester.pump(const Duration(milliseconds: 300));
      stage = '$theme change reasoning during the turn';
      await click(toggle);
      await until(
        () =>
            find
                .byKey(const ValueKey('reasoning-slider'))
                .evaluate()
                .isNotEmpty ||
            find.text('Low').evaluate().isNotEmpty,
      );
      final desired = theme == 'light' ? 'low' : 'medium';
      final desiredLabel = theme == 'light' ? 'Low' : 'Medium';
      await click(find.text(desiredLabel).hitTestable().last);
      await until(
        () =>
            find.byKey(const ValueKey('reasoning-slider')).evaluate().isEmpty &&
            find.text(desiredLabel).hitTestable().evaluate().length <= 1,
      );
      await until(() => shownLevel() == desiredLabel);
      // The level must have been accepted while the turn was still running.
      expect(working(), isTrue, reason: stage);
      await shot('running-composer-$theme');
      stage = '$theme the running turn completes on its own';
      await until(() => !working(), seconds: 300);
      expect(replied('COMPOSER_LONG_OK'), isTrue, reason: stage);
      expect(
        tester.widget<TextField>(input).controller!.text,
        '下一条草稿 retained while running',
      );
      stage = '$theme level applies after the turn';
      await until(() => shownLevel() == desiredLabel);
      expect((await reasoning())['effort'], desired, reason: stage);
      await shot('running-composer-after-turn-$theme');
      stage = '$theme next real turn';
      await click(input);
      expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
      await tester.enterText(
        input,
        'Only reply with COMPOSER_NEXT_TURN_OK. No tools.',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await click(find.byTooltip('Send'));
      await until(() => replied('COMPOSER_NEXT_TURN_OK'), seconds: 300);
      await until(() => !working());
      debugPrint(
        'QA $theme input / deferred reasoning / uninterrupted turn / next real turn passed',
      );
    }
    if (!sourceOnly) {
      final current = await reasoning();
      await tester.runAsync(
        () => c.rpc('models.reasoning.set', {
          'botId': bot,
          'sessionId': current['sessionId'],
          'effort': original,
        }),
      );
    }
    stage = 'custom source protocol picker';
    if (Platform.isAndroid) {
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 400));
    }
    final sources = await tester.runAsync(() => c.rpc('providers.list'));
    const sourceId = String.fromEnvironment('QA_SOURCE');
    final source = objects(sources!['sources']).firstWhere(
      (s) => sourceId.isEmpty
          ? s['name'] == 'Model Catalog QA'
          : s['sourceId'] == sourceId,
    );
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
