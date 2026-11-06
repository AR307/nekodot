import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/auth.dart';
import 'package:nekodot_native/ui/design.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native login errors against an isolated real Relay', (
    tester,
  ) async {
    const baseline = bool.fromEnvironment('QA_BASELINE');
    const email = String.fromEnvironment('QA_EMAIL');
    const password = String.fromEnvironment('QA_PASSWORD');
    const evidence = String.fromEnvironment('QA_EVIDENCE');
    final client = NekodotClient(vault: MemoryVault());
    expect(client.origin.host, anyOf('127.0.0.1', 'localhost'));
    expect(email.isNotEmpty && password.isNotEmpty, isTrue);
    final capture = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: RepaintBoundary(
          key: capture,
          child: AuthPage(client: client),
        ),
      ),
    );
    Future<void> settle(bool Function() done) async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (!done() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(done(), isTrue);
    }

    Future<void> shot(String name) async {
      if (evidence.isEmpty) return;
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() async {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
        final directory = Platform.isAndroid
            ? '${(await getExternalStorageDirectory())!.path}/login-evidence'
            : evidence;
        await Directory(directory).create(recursive: true);
        await File('$directory/$name.png').writeAsBytes(bytes);
        image.dispose();
      });
    }

    Future<void> submit(String address, String secret) async {
      await tester.enterText(find.byKey(const ValueKey('auth-email')), address);
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        secret,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pump(const Duration(milliseconds: 100));
    }

    for (final (name, address, secret) in [
      ('short-password', email, 'x'),
      ('long-password', email, 'incorrect-test-password'),
      ('unknown-email', 'missing@example.test', 'incorrect-test-password'),
    ]) {
      await submit(address, secret);
      final expected = baseline
          ? name == 'short-password'
                ? '密码至少需要 8 个字符'
                : 'Email or password incorrect'
          : '密码或邮箱错误';
      await settle(() => find.text(expected).evaluate().isNotEmpty);
      await shot('${baseline ? 'before' : 'after'}-$name');
      expect(client.token, isNull);
    }
    await submit(email, password);
    await settle(() => client.ready);
    expect(client.me!['user']['email'], email);
    await tester.runAsync(client.logout);
    if (!baseline) {
      await submit(email, '');
      expect(find.text('请输入密码'), findsOneWidget);
      await submit('not-an-email', 'incorrect-test-password');
      expect(find.text('请输入有效的邮箱'), findsOneWidget);
      client.language = 'en';
      await submit(email, 'incorrect-test-password');
      await settle(
        () => find.text('Email or password incorrect').evaluate().isNotEmpty,
      );
      await shot('after-english');
      client.language = 'zh';
      // The actual Relay limiter must not be presented as a wrong password.
      for (var attempt = 0; attempt < 10; attempt++) {
        await submit(email, 'incorrect-test-password');
        await settle(
          () =>
              tester
                  .widget<FilledButton>(
                    find.byKey(const ValueKey('auth-submit')),
                  )
                  .onPressed !=
              null,
        );
        if (find.text('请求过于频繁，请稍后重试').evaluate().isNotEmpty) break;
      }
      expect(find.text('请求过于频繁，请稍后重试'), findsOneWidget);
      await shot('after-rate-limit');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    client.dispose();
    binding.reportData = {
      'platform': Platform.operatingSystem,
      'baseline': baseline,
      'wrongPassword': true,
      'unknownEmail': true,
      'realPasswordLogin': true,
    };
  });
}
