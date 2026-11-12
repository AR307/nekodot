import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/settings.dart';
import 'package:nekodot_native/features/spaces.dart';
import 'package:nekodot_native/features/space_webview.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

// Reuses the actual Dot-generated site and existing isolated services. This
// journey neither regenerates content nor writes practice records or settings.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('A3 menus keep a real Space visible and preserve its page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final c = NekodotClient(vault: MemoryVault());
    final phone = Platform.isAndroid;
    final navigator = GlobalKey<NavigatorState>();
    final platform = phone ? 'android' : 'windows';
    addTearDown(c.dispose);
    Future<void> frames([int ms = 600]) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 40));
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }

    Future<void> until(bool Function() ready, String label) async {
      final end = DateTime.now().add(const Duration(minutes: 2));
      while (!ready() && DateTime.now().isBefore(end)) {
        await frames(150);
      }
      expect(ready(), isTrue, reason: label);
    }

    Future<void> tap(Finder target) async {
      await tester.ensureVisible(target.hitTestable().first);
      await tester.tap(target.hitTestable().first);
      await frames();
      expect(tester.takeException(), isNull);
    }

    Future<void> shot(String label) async {
      await frames();
      final name = 'menu-$platform-$label';
      if (phone) {
        final response = await http.post(
          Uri.parse(
            '${const String.fromEnvironment('QA_CONTROL')}/screenshot?name=$name',
          ),
        );
        expect(response.statusCode, 200);
      } else {
        final view = tester.binding.renderViews.first;
        final image = await (view.debugLayer! as OffsetLayer).toImage(
          Offset.zero & view.flutterView.physicalSize,
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${const String.fromEnvironment('QA_EVIDENCE_DIR')}/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }
    }

    Future<void> dismissMenu() async {
      if (phone) {
        debugPrint('MENU OS back probe ready');
        await Future<void>.delayed(const Duration(seconds: 1));
        expect(
          tester.binding.lifecycleState,
          AppLifecycleState.resumed,
          reason: 'system back closes a menu without backgrounding the app',
        );
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      }
      await frames();
      expect(find.byType(MenuCard), findsNothing);
    }

    if (!phone) {
      await DesktopHost.initialize();
      await windowManager.setTitle('nekodot Menu Space QA');
      await windowManager.setSize(const Size(1200, 850));
    }
    await c.prefs.update(locale: 'zh', appearance: 'light');
    await c.login(
      const String.fromEnvironment('QA_EMAIL'),
      const String.fromEnvironment('QA_PASSWORD'),
    );
    await c.selectNode(const String.fromEnvironment('QA_NODE'));
    await until(
      () => c.online && c.node.spaces.isNotEmpty,
      'real Node connected',
    );
    final space = c.node.spaces.values.firstWhere(
      (s) => s.name == 'Space Study QA',
    );
    final before = await c.rpc('spaces.data.read', {'spaceId': space.spaceId});
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: c.prefs,
        builder: (_, _) => MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [nativeRoutes],
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
    await frames(1200);
    navigator.currentState!.popUntil((route) => route.isFirst);
    await frames();
    await tap(find.text('空间').first);
    await tap(find.text(space.name).first);
    await until(
      () => find.byType(SpaceWebView).evaluate().isNotEmpty,
      'actual WebView mounted',
    );
    await frames(4000);
    final dynamic page = tester.state(find.byType(SpaceWebView));
    final view = page.controller as InAppWebViewController;
    final setup = await view.callAsyncJavaScript(
      functionBody: '''
      await window.nekodotSpace.ready;
      window.menuProbe = {instance: performance.timeOrigin, states: [], events: 0, times: []};
      document.addEventListener('visibilitychange', () => menuProbe.states.push(document.visibilityState));
      window.addEventListener('nekodotspacechange', () => menuProbe.events++);
      window.menuClock = setInterval(() => menuProbe.times.push(Date.now()), 100);
      window.scrollTo(0, 120);
      return {title: document.title, instance: menuProbe.instance};
    ''',
    );
    expect(setup?.error, isNull);
    expect(setup?.value['title'], isNotEmpty);
    await frames();
    final scroll = await view.evaluateJavascript(source: 'scrollY');
    Future<void> visible(String label) async {
      final result = await view.evaluateJavascript(
        source: '({instance:performance.timeOrigin, visibility:document.visibilityState, scroll:scrollY})',
      );
      expect(result['instance'], setup!.value['instance'], reason: label);
      expect(result['visibility'], 'visible', reason: label);
      expect(result['scroll'], scroll, reason: label);
      expect(page.visible, isTrue, reason: label);
      debugPrint('MENU verified $label: $result');
    }

    await tap(find.byKey(const ValueKey('space-menu')));
    expect(find.byType(BottomSheet), findsNothing);
    final menuBounds = tester.getRect(find.byType(MenuCard));
    expect(menuBounds.width, 280);
    expect(menuBounds.height, lessThan(240));
    await visible('Space menu does not hide or reload the page');
    await shot('space-open');
    await tap(find.text('重命名'));
    await visible('rename dialog keeps the page visible');
    await shot('rename');
    await tap(find.text('取消'));
    await visible('cancel retains scroll and page instance');
    await c.prefs.update(locale: 'en', appearance: 'dark');
    await frames();
    await tap(find.byKey(const ValueKey('space-menu')));
    await visible('English dark menu keeps the page visible');
    await shot('space-dark-en');
    await dismissMenu();
    await c.prefs.update(locale: 'zh', appearance: 'light');
    await frames();

    // Open the actual full-page settings route, not a synthetic RouteAware
    // signal. Only opaque coverage must pause the underlying WebView.
    unawaited(
      pushPage(tester.element(find.byType(SpacePage)), SettingsPage(client: c)),
    );
    await frames(1200);
    expect(page.visible, isFalse, reason: 'fully covered Space pauses');
    navigator.currentState!.pop();
    await frames(1200);
    await visible('return from full page resumes the same instance');
    final covered = await view.evaluateJavascript(source: 'menuProbe.states');
    expect(covered, contains('hidden'));
    expect(covered, contains('visible'));
    await view.evaluateJavascript(
      source: 'menuProbe.states=[]; menuProbe.times=[];',
    );
    await frames(500);
    if (phone) {
      // The existing external QA runner sends actual Android Home and resume.
      debugPrint('SPACE OS background probe ready');
      await Future<void>.delayed(const Duration(seconds: 8));
    } else {
      await windowManager.minimize();
      await Future<void>.delayed(const Duration(seconds: 3));
      await windowManager.restore();
      await windowManager.show();
    }
    await frames(1200);
    await visible('OS background then restore resumes the same instance');
    final background = await view.evaluateJavascript(
      source: '''
      ({states:menuProbe.states, events:menuProbe.events,
        maxTimerGap:Math.max(0,...menuProbe.times.slice(1).map((t,i)=>t-menuProbe.times[i]))})
    ''',
    );
    debugPrint('MENU real OS background observation $background');
    expect(background['states'], contains('hidden'));
    expect(background['states'], contains('visible'));
    await view.evaluateJavascript(source: 'clearInterval(menuClock)');
    await shot('space-restored');
    final after = await c.rpc('spaces.data.read', {'spaceId': space.spaceId});
    expect(
      after,
      before,
      reason: 'menu journey never modifies practice records',
    );

    await tap(find.byTooltip('返回'));
    await tap(find.byTooltip('电脑'));
    await shot('computer');
    await dismissMenu();
    await tap(find.text('Dot').first);
    await tap(find.byTooltip('新建'));
    await shot('create');
    await tap(find.text('新建空间'));
    await tap(find.byType(MenuSelect<String>));
    await shot('space-dot-choice');
    final choice = find.byType(MenuChoice).last;
    await tap(choice);
    expect(find.byType(CreateSpacePage), findsOneWidget);
    navigator.currentState!.pop();
    await frames();
    if (!phone) {
      await tap(find.byTooltip('账户'));
      await shot('account');
      await dismissMenu();
    }
    expect(tester.takeException(), isNull);
    debugPrint(
      'MENU completed real $platform journey without model or record writes',
    );
  });
}
