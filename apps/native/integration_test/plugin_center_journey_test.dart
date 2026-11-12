import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/plugin_center.dart';
import 'package:nekodot_native/features/extensions.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

import 'connectors_journey_test.dart' as connectors;
import 'local_desktop_journey_test.dart' show MemoryVault;

void main() {
  connectors.main();
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('plugin center across real profiles, catalogs and MCP', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'language': 'zh',
      'theme': 'light',
    });
    final client = NekodotClient(vault: MemoryVault());
    addTearDown(() async {
      await client.clearSession();
      client.dispose();
    });
    await client.prefs.load();
    await client.acceptSession({
      'token': const String.fromEnvironment('QA_TOKEN'),
    });
    await client.selectNode(const String.fromEnvironment('QA_NODE'));
    if (DesktopHost.supported) {
      await DesktopHost.initialize();
      await windowManager.setTitle('nekodot Plugin Center Preview');
      await windowManager.setSize(const Size(1100, 820));
      await windowManager.show();
    }
    Future<void> frames([int ms = 300]) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }

    Future<void> until(bool Function() ready) async {
      final end = DateTime.now().add(const Duration(minutes: 2));
      while (!ready() && DateTime.now().isBefore(end)) {
        await frames(150);
      }
      expect(ready(), isTrue);
      expect(tester.takeException(), isNull);
    }

    Future<void> shot(String name) async {
      await frames();
      final view = tester.binding.renderViews.first;
      final image = await (view.debugLayer! as OffsetLayer).toImage(
        Offset.zero & view.flutterView.physicalSize,
      );
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      image.dispose();
      if (Platform.isWindows) {
        await File(
          '${const String.fromEnvironment('QA_EVIDENCE_DIR')}/plugin-center-windows-$name.png',
        ).writeAsBytes(bytes);
      } else {
        binding.reportData ??= {};
        (binding.reportData!.putIfAbsent('screenshots', () => <Json>[]) as List)
            .add({
              'screenshotName': 'plugin-center-android-$name',
              'bytes': bytes.toList(),
            });
      }
    }

    Future<void> tab(String kind) async {
      final item = find.byKey(ValueKey('plugin-kind-$kind'));
      if (item.evaluate().isEmpty) {
        await tester.tap(find.byKey(const ValueKey('plugin-kind-menu')));
        await frames();
      }
      await tester.tap(item);
      await frames();
    }

    Future<void> enter(Finder field, String value) async {
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.enterText(field, value);
      FocusManager.instance.primaryFocus?.unfocus();
      await frames(700);
      await until(() => tester.view.viewInsets.bottom == 0);
    }

    Future<void> back() async {
      if (Platform.isAndroid) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.byType(BackButton).last);
      }
      await frames();
    }

    var scale = 1.0;
    Widget app(Brightness brightness) => MaterialApp(
      navigatorObservers: [nativeRoutes],
      debugShowCheckedModeBanner: false,
      theme: appTheme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: scale > 1,
        ),
        child: Ambient(child: child!),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              key: const ValueKey('open-plugin-center'),
              onPressed: () => showPluginCenter(context, client),
              child: const Text('插件中心'),
            ),
          ),
        ),
      ),
    );
    await until(() => client.online && client.node.bots.length >= 2);
    await tester.pumpWidget(app(Brightness.light));
    await tester.tap(find.byKey(const ValueKey('open-plugin-center')));
    await frames();
    await until(
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    expect(
      find.descendant(
        of: find.byType(PluginCenterPage),
        matching: find.text('插件中心'),
      ),
      findsOneWidget,
    );
    await shot('skills');
    final skills = objects(
      (await client.rpc('extensions.list', {'kind': 'skills'}))['entries'],
    );
    final skill = skills.firstWhere(
      (row) => objects(row['states']).any((s) => s['installed'] == true),
    );
    await enter(
      find.byKey(const ValueKey('extension-search-skills')),
      '${skill['name']}',
    );
    await tester.tap(find.byKey(ValueKey('extension-${skill['id']}')));
    await until(() => find.byType(ShiningText).evaluate().isEmpty);
    await shot('skill-detail');
    await tester.tap(find.widgetWithText(FilledButton, '管理'));
    await frames();
    expect(find.byType(ExtensionInstall), findsOneWidget);
    await shot('install');
    await tester.tap(find.widgetWithText(TextButton, '停用'));
    await frames();
    await until(() => find.byType(ShiningText).evaluate().isEmpty);
    final disabled = objects(
      (await client.rpc('extensions.list', {'kind': 'skills'}))['entries'],
    ).firstWhere((row) => row['id'] == skill['id']);
    expect(
      objects(disabled['states']).every((state) => state['enabled'] == false),
      isTrue,
    );
    await tester.tap(find.widgetWithText(TextButton, '启用'));
    await frames();
    await until(() => find.byType(ShiningText).evaluate().isEmpty);
    final enabled = objects(
      (await client.rpc('extensions.list', {'kind': 'skills'}))['entries'],
    ).firstWhere((row) => row['id'] == skill['id']);
    expect(
      objects(enabled['states']).every((state) => state['enabled'] == true),
      isTrue,
    );
    await shot('installed-result');
    await back();
    await back();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('extension-search-skills')),
          )
          .controller!
          .text,
      skill['name'],
    );
    await tab('plugins');
    await until(
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    await shot('plugins');
    await enter(
      find.byKey(const ValueKey('extension-search-plugins')),
      'no-match-plugin-center-qa',
    );
    expect(find.text('未找到插件'), findsOneWidget);
    await shot('empty');
    await tab('mcp');
    await until(
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    final server = find.byKey(const ValueKey('mcp-server-plugin-center-qa'));
    await until(() => server.evaluate().isNotEmpty);
    await shot('mcp');
    await tester.tap(server);
    await frames();
    await tester.tap(find.byKey(const ValueKey('mcp-test')));
    await until(() => find.text('连接测试通过').evaluate().isNotEmpty);
    expect(find.text('read_center_note'), findsOneWidget);
    await shot('mcp-detail');
    await tester.ensureVisible(find.byKey(const ValueKey('mcp-enabled')));
    await tester.tap(find.byKey(const ValueKey('mcp-enabled')));
    await frames();
    await until(
      () => !tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('mcp-enabled')))
          .value,
    );
    await tester.tap(find.byKey(const ValueKey('mcp-enabled')));
    await frames();
    await until(
      () => tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('mcp-enabled')))
          .value,
    );
    await back();
    await tester.tap(find.byKey(const ValueKey('mcp-bot-menu')));
    await frames();
    final other = client.node.bots[1];
    await tester.tap(find.byKey(ValueKey('mcp-bot-${other['botId']}')));
    await frames();
    await until(
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    expect(server, findsNothing);
    final otherServers = objects(
      (await client.rpc('mcp.list', {'botId': other['botId']}))['servers'],
    );
    if (otherServers.isEmpty) expect(find.text('未配置'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mcp-add')));
    await frames();
    await shot('mcp-add');
    final addedName =
        'plugin-center-ui-${Platform.isAndroid ? 'android' : 'windows'}';
    if (!otherServers.any((server) => server['name'] == addedName)) {
      await enter(find.byKey(const ValueKey('mcp-name')), addedName);
      await enter(
        find.byKey(const ValueKey('mcp-url')),
        'http://127.0.0.1:1/mcp',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('mcp-save')));
      await tester.tap(find.byKey(const ValueKey('mcp-save')));
      await until(
        () => find.byKey(const ValueKey('mcp-name')).evaluate().isEmpty,
      );
      await frames();
    } else {
      await back();
    }
    final added = find.byKey(ValueKey('mcp-server-$addedName'));
    await until(() => added.evaluate().isNotEmpty);
    await tester.tap(added);
    await frames();
    await tester.tap(find.byKey(const ValueKey('mcp-test')));
    await until(() => find.text('连接测试失败').evaluate().isNotEmpty);
    await shot('mcp-failure');
    if (tester
        .widget<SwitchListTile>(find.byKey(const ValueKey('mcp-enabled')))
        .value) {
      await tester.tap(find.byKey(const ValueKey('mcp-enabled')));
      await frames();
      await until(
        () => !tester
            .widget<SwitchListTile>(find.byKey(const ValueKey('mcp-enabled')))
            .value,
      );
    }
    await back();
    await tab('skills');
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('extension-search-skills')),
          )
          .controller!
          .text,
      skill['name'],
    );
    await client.prefs.update(locale: 'en');
    scale = 1.4;
    if (DesktopHost.supported) {
      await windowManager.setSize(const Size(520, 820));
    }
    await tester.pumpWidget(app(Brightness.dark));
    await frames();
    await shot('dark-narrow');
    await tester.tap(find.byKey(const ValueKey('plugin-kind-menu')));
    await frames();
    await shot('navigation');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
