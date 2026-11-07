import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

// Actual model replies -> Node -> Relay -> FCM -> Android notification manager.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android keeps the latest notification for each conversation', (
    tester,
  ) async {
    expect(Platform.isAndroid, isTrue);
    SharedPreferences.setMockInitialValues({
      'language': 'en',
      'theme': 'light',
      'notification-requested': true,
    });
    final c = NekodotClient(vault: MemoryVault());
    await tester.pumpWidget(NekodotApp(client: c));
    Future<void> until(
      bool Function() ready, {
      String what = '',
      int seconds = 240,
    }) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 150));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(ready(), isTrue, reason: '$what ${c.notificationError}');
    }

    Future<void> tap(Finder f) async {
      await until(() => f.evaluate().isNotEmpty);
      await Scrollable.ensureVisible(tester.element(f.first), alignment: .4);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(f.first);
      await tester.pump(const Duration(milliseconds: 250));
    }

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
    const dm = String.fromEnvironment('QA_CONVERSATION');
    const group = String.fromEnvironment('QA_GROUP');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final expected = <String, String>{};
    final local = FlutterLocalNotificationsPlugin();
    Future<void> send(
      String id,
      String marker, {
      bool background = false,
    }) async {
      await tap(find.byKey(ValueKey('conversation-$id')));
      final field = find.byKey(const ValueKey('chat-input'));
      await tap(field);
      await tester.enterText(
        field,
        '${id == group ? '@qalead ' : ''}${background ? 'Use execute_code to wait 20 seconds. Then ' : ''}Reply exactly $marker. Do not mention or hand off to any other Bot.',
      );
      await tap(find.byTooltip('Send'));
      await until(
        () => tester.widget<TextField>(field).controller!.text.isEmpty,
      );
      await tester.pageBack();
      await until(() => c.visibleConversation != id, what: 'back to chat list');
    }

    Future<void> checkNotification(String id, String marker) async {
      List<ActiveNotification> active = [];
      final end = DateTime.now().add(const Duration(minutes: 4));
      while (DateTime.now().isBefore(end)) {
        active = await tester.runAsync(local.getActiveNotifications) ?? [];
        if (active.any((n) => n.tag == id && (n.body ?? '').contains(marker))) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 150));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 250)),
        );
      }
      final matching = active.where((n) => n.tag == id).toList();
      expect(
        matching,
        hasLength(1),
        reason: 'one Android notification per conversation',
      );
      expect(matching.single.id, 0);
      expect(matching.single.body, contains(marker));
      for (final other in expected.entries.where((e) => e.key != id)) {
        expect(active.where((n) => n.tag == other.key), hasLength(1));
        expect(
          active.singleWhere((n) => n.tag == other.key).body,
          contains(other.value),
        );
      }
      expected[id] = marker;
      debugPrint('QA latest notification: $marker');
    }

    for (final round in [1, 2]) {
      for (final id in [dm, group]) {
        final marker = 'LATEST${id == dm ? 'DM' : 'GROUP'}${stamp}R$round';
        await send(id, marker);
        await checkNotification(id, marker);
        await until(() => (c.node.activities[id]?.state ?? 'idle') == 'idle');
      }
    }
    debugPrint(
      'QA foreground replacement verified; observe two OS notifications',
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 25)),
    );
    final background = 'LATESTBACKGROUND$stamp';
    await send(dm, background, background: true);
    debugPrint('QA background ready: $background');
    // The host uses the real emulator Home button and the actual OS notification.
    await until(
      () => c.visibleConversation == dm,
      what: 'tap real background notification',
      seconds: 300,
    );
    // Android auto-cancels the tapped notification. The host records the actual
    // notification manager state before the tap, not a synthetic in-app signal.
    await tester.runAsync(() => c.loadMessages(dm));
    expect(
      (c.node.messages[dm] ?? []).any(
        (m) =>
            m.author.type == 'bot' &&
            m.status == 'done' &&
            '${m.content['text']}'.contains(background),
      ),
      isTrue,
    );
    binding.reportData = {
      'realModel': 'gpt-6.1-sol',
      'foregroundLatestPerConversation': true,
      'backgroundReplacementEvidence': 'host OS notification capture required',
      'notificationTapOpenedConversation': true,
    };
    debugPrint('QA notification journey passed');
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 20)));
}
