import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/chat_message.dart';
import 'package:nekodot_native/features/connector_approval.dart';
import 'package:nekodot_native/main.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

// Windows: an existing real, pending approval; DENY the dedicated test operation.
// Android: reopen the same real, denied card. Never grant a third-party write.
// Prepare the task separately so rerunning this UI journey never starts a task.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('connector decision folds immediately and keeps the real result', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'language': 'zh',
      'theme': 'light',
      'notification-requested': true,
    });
    final client = NekodotClient(vault: MemoryVault());
    var appOwnsClient = false;
    addTearDown(() {
      if (!appOwnsClient) client.dispose();
    });
    const conversation = String.fromEnvironment('QA_FOLD_CONVERSATION');
    const marker = String.fromEnvironment('QA_FOLD_MARKER');
    expect(conversation, isNotEmpty);
    expect(marker, isNotEmpty);
    await client.acceptSession({
      'token': const String.fromEnvironment('QA_TOKEN'),
    });
    await client.selectNode(const String.fromEnvironment('QA_NODE'));
    if (DesktopHost.supported) {
      await DesktopHost.initialize();
      await windowManager.setTitle('nekodot Connector Approval Journey');
      await windowManager.setSize(const Size(980, 800));
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
      final end = DateTime.now().add(const Duration(minutes: 4));
      while (!ready() && DateTime.now().isBefore(end)) {
        await frames(150);
      }
      expect(ready(), isTrue);
      expect(tester.takeException(), isNull);
    }

    var surfaceReady = false;
    Future<void> shot(String name) async {
      await frames();
      if (Platform.isWindows) {
        final view = tester.binding.renderViews.first;
        final image = await (view.debugLayer! as OffsetLayer).toImage(
          Offset.zero & view.flutterView.physicalSize,
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${const String.fromEnvironment('QA_EVIDENCE_DIR')}/approval-fold-windows-$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      } else {
        if (!surfaceReady) {
          await binding.convertFlutterSurfaceToImage();
          surfaceReady = true;
          await frames();
        }
        await binding.takeScreenshot('approval-fold-android-$name');
      }
    }

    appOwnsClient = true;
    await tester.pumpWidget(NekodotApp(client: client));
    await frames();
    client.openNotification({
      'nodeId': client.selectedNodeId!,
      'conversationId': conversation,
    });
    await until(() => client.online);
    final card = find.byWidgetPredicate(
      (widget) =>
          widget is ControlCard &&
          widget.message.kind == 'approval' &&
          jsonEncode(widget.message.content).contains(marker),
    );

    await until(() => card.evaluate().isNotEmpty);
    await Scrollable.ensureVisible(tester.element(card), alignment: .3);
    await frames();
    final approval = find.descendant(
      of: card,
      matching: find.byType(ConnectorApprovalCard),
    );
    Finder within(Finder finder) => find.descendant(of: card, matching: finder);
    if (Platform.isWindows &&
        tester.widget<ConnectorApprovalCard>(approval).pending) {
      await tester.tap(within(find.text('详细信息')));
      await frames();
      await shot('before');
      final before = tester.getSize(within(find.byType(ChatCard))).height;
      await tester.tap(
        within(find.byKey(const ValueKey('connector-approval-deny'))),
      );
      await tester.pump();
      expect(
        within(find.byKey(const ValueKey('connector-approval-summary'))),
        findsOneWidget,
      );
      expect(within(find.text('详细信息')), findsNothing);
      expect(
        tester.getSize(within(find.byType(ChatCard))).height,
        lessThan(before),
      );
      await shot('after-tap');
      await until(
        () => !tester.widget<ConnectorApprovalCard>(approval).pending,
      );
    }
    expect(tester.widget<ConnectorApprovalCard>(approval).denied, isTrue);
    expect(within(find.text('拒绝')), findsOneWidget);
    expect(within(find.text('详细信息')), findsNothing);
    await shot('settled');

    await tester.tap(
      within(find.byKey(const ValueKey('connector-approval-summary'))),
    );
    await frames();
    expect(within(find.text('详细信息')), findsOneWidget);
    for (final choice in ['once', 'always', 'deny']) {
      expect(
        within(find.byKey(ValueKey('connector-approval-$choice'))),
        findsNothing,
      );
    }
    await tester.tap(within(find.text('详细信息')));
    await frames();
    await shot('expanded');
    await tester.tap(
      within(find.byKey(const ValueKey('connector-approval-summary'))),
    );
    await client.prefs.update(appearance: 'dark');
    if (DesktopHost.supported) {
      await windowManager.setSize(const Size(480, 800));
    }
    await frames();
    client.openNotification({
      'nodeId': client.selectedNodeId!,
      'conversationId': conversation,
    });
    await until(() => card.evaluate().isNotEmpty);
    await Scrollable.ensureVisible(tester.element(card), alignment: .3);
    await shot('dark');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugPrint(
      'CONNECTOR APPROVAL real denied operation stays collapsed and can be reviewed',
    );
  });
}
