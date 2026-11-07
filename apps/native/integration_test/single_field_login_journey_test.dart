import 'dart:convert';
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

import 'local_desktop_journey_test.dart' show MemoryVault;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('two confidential cards use the real native browser vault', (
    tester,
  ) async {
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
      int seconds = 360,
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
      await tester.pump(const Duration(milliseconds: 400));
      if (Platform.isWindows) {
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
    const dm = String.fromEnvironment('QA_SECOND_CONVERSATION');
    bool idle() => (c.node.activities[dm]?.state ?? 'idle') == 'idle';
    await until(() => c.online && idle());
    await tap(find.byKey(const ValueKey('conversation-$dm')));
    await tester.runAsync(() => c.loadMessages(dm));
    final priorMessages = (c.node.messages[dm] ?? [])
        .map((message) => message.messageId)
        .toSet();
    final input = find.byKey(const ValueKey('chat-input'));
    final service = 'Browser handoff ${DateTime.now().millisecondsSinceEpoch}';
    await tap(input);
    await tester.enterText(
      input,
      'Read nekodot-secrets skill. Sign into the controlled test page http://127.0.0.1:4562/login using native browser tools. Request one account card (identifier/text) first; after delivery request one password card (password/password). Use service $service, purpose Controlled browser login, target vault origin http://127.0.0.1:4562. Finish each requesting turn. After both deliveries use nekodot_secret_browser with the password reference then submit the form in the actual browser. Never read form values or print credentials. Reply HANDOFF_LOGIN_OK only after seeing that marker on the page.',
    );
    await tap(find.byTooltip('Send'));
    for (final field in ['identifier', 'password']) {
      final finder = find.byKey(ValueKey('secret-field-$field'));
      await until(
        () => finder.evaluate().isNotEmpty && idle(),
        what: 'single $field card',
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.key is ValueKey &&
              '${(w.key as ValueKey).value}'.startsWith('secret-field-'),
        ),
        findsOneWidget,
      );
      await tap(finder);
      await tester.enterText(
        finder,
        field == 'identifier'
            ? 'handoff-test-account'
            : 'handoff-test-password',
      );
      await tap(find.byKey(const ValueKey('secret-submit')));
      await until(() => finder.evaluate().isEmpty, what: 'delivered $field');
      debugPrint('QA browser delivered one $field card');
    }
    await until(
      () =>
          idle() &&
          (c.node.messages[dm] ?? []).any(
            (m) =>
                !priorMessages.contains(m.messageId) &&
                m.author.type == 'bot' &&
                m.kind == 'text' &&
                m.status == 'done' &&
                '${m.content['text']}'.contains('HANDOFF_LOGIN_OK'),
          ),
      what: 'native browser login',
      seconds: 480,
    );
    final content = jsonEncode(
      (c.node.messages[dm] ?? []).map((m) => m.content).toList(),
    );
    expect(content, isNot(contains('handoff-test-account')));
    expect(content, isNot(contains('handoff-test-password')));
    await shot('browser-login-light');
    await tester.runAsync(() => c.prefs.update(appearance: 'dark'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await shot('browser-login-dark');
    debugPrint('QA browser login passed; focus observation window');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 40)),
    );
    binding.reportData = {
      ...?binding.reportData,
      'realModel': 'gpt-6.1-sol',
      'singleAccountThenPassword': true,
      'realNativeBrowserLogin': true,
      'secretInMessages': false,
    };
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 18)));
}
