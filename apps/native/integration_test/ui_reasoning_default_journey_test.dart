import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/ui/design.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

/// Real candidate UI -> authenticated Relay -> Node -> native Hermes -> real model.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'new session uses xhigh and preserves explicit reasoning on resume',
    (tester) async {
      SharedPreferences.setMockInitialValues({'notification-requested': true});
      final client = NekodotClient(vault: MemoryVault());
      addTearDown(client.dispose);
      const dm = String.fromEnvironment('QA_CONVERSATION');
      final phone = Platform.isAndroid;
      Future<void> frames([int ms = 350]) async {
        final end = DateTime.now().add(Duration(milliseconds: ms));
        while (DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 40));
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      }

      Future<void> until(bool Function() ready, String label) async {
        final end = DateTime.now().add(const Duration(minutes: 4));
        while (!ready() && DateTime.now().isBefore(end)) {
          await frames(100);
        }
        expect(ready(), isTrue, reason: label);
        debugPrint('UI_REASONING PASS $label');
      }

      Future<void> tap(Finder finder) async {
        await until(() => finder.evaluate().isNotEmpty, 'control present');
        await Scrollable.ensureVisible(tester.element(finder.first));
        await frames(100);
        await tester.tap(finder.hitTestable().first);
        await frames();
      }

      if (!phone) {
        await windowManager.ensureInitialized();
        await windowManager.restore();
        await windowManager.show();
        tester.view.physicalSize = const Size(1280, 840);
        tester.view.devicePixelRatio = 1;
      }
      await client.prefs.update(locale: 'en', appearance: 'light');
      await client.login(
        const String.fromEnvironment('QA_EMAIL'),
        const String.fromEnvironment('QA_PASSWORD'),
      );
      await client.selectNode(const String.fromEnvironment('QA_NODE'));
      await until(
        () => client.online && client.node.conversations.isNotEmpty,
        'real Node connected',
      );
      final botId = client.node.conversations.firstWhere(
        (c) => c['conversationId'] == dm,
      )['botId'];
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [nativeRoutes],
          theme: appTheme(Brightness.light, glass: phone),
          home: HomePage(client: client),
        ),
      );
      await frames();
      await tap(find.byKey(ValueKey('conversation-$dm')));
      await tap(find.byKey(const ValueKey('chat-sessions')));
      await tap(find.byKey(const ValueKey('new-native-session')));
      await tap(find.byKey(const ValueKey('create-native-session')));
      final current = find.byKey(const ValueKey('reasoning-current'));
      await until(
        () =>
            current.evaluate().isNotEmpty &&
            tester.widget<Text>(current).data == 'xhigh',
        'new-session display xhigh',
      );
      var info = await client.rpc('models.reasoning.get', {'botId': botId});
      expect(info['effort'], 'xhigh');
      expect(info['wireEffort'], 'xhigh');
      final stored = (await client.rpc('sessions.list', {
        'botId': botId,
      }))['currentSessionId'];
      final before = (client.node.messages[dm] ?? [])
          .map((m) => m.messageId)
          .toSet();
      await tester.enterText(
        find.byKey(const ValueKey('chat-input')),
        'Reply exactly UI_XHIGH_LIVE_OK. Do not use tools.',
      );
      await frames();
      await tap(find.byTooltip('Send'));
      await until(
        () => (client.node.messages[dm] ?? []).any(
          (m) =>
              !before.contains(m.messageId) &&
              m.author.type == 'bot' &&
              m.status == 'done' &&
              '${m.content['text']}'.contains('UI_XHIGH_LIVE_OK'),
        ),
        'real model reply with xhigh',
      );
      await until(
        () => client.node.activities[dm]?.state == 'idle',
        'turn finished',
      );
      info = await client.rpc('models.reasoning.get', {'botId': botId});
      expect(info['effort'], 'xhigh');
      expect(info['wireEffort'], 'xhigh');
      await tap(find.byKey(const ValueKey('reasoning-toggle')));
      await tap(find.text('high').last);
      await until(
        () => tester.widget<Text>(current).data == 'high',
        'explicit high saved',
      );
      await tap(find.byKey(const ValueKey('chat-sessions')));
      await tap(find.byKey(const ValueKey('new-native-session')));
      await tap(find.byKey(const ValueKey('create-native-session')));
      await until(
        () =>
            current.evaluate().isNotEmpty &&
            tester.widget<Text>(current).data == 'xhigh',
        'second new session defaults xhigh',
      );
      await tap(find.byKey(const ValueKey('chat-sessions')));
      await tap(find.byKey(ValueKey('switch-session-$stored')));
      await until(
        () =>
            current.evaluate().isNotEmpty &&
            tester.widget<Text>(current).data == 'high',
        'resumed explicit high preserved',
      );
      info = await client.rpc('models.reasoning.get', {'botId': botId});
      expect(info['effort'], 'high');
      expect(info['wireEffort'], 'high');
      await tap(find.byKey(const ValueKey('reasoning-toggle')));
      await tap(find.text('xhigh').last);
      await until(
        () => tester.widget<Text>(current).data == 'xhigh',
        'QA choice restored to xhigh',
      );
      if (phone) {
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        await binding.takeScreenshot('ui-reasoning-android-xhigh');
      } else {
        final view = tester.binding.renderViews.first;
        final picture = await (view.debugLayer! as OffsetLayer).toImage(
          Offset.zero & view.flutterView.physicalSize,
        );
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${const String.fromEnvironment('QA_EVIDENCE_DIR')}/ui-reasoning-windows-xhigh.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      }
      expect(tester.takeException(), isNull);
    },
  );
}
