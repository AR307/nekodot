import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Use the already-installed Windows plugin with a private on-disk test path.
// ignore: depend_on_referenced_packages
import 'package:path_provider_windows/path_provider_windows.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_windows/shared_preferences_windows.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/ui/design.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

class _QaPaths extends PathProviderWindows {
  @override
  Future<String> getApplicationSupportPath() async =>
      '${const String.fromEnvironment('QA_EVIDENCE_DIR')}/unread-preferences';
}

/// Two separate launches exercise real disk persistence and a real reply
/// produced while the observer is disconnected. No fake messages or sequence.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('offline reply survives a native client restart', (tester) async {
    if (Platform.isWindows) {
      SharedPreferencesStorePlatform.instance = SharedPreferencesWindows()
        ..pathProvider = _QaPaths();
    }
    SharedPreferences.setPrefix('qa-ui-unread.');
    const stage = String.fromEnvironment(
      'QA_UNREAD_STAGE',
      defaultValue: 'send',
    );
    const dm = String.fromEnvironment('QA_CONVERSATION');
    const node = String.fromEnvironment('QA_NODE');
    final prefs = await SharedPreferences.getInstance();
    final c = NekodotClient(vault: MemoryVault());
    addTearDown(c.dispose);
    Future<void> frames() async {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 70));
    }

    Future<void> until(bool Function() done, String name) async {
      final end = DateTime.now().add(const Duration(minutes: 3));
      while (!done() && DateTime.now().isBefore(end)) {
        await frames();
      }
      expect(done(), isTrue, reason: name);
      debugPrint('UI_UNREAD PASS $stage $name');
    }

    Future<void> login(NekodotClient client) async {
      await client.login(
        const String.fromEnvironment('QA_EMAIL'),
        const String.fromEnvironment('QA_PASSWORD'),
      );
      await until(() => client.connection.ready, 'authenticated');
      await client.selectNode(node);
      await until(
        () => !client.node.syncing && client.node.seq > 0,
        'snapshot',
      );
    }

    await login(c);
    await c.prefs.update(locale: 'en');
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: HomePage(client: c),
      ),
    );
    await frames();
    if (stage == 'send') {
      await c.reading.viewed(node, dm, c.node.seq);
      final baseline = c.reading.position(node, dm);
      await prefs.setInt('test-baseline', baseline);
      final marker = 'UIUNREAD${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('test-marker', marker);
      // A second actual connection represents another device sending a message.
      c.connection.active = false;
      await c.connection.disconnect();
      final sender = NekodotClient(vault: MemoryVault());
      addTearDown(sender.dispose);
      await login(sender);
      // This second device must not write the observer's device-local receipts.
      await sender.reading.load('qa-other-device-$marker');
      await sender.reading.baseline(node, sender.node.seq);
      await sender.send(dm, 'Reply exactly $marker. Do not use tools.');
      await until(
        () =>
            sender.node.messages[dm]?.any(
              (m) =>
                  m.author.type == 'bot' &&
                  m.status == 'done' &&
                  '${m.content['text']}'.contains(marker),
            ) ==
            true,
        'real offline reply',
      );
      expect(c.reading.position(node, dm), baseline);
      expect(c.connection.ready, isFalse);
      await prefs.setBool('test-awaiting-restart', true);
    } else {
      final marker = prefs.getString('test-marker');
      expect(marker, isNotNull);
      expect(prefs.getBool('test-awaiting-restart'), isTrue);
      await c.loadMessages(dm);
      expect(
        c.node.messages[dm]!.any(
          (m) =>
              m.author.type == 'bot' &&
              '${m.content['text']}'.contains(marker!),
        ),
        isTrue,
      );
      expect(c.reading.position(node, dm), prefs.getInt('test-baseline'));
      expect(c.reading.unread(node, dm, c.incomingSequence(dm)), isTrue);
      await frames();
      expect(find.byKey(const ValueKey('unread-$dm')), findsOneWidget);
      await c.reading.viewed(node, dm, c.incomingSequence(dm));
      await frames();
      expect(find.byKey(const ValueKey('unread-$dm')), findsNothing);
      debugPrint(
        'UI_UNREAD PASS persisted position and recovered sidebar badge',
      );
    }
    await tester.pumpWidget(const SizedBox());
  });
}
