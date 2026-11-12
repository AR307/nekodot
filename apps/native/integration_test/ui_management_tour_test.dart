import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/auth.dart';
import 'package:nekodot_native/features/bot_details.dart';
import 'package:nekodot_native/features/bot_editor.dart';
import 'package:nekodot_native/features/bot_model.dart';
import 'package:nekodot_native/features/plugin_center.dart';
import 'package:nekodot_native/features/plugin_catalog.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/hermes_settings.dart';
import 'package:nekodot_native/features/pairing.dart';
import 'package:nekodot_native/features/learning.dart';
import 'package:nekodot_native/features/local_setup.dart';
import 'package:nekodot_native/local/runtime.dart';
import 'package:nekodot_native/local/system.dart';
import 'package:nekodot_native/screen/viewer.dart';
import 'package:nekodot_native/features/pets.dart';
import 'package:nekodot_native/features/secrets.dart';
import 'package:nekodot_native/features/settings.dart';
import 'package:nekodot_native/features/source_models.dart';
import 'package:nekodot_native/features/statistics.dart';
import 'package:nekodot_native/features/subscription.dart';
import 'package:nekodot_native/features/updates.dart';
import 'package:nekodot_native/features/user_memory.dart';
import 'package:nekodot_native/features/voice.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

/// Read-only page tour of the real isolated Node and Hermes catalogs.
/// Screenshots prove page rendering, not task execution or external integrations.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native management navigation and real catalog states', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'notification-requested': true});
    final c = NekodotClient(vault: MemoryVault());
    final nav = GlobalKey<NavigatorState>();
    final phone = Platform.isAndroid;
    const focus = String.fromEnvironment('QA_TOUR_FOCUS');
    final device = phone ? 'android' : 'windows';
    var converted = false;
    addTearDown(c.dispose);
    Future<void> frames([int ms = 450]) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 40));
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }

    Future<void> shot(String name) async {
      // Android image-surface capture changes raster performance. Collect the
      // profile run on the original surface; visual coverage is a debug tour.
      if (kProfileMode) return;
      await frames(700);
      expect(tester.takeException(), isNull, reason: name);
      final label = 'ui-management-$device-${c.prefs.theme}-$name';
      if (phone) {
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
          await tester.pump();
        }
        await binding.takeScreenshot(label);
      } else {
        final view = tester.binding.renderViews.first;
        final image = await (view.debugLayer! as OffsetLayer).toImage(
          Offset.zero & view.flutterView.physicalSize,
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        const out = String.fromEnvironment('QA_EVIDENCE_DIR');
        await File('$out/$label.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }
      debugPrint('UI_MANAGEMENT rendered $label');
    }

    Future<void> tap(Finder finder) async {
      await Scrollable.ensureVisible(
        tester.element(finder.first),
        alignment: .5,
      );
      await frames(100);
      await tester.tap(finder.hitTestable().first);
      await frames();
    }

    Future<void> open(
      String name,
      Widget page, {
      bool form = false,
      Future<void> Function()? inspect,
    }) async {
      unawaited(openPage(nav.currentContext!, page, form: form));
      await frames(2000);
      final end = DateTime.now().add(const Duration(seconds: 25));
      while ((find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
              find.byType(ShiningText).evaluate().isNotEmpty) &&
          DateTime.now().isBefore(end)) {
        await frames(250);
      }
      await shot(name);
      if (inspect != null) await inspect();
      nav.currentState!.popUntil((route) => route.isFirst);
      await frames();
    }

    if (!phone) {
      await windowManager.ensureInitialized();
      await windowManager.show();
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
    }
    await c.prefs.update(locale: 'en', appearance: 'light');
    await c.login(
      const String.fromEnvironment('QA_EMAIL'),
      const String.fromEnvironment('QA_PASSWORD'),
    );
    await c.selectNode(const String.fromEnvironment('QA_NODE'));
    final ready = DateTime.now().add(const Duration(seconds: 60));
    while ((!c.online || c.node.bots.isEmpty) &&
        DateTime.now().isBefore(ready)) {
      await frames();
    }
    expect(c.online, isTrue);
    final bot = c.node.bots.first;
    final botId = bot['botId'] as String;
    final group = c.node.groups.first;
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: c.prefs,
        builder: (_, child) => MaterialApp(
          navigatorKey: nav,
          navigatorObservers: [nativeRoutes],
          debugShowCheckedModeBanner: false,
          theme: appTheme(
            c.prefs.theme == 'dark' ? Brightness.dark : Brightness.light,
            glass: phone,
          ),
          builder: (_, child) =>
              phone ? Ambient(child: child!) : WindowChrome(child: child!),
          home: HomePage(client: c),
        ),
      ),
    );
    if (focus == 'responsive' || focus == 'performance') {
      if (focus != 'performance') {
        await open(
          'login-invalid',
          AuthPage(client: c),
          inspect: () async {
            await tap(find.byKey(const ValueKey('auth-submit')));
            await shot('login-validation');
            await tap(find.byKey(const ValueKey('auth-switch-mode')));
            await shot('signup');
            await tap(find.byKey(const ValueKey('auth-switch-mode')));
            await tap(find.text('Forgot password?'));
            await shot('password-reset');
          },
        );
        if (!phone) {
          localRuntime = LocalRuntime(c)..support = await localSupport();
          await open('run-location', RunLocationPage(client: c));
          await open('local-folders', LocalSetupPage(client: c));
          localRuntime!.dispose();
          localRuntime = null;
        }
        await open('screen-capability', ScreenPage(client: c, bot: bot));
      }
      await open(
        'catalog-profile',
        PluginCenterPage(client: c, kind: 'plugins'),
        inspect: () async {
          final catalog = find.byType(PluginCenterPage);
          final entries = find.descendant(
            of: catalog,
            matching: find.byType(PluginTile),
          );
          final search = find.descendant(
            of: catalog,
            matching: find.byType(TextField),
          );
          expect(entries, findsWidgets);
          Future<void> scrollCatalog() async {
            for (var i = 0; i < 8; i++) {
              await tester.fling(
                find.descendant(
                  of: catalog,
                  matching: find.byType(CustomScrollView),
                ),
                Offset(0, i < 4 ? -480 : 480),
                900,
              );
              await frames(500);
            }
          }

          if (kProfileMode) {
            await binding.watchPerformance(
              scrollCatalog,
              reportKey: 'catalog_scroll',
            );
          } else {
            await scrollCatalog();
          }
          if (focus == 'performance') return;
          final context = tester.element(find.byType(PluginCenterPage));
          final surface = MediaQuery.sizeOf(context);
          final density = MediaQuery.devicePixelRatioOf(context);
          tester.view.physicalSize =
              Size(surface.height, surface.width) * density;
          await frames();
          await shot('catalog-landscape');
          tester.view.resetPhysicalSize();
          await frames();
          await tap(search);
          await tester.enterText(search, 'no-ui-refresh-match');
          await frames();
          expect(entries, findsNothing);
          await shot('catalog-empty');
        },
      );
      if (focus == 'performance') {
        debugPrint('UI_MANAGEMENT profile catalog scroll complete');
        await tester.pumpWidget(const SizedBox());
        return;
      }
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await open('settings-large-reduced-motion', SettingsPage(client: c));
      await open('bot-large-reduced-motion', BotEditor(client: c), form: true);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      if (!phone) tester.view.resetPhysicalSize();
      await tester.pumpWidget(const SizedBox());
      return;
    }
    for (final theme in ['light', 'dark']) {
      await c.prefs.update(appearance: theme);
      await shot('home');
      await open('login', AuthPage(client: c));
      await open('password', PasswordPage(client: c), form: true);
      await open('bot-create', BotEditor(client: c), form: true);
      await open('bot-edit', BotEditor(client: c, existing: bot), form: true);
      await open(
        'group-edit',
        BotEditor(client: c, group: true, existing: group),
        form: true,
      );
      await open(
        'bot-details',
        BotDetails(client: c, bot: bot),
        inspect: () async {
          for (final label in ['Memory', 'Files', 'Settings']) {
            await tap(find.text(label));
            await frames(1800);
            await shot('details-${label.toLowerCase()}');
          }
        },
      );
      await open(
        'bot-model',
        BotModelPage(client: c, botId: botId),
        form: true,
      );
      await open('learning', LearningPage(client: c, botId: botId));
      await open('secrets', BotSecretsPage(client: c, botId: botId));
      await open('settings', SettingsPage(client: c));
      if (phone) {
        for (final id in ['account', 'bots', 'app']) {
          await open('settings-$id', SettingsPage(client: c, sectionId: id));
        }
      }
      await open(
        'shared-settings',
        AppPage(
          title: c.tr('共用 Hermes 设置', 'Shared Hermes settings'),
          body: HermesSettings(client: c),
        ),
      );
      await open('sources', SourcesPage(client: c));
      await open('source-edit', CustomSourcePage(client: c), form: true);
      await open(
        'model-catalog',
        AppPage(
          title: c.tr('模型', 'Model'),
          body: PageList(
            children: [
              SourceModels(client: c, sourceId: bot['sourceId'] as String),
            ],
          ),
        ),
      );
      await open(
        'extensions',
        PluginCenterPage(client: c, kind: 'skills'),
        inspect: () async {
          await tap(find.text('Plugins'));
          final end = DateTime.now().add(const Duration(seconds: 25));
          while (find.byType(ShiningText).evaluate().isNotEmpty &&
              DateTime.now().isBefore(end)) {
            await frames(250);
          }
          await shot('plugins');
        },
      );
      await open('user-memory', SharedUserMemoryPage(client: c));
      await open('statistics', StatisticsPage(client: c));
      await open('updates', UpdatesPage(client: c));
      await open('voice', VoicePage(client: c, botId: botId));
      await open('pets', PetsPage(client: c, botId: botId));
      await open('subscription', SubscriptionPage(client: c, botId: botId));
    }
    // A disposable QA pairing code, never a new Node or production pairing.
    await open('pairing', PairingPage(client: c));
    await tester.pumpWidget(const SizedBox());
  });
}
