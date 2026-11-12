import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/plugin_center.dart';
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
    addTearDown(() async {
      await client.clearSession();
      client.dispose();
    });
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
    Future<void> closeKeyboard() async {
      FocusManager.instance.primaryFocus?.unfocus();
      await frames(700);
      await until(() => tester.view.viewInsets.bottom == 0);
    }

    Future<void> shot(String name) async {
      await frames();
      // Both clients are Flutter-only here. Capture their actual render layer
      // without converting Android's live SurfaceView into an ImageView.
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
          '${const String.fromEnvironment('QA_EVIDENCE_DIR')}/catalog-ui-windows-$name.png',
        ).writeAsBytes(bytes);
      } else if (Platform.isAndroid) {
        binding.reportData ??= {};
        (binding.reportData!.putIfAbsent('screenshots', () => <Json>[]) as List)
            .add({
              'screenshotName': 'catalog-ui-android-$name',
              'bytes': bytes.toList(),
            });
      }
    }

    var scale = 1.0;
    Widget page(Brightness brightness) => MaterialApp(
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
      home: PluginCenterPage(client: client, kind: 'connectors'),
    );
    Finder service(String id) => find.byKey(ValueKey('connector-service-$id'));
    Future<void> searchCatalog(String value) async {
      await until(() => find.byType(ConnectorServicePage).evaluate().isEmpty);
      final field = find.descendant(
        of: find.byType(ConnectorsBody),
        matching: find.byType(TextField),
      );
      await tester.scrollUntilVisible(
        field,
        -300,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(field);
      await frames(100);
      await tester.enterText(field, value);
      await frames(400);
      expect(tester.widget<TextField>(field).controller!.text, value);
      await closeKeyboard();
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
      await tester.ensureVisible(category);
      await tester.tap(category);
    } else {
      await tester.tap(find.byKey(const ValueKey('connector-category-menu')));
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
    expect(find.text('已连接账号'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('connector-account-count')))
          .data,
      '$count',
    );
    expect(find.byKey(const ValueKey('connector-connect')), findsOneWidget);
    expect(find.textContaining('可用工具'), findsOneWidget);
    await shot('detail-light');

    await tester.tap(find.byTooltip('更多').first);
    await frames();
    expect(find.text('账号备注'), findsOneWidget);
    expect(find.text('重新授权'), findsOneWidget);
    await shot('account-menu');
    if (DesktopHost.supported) {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await frames();
      expect(find.byType(MenuChoice), findsNothing);
      await tester.tap(find.byTooltip('更多').first);
      await frames();
    }
    await tester.tap(find.text('账号备注'));
    await frames();
    await tester.tap(find.text('取消'));
    await frames();
    final toolsSearch = find.byType(TextField).first;
    await tester.ensureVisible(toolsSearch);
    await tester.enterText(toolsSearch, 'issue');
    await frames(400);
    await loaded();
    await closeKeyboard();
    await shot('tools-search');
    final toolKey = tester
        .widget<ListTile>(
          find
              .byWidgetPredicate(
                (widget) =>
                    widget is ListTile &&
                    widget.key is ValueKey<String> &&
                    (widget.key! as ValueKey<String>).value.startsWith(
                      'connector-tool-',
                    ),
              )
              .first,
        )
        .key!;
    final tool = find.byKey(toolKey);
    await tester.ensureVisible(tool);
    await frames();
    await tester.tap(tool);
    await frames();
    final description =
        (tester.widget<ListTile>(tool).subtitle! as Padding).child! as Text;
    expect(description.maxLines, isNull);
    await shot('tool-expanded');
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
    // Exercise the real Relay's rejected session response, then recover through Retry.
    final token = client.account.token;
    client.account.token = 'connector-ui-invalid-session';
    await tester.tap(find.byTooltip('刷新'));
    await frames();
    await loaded();
    expect(find.text('连接器暂不可用'), findsOneWidget);
    await shot('failed-refresh');
    client.account.token = token;
    await tester.tap(find.text('重试'));
    await frames();
    await loaded();
    expect(find.byType(ErrorNotice), findsNothing);
    expect(service('github'), findsOneWidget);
    await client.prefs.update(locale: 'en');
    await tester.pumpWidget(page(Brightness.dark));
    await frames(700);
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
    expect(find.text('Connected accounts'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('connector-account-count')))
          .data,
      '$count',
    );
    await shot('detail-dark-en');
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await frames();
    expect(find.byType(ConnectorsBody), findsOneWidget);
    scale = 1.4;
    await tester.pumpWidget(page(Brightness.light));
    await frames(700);
    await shot('large-text');
    await tester.ensureVisible(service('github'));
    await tester.tap(service('github'));
    await frames();
    await loaded();
    await shot('detail-large-text');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugPrint(
      'CONNECTOR CATALOG real provider directory, detail, cancellation and account scope passed',
    );
  });
}
