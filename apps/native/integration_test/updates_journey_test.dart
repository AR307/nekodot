import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';

import 'package:nekodot_native/features/updates.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/platform/updates.dart';
import 'package:nekodot_native/ui/design.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('actual Relay version check and native package download', (
    tester,
  ) async {
    if (Platform.isWindows) await DesktopHost.initialize();
    final c = NekodotClient();
    runApp(
      MaterialApp(
        theme: appTheme(Brightness.light),
        builder: (_, child) => Platform.isWindows
            ? WindowChrome(child: child!)
            : Ambient(child: child!),
        home: UpdatesPage(client: c),
      ),
    );
    Future<void> until(bool Function() predicate) async {
      final end = DateTime.now().add(const Duration(minutes: 3));
      while (!predicate() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 150));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(predicate(), isTrue);
    }

    await until(() => find.text('有新版本可用').evaluate().isNotEmpty);
    await tester.tap(find.byKey(const ValueKey('download-update')));
    final label = Platform.isWindows ? '退出并安装' : '打开系统安装器';
    await until(() => find.text(label).evaluate().isNotEmpty);
    expect(tester.takeException(), isNull);
    final version = await tester.runAsync(InstalledVersion.read);
    final permission = await tester.runAsync(canInstallUpdate);
    binding.reportData = {
      'platform': Platform.operatingSystem,
      'installed': version.toString(),
      'actualRelayDownload': true,
      'installerInvoked': false,
      'installPermission': permission,
    };
    if (Platform.isAndroid) {
      await tester.tap(find.text(label));
      if (permission == false) {
        await until(() => find.text('打开安装权限设置').evaluate().isNotEmpty);
      }
    }
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
    await tester.pump(const Duration(milliseconds: 500));
    if (Platform.isAndroid) await binding.takeScreenshot('updates-android');
    c.dispose();
  });
}
