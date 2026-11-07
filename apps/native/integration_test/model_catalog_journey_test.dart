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
import 'package:nekodot_native/features/reasoning_slider.dart';
import 'package:nekodot_native/main.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

/// Real candidate widgets -> authenticated Relay -> Node -> official Hermes -> paid model.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'live model inventory, native connection test and reasoning composer',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'language': 'zh',
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
      Future<void> until(bool Function() done, {int seconds = 120}) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!done() && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
        }
        expect(done(), isTrue);
      }

      Future<void> tap(Finder f) async {
        await until(() => f.evaluate().isNotEmpty);
        await tester.ensureVisible(f);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(f);
        await tester.pump(const Duration(milliseconds: 350));
      }

      Future<void> shot(String name) async {
        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(() async {
          final image =
              await (capture.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
          final dir = Platform.isAndroid
              ? '${(await getExternalStorageDirectory())!.path}/model-catalog-evidence'
              : const String.fromEnvironment('QA_EVIDENCE_DIR');
          await Directory(dir).create(recursive: true);
          await File('$dir/$name.png').writeAsBytes(bytes);
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
      await tester.runAsync(
        () => c.selectNode(const String.fromEnvironment('QA_NODE')),
      );
      await until(() => c.online && c.node.bots.isNotEmpty);
      final sources = await tester.runAsync(() => c.rpc('providers.list'));
      final source = objects(sources!['sources'])
          .firstWhere((s) => s['kind'] == 'custom');
      if (find.byTooltip('账户').evaluate().isNotEmpty) {
        await tap(find.byTooltip('账户'));
        await tap(find.text('设置'));
      } else {
        await tap(find.byTooltip('设置'));
      }
      await tap(find.text('模型来源'));
      await tap(find.text('${source['name']}'));
      await until(
        () => find
            .byKey(const ValueKey('source-model-count'))
            .evaluate()
            .isNotEmpty,
      );
      await tap(find.text('保存')); // existing secret remains in Hermes; save must stay and fetch automatically
      await until(
        () =>
            find
                .byKey(const ValueKey('source-model-count'))
                .evaluate()
                .isNotEmpty &&
            tester
                    .widget<Text>(
                      find.byKey(const ValueKey('source-model-count')),
                    )
                    .data !=
                '0 个模型',
      );
      expect(find.byType(CustomSourcePage), findsOneWidget);
      final inventory = await tester.runAsync(
        () => c.rpc('models.options', {'sourceId': source['sourceId']}),
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('source-model-count')))
            .data,
        '${(inventory!['models'] as List).length} 个模型',
      );
      await tester.enterText(
        find.byKey(const ValueKey('source-model-search')),
        'gpt-6.1-sol',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tap(find.byKey(const ValueKey('source-model-gpt-6.1-sol')));
      await until(() => find.byType(ModelCapabilities).evaluate().isNotEmpty);
      expect(
        find.textContaining('low · medium · high · xhigh · max'),
        findsOneWidget,
      );
      await shot('source-catalog-${Platform.operatingSystem}');
      final earlierTests = await tester.runAsync(
        () => c.rpc('operations.list'),
      );
      final earlierSessions = objects(earlierTests!['operations'])
          .where((op) => op['kind'] == 'provider-test')
          .expand((op) => objects(op['results']))
          .map((result) => result['native']?['sessionId'])
          .toSet();
      await tap(find.byKey(const ValueKey('source-test')));
      await until(() => find.text('连通性测试通过').evaluate().isNotEmpty);
      final tested = await tester.runAsync(() => c.rpc('operations.list'));
      final native = objects(tested!['operations']).firstWhere(
        (op) => op['kind'] == 'provider-test',
      )['results'][0]['native'];
      expect(native['provider'], source['provider']);
      expect(native['actualModel'], 'gpt-6.1-sol');
      expect(earlierSessions.contains(native['sessionId']), isFalse);
      await shot('source-connected-${Platform.operatingSystem}');
      debugPrint('QA real source inventory and native model call passed');
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 400));
      const dm = String.fromEnvironment('QA_CONVERSATION');
      await tap(find.byKey(const ValueKey('conversation-$dm')));
      await until(
        () => find
            .byKey(const ValueKey('reasoning-toggle'))
            .evaluate()
            .isNotEmpty,
      );
      final bot = c.node.conversations.firstWhere(
        (v) => v['conversationId'] == dm,
      )['botId'];
      await until(
        () =>
            tester
                .widget<TextButton>(
                  find.byKey(const ValueKey('reasoning-toggle')),
                )
                .onPressed !=
            null,
      );
      await tester.enterText(
        find.byKey(const ValueKey('chat-input')),
        'Only reply with MODEL_CATALOG_LIVE_OK. Do not use tools.',
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('reasoning-slider')), findsNothing);
      await shot('composer-collapsed-${Platform.operatingSystem}');
      await tap(find.byKey(const ValueKey('reasoning-toggle')));
      final slider = find.byKey(const ValueKey('reasoning-slider'));
      await shot('composer-expanded-${Platform.operatingSystem}');
      await tester.tapAt(const Offset(10, 90));
      await tester.pump(const Duration(milliseconds: 200));
      expect(slider, findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chat-input')))
            .controller!
            .text,
        'Only reply with MODEL_CATALOG_LIVE_OK. Do not use tools.',
      );
      await tap(find.byKey(const ValueKey('reasoning-toggle')));
      final rect = tester.getRect(slider);
      final gesture = await tester.startGesture(
        Offset(rect.left + 24, rect.center.dy),
      );
      await gesture.moveTo(Offset(rect.right - 24, rect.center.dy));
      await gesture.up();
      await until(
        () =>
            find.byKey(const ValueKey('reasoning-slider')).evaluate().isEmpty &&
            tester
                    .widget<Text>(
                      find.byKey(const ValueKey('reasoning-current')),
                    )
                    .data ==
                'max',
      );
      final picked = await tester.runAsync(
        () => c.rpc('models.reasoning.get', {'botId': bot}),
      );
      expect(picked!['effort'], 'max');
      expect(picked['wireEffort'], 'max');
      expect(
        tester.getCenter(find.byKey(const ValueKey('composer-attach'))).dx,
        lessThan(
          tester.getCenter(find.byKey(const ValueKey('reasoning-toggle'))).dx,
        ),
      );
      expect(
        tester.getCenter(find.byKey(const ValueKey('reasoning-toggle'))).dx,
        lessThan(tester.getCenter(find.byTooltip('发送')).dx),
      );
      await shot('composer-light-${Platform.operatingSystem}');
      await c.prefs.update(appearance: 'dark');
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await shot('composer-dark-${Platform.operatingSystem}');
      final before = (c.node.messages[dm] ?? [])
          .map((m) => m.messageId)
          .toSet();
      await tap(find.byTooltip('发送'));
      await until(
        () => (c.node.messages[dm] ?? []).any(
          (m) =>
              !before.contains(m.messageId) &&
              m.author.type == 'bot' &&
              m.status == 'done' &&
              '${m.content['text']}'.contains('MODEL_CATALOG_LIVE_OK'),
        ),
        seconds: 240,
      );
      await until(() => c.node.activities[dm]?.state == 'idle');
      await shot('composer-reply-${Platform.operatingSystem}');
      final after = await tester.runAsync(
        () => c.rpc('models.reasoning.get', {'botId': bot}),
      );
      expect(after!['effort'], 'max');
      expect(after['sessionId'], picked['sessionId']);
      await until(() => c.online);
      await tap(find.byKey(const ValueKey('chat-sessions')));
      await tap(find.byKey(const ValueKey('new-native-session')));
      await tap(find.byKey(const ValueKey('create-native-session')));
      await until(
        () => find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty,
      );
      await until(
        () =>
            find
                .byKey(const ValueKey('reasoning-current'))
                .evaluate()
                .isNotEmpty &&
            tester
                    .widget<Text>(
                      find.byKey(const ValueKey('reasoning-current')),
                    )
                    .data ==
                'omit',
      );
      final fresh = await tester.runAsync(
        () => c.rpc('models.reasoning.get', {'botId': bot}),
      );
      expect(fresh!['sessionId'], isNot(after['sessionId']));
      expect(fresh['effort'], isNull);
      await tap(find.byKey(const ValueKey('chat-sessions')));
      final restore = find.byKey(
        ValueKey('switch-session-${after['sessionId']}'),
      );
      await tap(restore);
      await until(
        () => find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty,
      );
      await until(
        () =>
            tester
                .widget<Text>(find.byKey(const ValueKey('reasoning-current')))
                .data ==
            'max',
      );
      debugPrint(
        'QA native session switching restored the selected reasoning level',
      );
      await tester.runAsync(c.connection.connect);
      await until(() => c.online);
      await until(() => find.byType(ReasoningSlider).evaluate().isNotEmpty);
      expect(tester.takeException(), isNull);
      binding.reportData = {
        'platform': Platform.operatingSystem,
        'realModel': 'gpt-6.1-sol',
        'inventoryCount': (inventory['models'] as List).length,
        'nativeConnectionTest': true,
        'draggedEffort': after['effort'],
        'wireEffort': after['wireEffort'],
        'realReply': true,
      };
      debugPrint(
        'QA MODEL CATALOG REAL JOURNEY PASSED ${Platform.operatingSystem}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
