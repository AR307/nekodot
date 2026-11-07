import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/main.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real model notification delivery and conversation navigation', (
    tester,
  ) async {
    if (Platform.isWindows) await DesktopHost.initialize();
    SharedPreferences.setMockInitialValues({
      'language': 'en',
      'theme': 'light',
      'notification-requested': true,
    });
    final c = NekodotClient(vault: MemoryVault());
    await tester.pumpWidget(NekodotApp(client: c));
    Future<void> until(bool Function() ready, {int seconds = 180}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 150));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(ready(), isTrue, reason: c.notificationError);
    }

    Future<void> tap(Finder finder) async {
      await until(() => finder.evaluate().isNotEmpty);
      await tester.ensureVisible(finder.first);
      await tester.tap(finder.first);
      await tester.pump(const Duration(milliseconds: 300));
    }

    const dm = String.fromEnvironment('QA_CONVERSATION');
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
    await until(
      () =>
          c.online &&
          (c.notificationStatus.isNotEmpty || c.notificationError.isNotEmpty),
    );
    expect(
      c.notificationStatus,
      'Notifications enabled',
      reason: c.notificationError,
    );
    await tap(find.byKey(const ValueKey('conversation-$dm')));
    final marker = 'CORENOTIFY${DateTime.now().millisecondsSinceEpoch}';
    final signal = Completer<void>();
    final subscription = c.notifications.stream.listen((event) {
      if ('${event['preview']}'.contains(marker) && !signal.isCompleted) {
        signal.complete();
      }
    });
    addTearDown(subscription.cancel);
    debugPrint('QA notification marker: $marker');
    final input = find.byKey(const ValueKey('chat-input'));
    final waitSeconds = Platform.isAndroid ? 30 : 8;
    await tap(input);
    await tester.enterText(
      input,
      'Use execute_code to wait $waitSeconds seconds with Python time.sleep, print 19*23, then reply $marker and 437. Do not use any other tools.',
    );
    await tap(find.byTooltip('Send'));
    await until(() => tester.widget<TextField>(input).controller!.text.isEmpty);
    Navigator.of(tester.element(input)).popUntil((route) => route.isFirst);
    await tester.pump(const Duration(milliseconds: 400));
    await tap(
      find.byKey(
        const ValueKey('conversation-${String.fromEnvironment('QA_GROUP')}'),
      ),
    );
    expect(c.visibleConversation, isNot(dm));
    // Android runner moves the actual task into background after this marker.
    debugPrint('QA notification background ready');
    if (Platform.isWindows) {
      await until(() => signal.isCompleted);
      await tester.runAsync(() => c.loadMessages(dm));
      expect(
        (c.node.messages[dm] ?? []).any(
          (m) =>
              m.author.type == 'bot' &&
              m.status == 'done' &&
              '${m.content['text']}'.contains(marker),
        ),
        isTrue,
      );
      // Unpackaged Windows apps cannot enumerate toast history. Observe the
      // real system toast separately; a Relay signal alone is not OS proof.
      debugPrint('QA Windows toast observation window: $marker');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 45)),
      );
      expect(c.notificationError, isEmpty);
    }
    if (Platform.isAndroid) {
      // The host observes the OS drawer and taps the real notification while
      // Flutter is paused in background; no synthetic destination is injected.
      debugPrint('QA notification tap pending');
      await until(
        () =>
            c.visibleConversation == dm &&
            find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty,
      );
    }
    binding.reportData = {
      'platform': Platform.operatingSystem,
      'realModel': 'gpt-6.1-sol',
      'systemNotificationEvidenceRequired': true,
      'windowsToastRequiresSeparateObservation': Platform.isWindows,
      'actualTap': Platform.isAndroid,
    };
    debugPrint(
      Platform.isAndroid
          ? 'QA Android system notification and tap passed'
          : 'QA Windows signal passed; inspect separate OS evidence',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 8)));
}
