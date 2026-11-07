import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/routines.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

// A bounded session, the actual VPS, and an existing harmless connectivity task.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('upgraded VPS accepts a real webhook from the native test button', (
    tester,
  ) async {
    if (Platform.isWindows) await DesktopHost.initialize();
    SharedPreferences.setMockInitialValues({
      'language': 'en',
      'theme': 'light',
    });
    final client = NekodotClient(vault: MemoryVault());
    final target = {
      'botId': const String.fromEnvironment('QA_BOT'),
      'routineId': const String.fromEnvironment('QA_ROUTINE'),
    };
    late Set<String> previous;
    await tester.runAsync(() async {
      client.account.token = const String.fromEnvironment('QA_TOKEN');
      await client.prefs.load();
      await client.bootstrap();
      await client.selectNode(const String.fromEnvironment('QA_NODE'));
    });
    Future<void> until(bool Function() ready) async {
      final end = DateTime.now().add(const Duration(minutes: 4));
      while (!ready() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 150));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(ready(), isTrue, reason: client.error);
    }

    await until(() => client.online);
    await tester.runAsync(() async {
      final before = await client.rpc('routines.get', target);
      previous = objects(before['executions'])
          .map((e) => '${e['executionId']}')
          .toSet();
    });
    final capture = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: MaterialApp(
          theme: appTheme(Brightness.light),
          builder: (context, child) => Ambient(child: child!),
          home: RoutinePage(
            client: client,
            botId: target['botId']!,
            routineId: target['routineId']!,
          ),
        ),
      ),
    );
    await until(() => find.text('Test webhook').evaluate().isNotEmpty);
    await tester.ensureVisible(find.text('Test webhook').first);
    await tester.tap(find.text('Test webhook').first);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await until(
      () => find
          .byKey(const ValueKey('routine-test-receipt'))
          .evaluate()
          .isNotEmpty,
    );
    final receipt = tester
        .widget<SelectableText>(
          find.byKey(const ValueKey('routine-test-receipt')),
        )
        .data!;
    expect(receipt, contains('HTTP 202'));
    expect(receipt, contains('accepted'));
    Json? completed;
    final deadline = DateTime.now().add(const Duration(minutes: 4));
    while (completed == null && DateTime.now().isBefore(deadline)) {
      await tester.runAsync(() async {
        final detail = await client.rpc('routines.get', target);
        completed = objects(detail['executions'])
            .where(
              (e) =>
                  !previous.contains(e['executionId']) &&
                  e['state'] == 'completed',
            )
            .firstOrNull;
        await Future<void>.delayed(const Duration(seconds: 1));
      });
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(completed, isNotNull);
    expect('${completed!['text']}', contains('测试回调已执行'));
    await tester.ensureVisible(
      find.byKey(const ValueKey('routine-test-receipt')),
    );
    await tester.pump(const Duration(milliseconds: 400));
    if (Platform.isWindows) {
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await tester.runAsync(
        () => File(
          '${const String.fromEnvironment('QA_EVIDENCE_DIR')}/webhook-native.png',
        ).writeAsBytes(bytes!.buffer.asUint8List()),
      );
      image.dispose();
    }
    debugPrint('VPS native webhook: accepted and real model completed');
    await tester.pumpWidget(const SizedBox.shrink());
    client.dispose();
  });
}
