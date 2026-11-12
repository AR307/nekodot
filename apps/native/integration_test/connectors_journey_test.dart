import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/extensions.dart';
import 'package:nekodot_native/features/connectors.dart';
import 'package:nekodot_native/features/connector_approval.dart';
import 'package:nekodot_native/main.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

// Real account Relay + Composio catalog. No fixture transport or fake service data.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'account connectors without a Node, search and compact account menu',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'language': 'zh',
        'theme': 'light',
      });
      final client = NekodotClient(vault: MemoryVault());
      var appOwnsClient = false;
      addTearDown(() {
        if (!appOwnsClient) client.dispose();
      });
      await client.acceptSession({
        'token': const String.fromEnvironment('QA_TOKEN'),
      });
      client.selectedNodeId = null;
      if (DesktopHost.supported) {
        await DesktopHost.initialize();
        await windowManager.setTitle('nekodot Connector Journey');
        await windowManager.setSize(const Size(980, 720));
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
            '${const String.fromEnvironment('QA_EVIDENCE_DIR')}/connectors-$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        } else if (Platform.isAndroid) {
          if (!androidSurface) {
            await binding.convertFlutterSurfaceToImage();
            androidSurface = true;
            await frames();
          }
          await binding.takeScreenshot(
            'connectors-${name.replaceFirst('windows-', 'android-')}',
          );
        }
      }

      Widget page(Brightness brightness) => MaterialApp(
        navigatorObservers: [nativeRoutes],
        debugShowCheckedModeBanner: false,
        theme: appTheme(brightness),
        builder: (context, child) => Ambient(child: child!),
        home: ExtensionsPage(client: client, kind: 'connectors'),
      );
      await tester.pumpWidget(page(Brightness.light));
      await until(
        () =>
            find.text('GitHub').evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      expect(find.textContaining('已连接'), findsWidgets);
      await shot('windows-light');
      await tester.tap(find.byTooltip('更多').first);
      await frames();
      expect(find.text('连接其他账号'), findsOneWidget);
      expect(find.text('重新授权'), findsOneWidget);
      await shot('windows-menu');
      await tester.tap(find.text('账号备注'));
      await frames();
      await tester.enterText(find.byType(TextField).last, 'Connector QA');
      await tester.tap(find.text('保存'));
      await until(
        () => find.textContaining('Connector QA').evaluate().isNotEmpty,
      );
      await tester.enterText(find.byType(TextField).first, 'gmail');
      await frames(350);
      await until(
        () =>
            find.text('Gmail').evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      await shot('windows-search');
      await tester.enterText(
        find.byType(TextField).first,
        'zzzznekodotnomatch',
      );
      await until(() => find.text('未找到服务').evaluate().isNotEmpty);
      await shot('windows-empty');
      await tester.enterText(find.byType(TextField).first, 'github');
      await frames(350);
      await until(
        () =>
            find.text('GitHub').evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      await tester.pumpWidget(page(Brightness.dark));
      await until(
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      await shot('windows-dark');
      if (DesktopHost.supported) {
        await windowManager.setSize(const Size(480, 720));
      }
      await frames();
      await shot('windows-narrow');
      expect(tester.takeException(), isNull);
      expect(find.byType(ConnectorsBody), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      if (DesktopHost.supported) {
        await windowManager.setSize(const Size(980, 760));
      }
      await client.selectNode(const String.fromEnvironment('QA_NODE'));
      appOwnsClient = true;
      await tester.pumpWidget(NekodotApp(client: client));
      await frames();
      client.openNotification({
        'nodeId': client.selectedNodeId!,
        'conversationId': const String.fromEnvironment('QA_CONVERSATION'),
      });
      await until(
        () => find.byType(ConnectorApprovalCard).evaluate().isNotEmpty,
      );
      final card = find.byType(ConnectorApprovalCard).last;
      await Scrollable.ensureVisible(tester.element(card), alignment: .15);
      await frames();
      expect(
        find.descendant(of: card, matching: find.text('GitHub')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('详细信息')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('owner')),
        findsNothing,
      );
      await shot('windows-approval');
      await tester.tap(find.descendant(of: card, matching: find.text('详细信息')));
      await frames();
      expect(
        find.descendant(of: card, matching: find.text('owner')),
        findsOneWidget,
      );
      await Scrollable.ensureVisible(tester.element(card), alignment: .15);
      await shot('windows-approval-details');
      if (DesktopHost.supported) {
        await windowManager.setSize(const Size(480, 760));
        await frames();
        client.openNotification({
          'nodeId': client.selectedNodeId!,
          'conversationId': const String.fromEnvironment('QA_CONVERSATION'),
        });
        await until(
          () => find.byType(ConnectorApprovalCard).evaluate().isNotEmpty,
        );
        await Scrollable.ensureVisible(
          tester.element(find.byType(ConnectorApprovalCard).last),
          alignment: .1,
        );
      }
      await frames();
      await shot('windows-approval-narrow');
      expect(tester.takeException(), isNull);
      debugPrint(
        'CONNECTORS real account management and in-chat connector approval card passed',
      );
    },
  );
}
