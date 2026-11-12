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
import 'package:nekodot_native/features/extensions.dart';
import 'package:nekodot_native/features/connectors.dart';
import 'package:nekodot_native/features/connector_authorization.dart';
import 'package:nekodot_native/features/connector_service.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

// Real isolated Relay + Composio. No fake catalog, OAuth grants or third-party writes.
// This creates and cancels only its own unapproved Notion authorization.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('classified catalog, service detail and pending cancellation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'language': 'zh',
      'theme': 'light',
    });
    final client = NekodotClient(vault: MemoryVault());
    addTearDown(client.dispose);
    await client.acceptSession({
      'token': const String.fromEnvironment('QA_TOKEN'),
    });
    client.selectedNodeId = null;
    if (DesktopHost.supported) {
      await DesktopHost.initialize();
      await windowManager.setTitle('nekodot Connector Journey');
      await windowManager.setSize(const Size(980, 800));
      await windowManager.show();
    }
    Future<void> frames([int ms = 300]) async {
      final until = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(until)) {
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

    Future<void> loaded() =>
        until(() => find.byType(CircularProgressIndicator).evaluate().isEmpty);
    var androidSurface = false;
    Future<void> shot(String name) async {
      await frames();
      if (Platform.isWindows) {
        final view = tester.binding.renderViews.first;
        final image = await (view.debugLayer! as OffsetLayer).toImage(
          Offset.zero & view.flutterView.physicalSize,
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${const String.fromEnvironment('QA_EVIDENCE_DIR')}/catalog-windows-$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      } else if (Platform.isAndroid) {
        if (!androidSurface) {
          await binding.convertFlutterSurfaceToImage();
          androidSurface = true;
          await frames();
        }
        await binding.takeScreenshot('catalog-android-$name');
      }
    }

    Widget page(Brightness brightness) => MaterialApp(
      navigatorObservers: [nativeRoutes],
      debugShowCheckedModeBanner: false,
      theme: appTheme(brightness),
      builder: (context, child) => Ambient(child: child!),
      home: ExtensionsPage(client: client, kind: 'connectors'),
    );
    Finder service(String id) => find.byKey(ValueKey('connector-service-$id'));
    Future<void> searchCatalog(String value) async {
      await until(() => find.byType(ConnectorServicePage).evaluate().isEmpty);
      final field = find.descendant(
        of: find.byType(ConnectorsBody),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(field);
      await tester.tap(field);
      await frames(100);
      await tester.enterText(field, value);
      await frames(400);
      expect(tester.widget<TextField>(field).controller!.text, value);
    }

    await tester.pumpWidget(page(Brightness.light));
    await until(() => service('github').evaluate().isNotEmpty);
    await loaded();
    expect(find.textContaining('已连接账号'), findsNothing);
    expect(find.byType(ConnectorAuthorizationView), findsNothing);
    await frames(1800);
    await shot('directory-light');

    final category = find.byKey(
      const ValueKey('connector-category-developer-tools'),
    );
    if (category.evaluate().isNotEmpty) {
      await tester.tap(category);
    } else {
      await tester.tap(find.byTooltip('更多'));
      await frames();
      await shot('category-menu');
      await tester.tap(
        find.descendant(
          of: find.byType(MenuChoice),
          matching: find.text('Developer Tools'),
        ),
      );
    }
    await frames();
    await loaded();
    await shot('category');
    await tester.ensureVisible(service('github'));
    await tester.tap(service('github'));
    await frames();
    await loaded();
    expect(find.byType(ConnectorServicePage), findsOneWidget);
    final list = await client.account.request('/connectors/connections');
    final count = objects(list['connections'])
        .where(
          (row) =>
              row['service']['serviceId'] == 'github' &&
              row['status'] == 'active',
        )
        .length;
    expect(find.text('已连接账号 · $count'), findsOneWidget);
    expect(find.textContaining('可用工具'), findsOneWidget);
    await shot('detail-light');

    await tester.tap(find.byTooltip('更多').first);
    await frames();
    expect(find.text('账号备注'), findsOneWidget);
    expect(find.text('重新授权'), findsOneWidget);
    await shot('account-menu');
    await tester.tap(find.text('账号备注'));
    await frames();
    await tester.tap(find.text('取消'));
    await frames();
    final toolsSearch = find.byType(TextField).first;
    await tester.ensureVisible(toolsSearch);
    await tester.enterText(toolsSearch, 'issue');
    await frames(400);
    await loaded();
    await shot('tools-search');
    await tester.pageBack();
    await frames();
    await searchCatalog('notion');
    await until(() => service('notion').evaluate().isNotEmpty);
    await loaded();
    // A real unapproved request, without opening/accepting OAuth in the system browser.
    final pendingRequests = await client.account.request(
      '/connectors/connections',
    );
    final auth =
        objects(pendingRequests['authorizations'])
            .where((row) => row['service']['serviceId'] == 'notion')
            .firstOrNull ??
        await client.account.request(
          '/connectors/authorizations',
          method: 'POST',
          body: {'serviceId': 'notion'},
        );
    await tester.tap(service('notion'));
    await frames();
    await loaded();
    await until(
      () => find.byType(ConnectorAuthorizationView).evaluate().isNotEmpty,
    );
    final pending = find.byKey(ValueKey(auth['authorizationId']));
    await Scrollable.ensureVisible(tester.element(pending), alignment: .35);
    await shot('pending');
    final refresh = find.descendant(of: pending, matching: find.text('刷新'));
    final cancel = find.descendant(of: pending, matching: find.text('取消'));
    await tester.tap(refresh);
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(
            find.ancestor(of: cancel, matching: find.byType(TextButton)).first,
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(cancel);
    await until(
      () => find.byKey(ValueKey(auth['authorizationId'])).evaluate().isEmpty,
    );
    final result = await client.account.request(
      '/connectors/authorizations/${auth['authorizationId']}',
    );
    expect(result['status'], 'cancelled');
    final after = await client.account.request('/connectors/connections');
    expect(
      objects(after['connections'])
          .any((row) => row['connectionId'] == auth['connectionId']),
      isFalse,
    );
    await shot('cancelled');
    await tester.pageBack();
    await frames();
    await tester.tap(service('notion'));
    await frames();
    await loaded();
    expect(find.byKey(ValueKey(auth['authorizationId'])), findsNothing);
    await tester.pageBack();
    await frames();
    await searchCatalog('zzzznekodotnomatch');
    await loaded();
    await shot('empty');
    await until(() => find.text('未找到服务').evaluate().isNotEmpty);
    await searchCatalog('');
    await loaded();
    await client.prefs.update(locale: 'en');
    await tester.pumpWidget(page(Brightness.dark));
    await frames();
    await shot('directory-dark-en');
    if (DesktopHost.supported) {
      await windowManager.setSize(const Size(480, 800));
      await frames();
      await shot('narrow');
    }
    await tester.ensureVisible(service('github'));
    await tester.tap(service('github'));
    await frames();
    await loaded();
    expect(find.text('Connected accounts · $count'), findsOneWidget);
    await shot('detail-dark-en');
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await frames();
    expect(find.byType(ConnectorsBody), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    debugPrint(
      'CONNECTOR CATALOG real provider directory, detail, cancellation and account scope passed',
    );
  });
}
