import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:nekodot_native/main.dart' as product;
import 'package:nekodot_native/features/auth.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/settings.dart';

/// Run against a local Relay and Mailpit. No credentials or codes are logged.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows email registration, password login and existing node', (
    tester,
  ) async {
    final relay = Uri.parse(const String.fromEnvironment('RELAY_URL'));
    expect(relay.host, anyOf('127.0.0.1', 'localhost'));
    expect(const String.fromEnvironment('LOCAL_ACCOUNT_FILE'), isNotEmpty);
    expect(const String.fromEnvironment('LOCAL_EVIDENCE'), isNotEmpty);
    final prefs = await SharedPreferences.getInstance();
    final notificationPrompt = !prefs.containsKey('notification-requested');
    await product.main();
    Future<void> until(bool Function() condition) async {
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Local Windows account journey timed out');
        }
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
    }

    await until(() => find.byType(product.NekodotApp).evaluate().isNotEmpty);
    final client = tester
        .widget<product.NekodotApp>(find.byType(product.NekodotApp))
        .client;
    expect(client.origin.host, anyOf('127.0.0.1', 'localhost'));
    await until(
      () =>
          find.byType(AuthPage).evaluate().isNotEmpty ||
          find.byType(HomePage).evaluate().isNotEmpty,
    );
    if (notificationPrompt) {
      await until(
        () =>
            find.byType(AlertDialog).evaluate().isNotEmpty ||
            client.notificationError.isNotEmpty,
      );
      if (find.byType(AlertDialog).evaluate().isNotEmpty) {
        await tester.tap(
          find.widgetWithText(TextButton, client.tr('继续', 'Continue')),
        );
      }
    }
    await tester.runAsync(
      () => client.preferences(locale: 'zh', appearance: 'light'),
    );
    if (client.token != null) await tester.runAsync(client.clearSession);
    await until(() => find.byType(AuthPage).evaluate().isNotEmpty);
    if (Platform.isWindows) await windowManager.setSize(const Size(1280, 900));
    await tester.pump(const Duration(milliseconds: 400));

    final email =
        'windows-auth-${DateTime.now().millisecondsSinceEpoch}@nekodot.test';
    final random = Random.secure();
    final password =
        'NekoDOT-${List.generate(24, (_) => random.nextInt(36).toRadixString(36)).join()}';
    Future<void> fillCredentials(String address, String secret) async {
      await tester.enterText(find.byKey(const ValueKey('auth-email')), address);
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        secret,
      );
    }

    Future<void> tapKey(String key) async {
      final button = find.byKey(ValueKey(key));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 300));
    }

    final output = Directory(const String.fromEnvironment('LOCAL_EVIDENCE'));
    Future<void> screenshot(String name) async {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        await output.create(recursive: true);
        final view = tester.binding.renderViews.first;
        final image = await (view.debugLayer! as OffsetLayer).toImage(
          Offset.zero & tester.view.physicalSize,
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${output.path}/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await tapKey('auth-switch-mode');
    await fillCredentials(email, password);
    await tapKey('auth-submit');
    expect(find.text('请输入 6 位邮箱验证码'), findsOneWidget);
    await tapKey('auth-send-code');
    await until(() => find.textContaining('10 分钟内有效').evaluate().isNotEmpty);
    expect(find.byKey(const ValueKey('auth-code')), findsOneWidget);
    await screenshot('windows-register');
    final verificationCode = await tester.runAsync(() async {
      for (var attempt = 0; attempt < 30; attempt++) {
        final inbox = jsonDecode(
          (await http.get(Uri.parse('http://127.0.0.1:8025/api/v1/messages')))
              .body,
        ) as Map<String, dynamic>;
        for (final message in inbox['messages'] as List) {
          if (!(message['To'] as List).any((to) => to['Address'] == email)) {
            continue;
          }
          final detail = jsonDecode(
            (await http.get(
              Uri.parse(
                'http://127.0.0.1:8025/api/v1/message/${message['ID']}',
              ),
            )).body,
          ) as Map<String, dynamic>;
          final code = RegExp(r'验证码是 (\d{6})')
              .firstMatch(detail['Text'] as String)
              ?.group(1);
          if (code != null) return code;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      throw StateError(
        'Local test mailbox did not receive the verification email',
      );
    });
    await tester.enterText(
      find.byKey(const ValueKey('auth-code')),
      verificationCode!,
    );
    await tapKey('auth-submit');
    await until(
      () => client.ready && find.byType(HomePage).evaluate().isNotEmpty,
    );
    expect(client.me?['email'] ?? client.me?['user']?['email'], email);
    await tester.runAsync(client.logout);
    await until(() => find.byType(AuthPage).evaluate().isNotEmpty);
    expect(find.byKey(const ValueKey('auth-code')), findsNothing);
    await fillCredentials(email, password);
    await tapKey('auth-submit');
    await until(
      () => client.ready && find.byType(HomePage).evaluate().isNotEmpty,
    );
    await tester.runAsync(client.logout);
    await until(() => find.byType(AuthPage).evaluate().isNotEmpty);

    // Leave the deployed client signed in to the user's existing local account.
    final account = await tester.runAsync(
      () async => jsonDecode(
        await File(const String.fromEnvironment('LOCAL_ACCOUNT_FILE'))
            .readAsString(),
      ) as Map<String, dynamic>,
    );
    await fillCredentials(
      account!['email'] as String,
      account['password'] as String,
    );
    await tapKey('auth-submit');
    await until(() => client.ready && client.online && !client.node.syncing);
    final providers = await tester.runAsync(() => client.rpc('providers.list'));
    expect(providers, isNotNull);
    await until(() => find.byTooltip('账户').evaluate().isNotEmpty);
    await tester.tap(find.byTooltip('账户'));
    await until(
      () => find
          .widgetWithText(PopupMenuItem<String>, '设置')
          .evaluate()
          .isNotEmpty,
    );
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, '设置'));
    await until(() => find.byType(SettingsPage).evaluate().isNotEmpty);
    await screenshot('windows-settings');
    expect(tester.takeException(), isNull);
    final report = {
      'platform': Platform.operatingSystem,
      'relay': client.origin.toString(),
      'emailCodeRegistration': true,
      'missingCodeBlockedLocally': true,
      'passwordLoginAfterLogout': true,
      'existingAccountLogin': true,
      'nodeOnline': client.online,
      'snapshotSynchronized': !client.node.syncing,
      'hermesProvidersRpc': true,
      'modelReplyTested': false,
    };
    binding.reportData = report;
    await tester.runAsync(
      () => File('${output.path}/windows-auth-journey.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(report)),
    );
  });
}
