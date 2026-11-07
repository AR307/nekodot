import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/main.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'candidate themes, window sizes and live reconnect preserve the task',
    (tester) async {
      if (Platform.isWindows) await DesktopHost.initialize();
      SharedPreferences.setMockInitialValues({
        'language': 'en',
        'theme': 'light',
        'notification-requested': true,
      });
      final c = NekodotClient(vault: MemoryVault());
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: NekodotApp(client: c),
        ),
      );
      Future<void> until(
        bool Function() ready, {
        String what = '',
        int seconds = 300,
      }) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!ready() && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 150));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
        }
        expect(ready(), isTrue, reason: what);
      }

      Future<void> tap(Finder f) async {
        await until(() => f.evaluate().isNotEmpty);
        await Scrollable.ensureVisible(tester.element(f.first), alignment: .4);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(f.first);
        await tester.pump(const Duration(milliseconds: 350));
      }

      Future<void> shot(String name) async {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.runAsync(() async {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
          await File(
            '${const String.fromEnvironment('QA_EVIDENCE_DIR')}/$name.png',
          ).writeAsBytes(bytes);
          image.dispose();
        });
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
      const dm = String.fromEnvironment('QA_CONVERSATION');
      await until(
        () => c.online && (c.node.activities[dm]?.state ?? 'idle') == 'idle',
      );
      await tap(find.byKey(const ValueKey('conversation-$dm')));
      await tester.runAsync(() => c.loadMessages(dm));
      final input = find.byKey(const ValueKey('chat-input'));
      await shot('conversation-light');
      await tester.runAsync(() => c.prefs.update(appearance: 'dark'));
      await until(
        () =>
            input.evaluate().isNotEmpty &&
            Theme.of(tester.element(input)).brightness == Brightness.dark,
        what: 'dark theme',
      );
      await shot('conversation-dark');
      await tester.runAsync(() => windowManager.setSize(const Size(760, 760)));
      await tester.pump(const Duration(milliseconds: 600));
      if (input.evaluate().isEmpty) {
        await tap(find.byKey(const ValueKey('conversation-$dm')));
      }
      await shot('conversation-narrow-dark');
      await tester.runAsync(() => c.prefs.update(appearance: 'light'));
      await until(
        () =>
            input.evaluate().isNotEmpty &&
            Theme.of(tester.element(input)).brightness == Brightness.light,
        what: 'light theme',
      );
      await shot('conversation-narrow-light');
      final marker = 'RECONNECTED_${DateTime.now().millisecondsSinceEpoch}';
      await tap(input);
      await tester.enterText(
        input,
        'Use execute_code once: import time; time.sleep(12); print(19*23). Then reply $marker 437. No other tool calls.',
      );
      await tap(find.byTooltip('Send'));
      await until(
        () => (c.node.messages[dm] ?? []).any(
          (m) => m.kind == 'tool' && m.status == 'streaming',
        ),
        what: 'real tool running',
      );
      final tools = (c.node.messages[dm] ?? [])
          .where((m) => m.kind == 'tool')
          .map((m) => m.messageId)
          .toSet();
      await tester.runAsync(() async {
        c.pause();
        await c.connection.disconnect();
        c.resume();
      });
      await until(
        () => c.connection.ready && c.online,
        what: 'real channel reconnected',
      );
      await until(
        () =>
            (c.node.activities[dm]?.state ?? 'idle') == 'idle' &&
            (c.node.messages[dm] ?? []).any(
              (m) =>
                  m.status == 'done' &&
                  m.author.type == 'bot' &&
                  '${m.content['text']}'.contains(marker),
            ),
        what: 'same task completed',
      );
      expect(
        (c.node.messages[dm] ?? []).where(
          (m) => m.kind == 'tool' && !tools.contains(m.messageId),
        ),
        isEmpty,
        reason: 'disconnect must not replay the tool',
      );
      await shot('reconnected-same-task');
      binding.reportData = {
        'darkLightObserved': true,
        'windowResized': true,
        'realChannelReconnect': true,
        'toolReplayed': false,
      };
      await tester.runAsync(() => windowManager.setSize(const Size(1160, 780)));
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
