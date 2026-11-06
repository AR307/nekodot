import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/secrets.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real Bot card, encrypted submission and original-session continuation', (
    tester,
  ) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final client = NekodotClient();
    const botId = String.fromEnvironment('QA_SECOND_BOT');
    const mode = String.fromEnvironment('QA_SECRET_MODE', defaultValue: 'api');
    Future<void> until(bool Function() ready, {int seconds = 180}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 200));
        final allow = find.widgetWithText(FilledButton, '允许一次');
        if (allow.evaluate().isNotEmpty &&
            tester.widget<FilledButton>(allow.first).onPressed != null) {
          await Scrollable.ensureVisible(
            tester.element(allow.first),
            alignment: .4,
          );
          await tester.pump(const Duration(milliseconds: 200));
          await tester.tap(allow.first);
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
      }
      expect(ready(), isTrue, reason: 'Real confidential journey timed out');
    }

    Future<void> tap(Finder finder) async {
      await Scrollable.ensureVisible(tester.element(finder), alignment: .4);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 400));
    }

    await tester.runAsync(() async {
      final session = await client.account.request(
        '/auth/login',
        method: 'POST',
        body: {
          'email': const String.fromEnvironment('QA_EMAIL'),
          'password': const String.fromEnvironment('QA_PASSWORD'),
        },
      );
      client.account.token = session['token'];
      await client.bootstrap();
      await client.selectNode(const String.fromEnvironment('QA_NODE'));
    });
    await until(() => client.online && client.node.conversations.isNotEmpty);
    final conversationId =
        '${client.node.conversations.firstWhere((c) => c['kind'] == 'dm' && c['botId'] == botId)['conversationId']}';
    runApp(
      MaterialApp(
        theme: appTheme(Brightness.light),
        navigatorObservers: [nativeRoutes],
        builder: (context, child) =>
            Theme.of(context).platform == TargetPlatform.windows
            ? WindowChrome(child: child!)
            : Ambient(child: child!),
        home: HomePage(client: client),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tap(find.byKey(ValueKey('conversation-$conversationId')));
    await until(
      () => find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty,
    );
    await tester.runAsync(() => client.loadMessages(conversationId));
    await until(
      () => (client.node.activities[conversationId]?.state ?? 'idle') == 'idle',
    );
    final native = mode.startsWith('native');
    final service = native
        ? const String.fromEnvironment('QA_NATIVE_ENV')
        : 'confidential-$mode-${DateTime.now().millisecondsSinceEpoch}';
    final spec = mode == 'private-key'
        ? {
            'service': service,
            'purpose': 'Install a harmless multiline test identity',
            'fields': [
              {
                'name': 'PRIVATE_KEY',
                'label': 'Test private key',
                'kind': 'private-key',
              },
            ],
            'target': {
              'kind': 'file',
              'path': '/root/.cache/nekodot-phase5-settings/confidential/identity.pem',
              'format': 'raw',
            },
          }
        : mode == 'otp'
        ? {
            'service': service,
            'purpose': 'Enter a temporary code on the isolated acceptance page',
            'fields': [
              {'name': 'code', 'label': 'One-time code', 'kind': 'otp'},
            ],
            'target': {
              'kind': 'browser-code',
              'origin': 'http://127.0.0.1:19439',
            },
          }
        : mode.startsWith('login')
        ? {
            'service': service,
            'purpose': 'Sign in to the isolated acceptance page',
            'fields': [
              {'name': 'identifier', 'label': 'Account', 'kind': 'text'},
              {'name': 'password', 'label': 'Password', 'kind': 'password'},
            ],
            'target': {'kind': 'vault', 'origin': 'http://127.0.0.1:19439'},
          }
        : {
            'service': service,
            'purpose': 'Configure the harmless local acceptance service',
            'fields': [
              {
                'name': 'QA_API_KEY',
                'label': 'Test API Key',
                'kind': 'password',
              },
            ],
            'target': {
              'kind': 'file',
              'path':
                  '/root/.cache/nekodot-phase5-settings/confidential/qa.env',
              'format': 'env',
            },
          };
    final verification = mode == 'private-key'
        ? 'After delivery use Python cryptography in the Hermes PM environment, or openssl, to load the approved PKCS8 PEM file, sign the harmless bytes nekodot-confidential-proof and verify with its public key. Never print file contents, key bytes or signatures. Reply CONFIDENTIAL_KEY_FILE_OK only after actual signature verification succeeds.'
        : mode == 'otp'
        ? 'After delivery open http://127.0.0.1:19439/otp with native browser_exec, use nekodot_secret_browser with the delivered reference, submit the form and verify CONFIDENTIAL_OTP_OK. Never read form values.'
        : mode.startsWith('login')
        ? 'After delivery open http://127.0.0.1:19439/login with native browser_exec, use nekodot_secret_browser with the delivered reference, submit the existing form and verify the page shows CONFIDENTIAL_LOGIN_OK. Do not read form values or use curl to perform login.'
        : 'After delivery verify with Python urllib GET http://127.0.0.1:19439/check using header X-QA-Key loaded from the approved env file. Print only HTTP status and the response marker, never the key. Reply CONFIDENTIAL_SERVICE_OK only on actual success.';
    await tester.enterText(
      find.byKey(const ValueKey('chat-input')),
      native
          ? 'Use skill_view to read ${const String.fromEnvironment('QA_NATIVE_SKILL')}. Complete its native secret setup through the confidential card. Never ask for the value in chat, never print it or read it into model context. After actual setup succeeds, reply CONFIDENTIAL_NATIVE_SECRET_OK.'
          : 'Read nekodot-secrets skill. Use terminal to run hermes secret request --spec \'${jsonEncode(spec)}\'. These are harmless acceptance values. Do not ask for them in chat. After creating the card, finish this turn and ask me to open it. $verification',
    );
    await tap(find.byTooltip('发送'));
    await until(
      () => (client.node.messages[conversationId] ?? []).any(
        (m) => m.kind == 'secret' && m.content['service'] == service,
      ),
      seconds: 300,
    );
    final requestCard = (client.node.messages[conversationId] ?? [])
        .where(
          (m) =>
              m.kind == 'secret' &&
              m.content['state'] == 'pending' &&
              m.content['service'] == service,
        )
        .last;
    final requestId = '${requestCard.content['requestId']}';
    final previousMessages = (client.node.messages[conversationId] ?? [])
        .map((m) => m.messageId)
        .toSet();
    final card = find.byWidgetPredicate(
      (w) => w is SecretCard && w.content['requestId'] == requestId,
    );
    await until(() => card.evaluate().isNotEmpty);
    final details = (await tester.runAsync(
      () => client.rpc('secrets.get', {'botId': botId, 'requestId': requestId}),
    ))!;
    final definitions = objects(object(details['request'])['fields']);
    final field = find.byKey(
      ValueKey('secret-field-${definitions.first['name']}'),
    );
    await until(() => field.evaluate().isNotEmpty);
    if (mode == 'native-cancel' || mode == 'native-timeout') {
      // The card asks only for the value; a request nobody answers is
      // cancelled by the Bot's side.
      if (mode == 'native-cancel') {
        await tester.runAsync(
          () => client.rpc('secrets.cancel', {
            'botId': botId,
            'requestId': requestId,
          }),
        );
      }
      await until(
        () => (client.node.messages[conversationId] ?? []).any(
          (m) =>
              m.kind == 'secret' &&
              m.content['requestId'] == requestId &&
              m.content['state'] ==
                  (mode == 'native-cancel' ? 'cancelled' : 'expired'),
        ),
        seconds: 160,
      );
      debugPrint('QA native secret $mode passed');
      binding.reportData = {
        'mode': mode,
        'requestId': requestId,
        'actualNativeRequest': true,
      };
      client.dispose();
      return;
    }
    if (mode == 'otp') {
      expect(find.byKey(const ValueKey('secret-save')), findsNothing);
    } else {
      expect(
        tester
            .widget<Checkbox>(find.byKey(const ValueKey('secret-save')))
            .value,
        isFalse,
      );
    }
    final values = {
      'QA_API_KEY': 'nekodot-qa-key-20261103',
      'PRIVATE_KEY': utf8.decode(
        base64Decode(const String.fromEnvironment('QA_SECRET_TEST_KEY_B64')),
      ),
      'identifier': 'nekodot-qa-user',
      'password': 'nekodot-qa-password-20261103',
      'code': '879421',
      'NEKODOT_SECRET_NATIVE_QA': 'nekodot-qa-native-value-20261103',
    };
    final inputController = tester.widget<TextField>(field).controller!;
    if (mode == 'api' || mode == 'login-save') {
      await tap(find.byKey(const ValueKey('secret-save')));
    }
    // One field at a time: each moves on to the next, the last one delivers.
    for (final (index, definition) in definitions.indexed) {
      final finder = find.byKey(ValueKey('secret-field-${definition['name']}'));
      await until(() => finder.evaluate().isNotEmpty);
      await Scrollable.ensureVisible(tester.element(finder), alignment: .4);
      await tester.enterText(
        finder,
        native
            ? 'nekodot-qa-native-value-20261103'
            : values['${definition['name']}']!,
      );
      await tester.pump();
      await tap(
        find.byKey(
          ValueKey(
            index == definitions.length - 1 ? 'secret-submit' : 'secret-next',
          ),
        ),
      );
    }
    await until(
      () => (client.node.messages[conversationId] ?? []).any(
        (m) =>
            m.kind == 'secret' &&
            m.content['requestId'] == requestId &&
            m.content['state'] == 'applied',
      ),
    );
    await until(
      () => (client.node.messages[conversationId] ?? []).any(
        (m) =>
            m.kind == 'text' &&
            !previousMessages.contains(m.messageId) &&
            m.status == 'done' &&
            '${m.content['text']}'.contains(switch (mode) {
              'private-key' => 'CONFIDENTIAL_KEY_FILE_OK',
              'login' || 'login-save' => 'CONFIDENTIAL_LOGIN_OK',
              'native' => 'CONFIDENTIAL_NATIVE_SECRET_OK',
              'otp' => 'CONFIDENTIAL_OTP_OK',
              _ => 'CONFIDENTIAL_SERVICE_OK',
            }),
      ),
      seconds: 300,
    );
    expect(
      jsonEncode(client.node.messages[conversationId])
          .contains('nekodot-qa-key-20261103'),
      isFalse,
    );
    expect(inputController.text, isEmpty);
    final metadata = (await tester.runAsync(
      () => client.rpc('secrets.list', {'botId': botId}),
    ))!;
    expect(
      objects(metadata['credentials'])
          .any((c) => c['service'] == requestCard.content['service']),
      mode == 'api' || mode == 'login-save',
    );
    debugPrint('QA encrypted real-model service configuration passed');
    binding.reportData = {
      'realModel': 'gpt-6.1-sol',
      'hermes': 'v0.22.5',
      'requestId': requestId,
      'encryptedDelivery': true,
      'actualServiceUse': true,
      'chatContainsSecret': false,
    };
    await tester.pump(const Duration(seconds: 1));
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(seconds: 1));
      await binding.takeScreenshot('confidential-card-$mode');
    }
    client.dispose();
  });
}
