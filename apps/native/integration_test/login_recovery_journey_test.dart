import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/auth.dart';
import 'package:nekodot_native/ui/design.dart';
import 'package:path_provider/path_provider.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

/// Real Relay account validation and an actual local proxy/connection outage.
/// QA_CONTROL belongs only to the private test harness, never the product.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('unverified account and login recovery after network failures', (
    tester,
  ) async {
    const control = String.fromEnvironment('QA_CONTROL');
    const password = String.fromEnvironment('QA_PASSWORD');
    final client = NekodotClient(vault: MemoryVault());
    expect(client.account.origin.host, '127.0.0.1');
    final capture = GlobalKey();
    Future<void> mode(String name) async {
      final response = await tester.runAsync(
        () => http.post(Uri.parse('$control/$name')),
      );
      expect(response!.statusCode, 200);
    }

    Future<void> mount() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: RepaintBoundary(
            key: capture,
            child: AuthPage(client: client),
          ),
        ),
      );
    }

    Future<void> until(bool Function() ready) async {
      final end = DateTime.now().add(const Duration(seconds: 45));
      while (!ready() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(ready(), isTrue);
    }

    Future<void> submit(String email) async {
      await tester.enterText(find.byKey(const ValueKey('auth-email')), email);
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        password,
      );
      final submit = find.byKey(const ValueKey('auth-submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
    }

    Future<void> shot(String name) async {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        final image =
            await (capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Platform.isAndroid
            ? '${(await getExternalStorageDirectory())!.path}/login-recovery'
            : const String.fromEnvironment('QA_EVIDENCE');
        await Directory(directory).create(recursive: true);
        await File('$directory/$name.png')
            .writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      });
    }

    try {
      await mode('up');
      await mount();
      await submit(const String.fromEnvironment('QA_UNVERIFIED'));
      await until(
        () => find.byKey(const ValueKey('auth-code')).evaluate().isNotEmpty,
      );
      expect(find.text('验证邮箱'), findsOneWidget);
      expect(find.text('密码或邮箱错误'), findsNothing);
      expect(client.account.token, isNull);
      await shot('unverified');
      for (final scenario in [
        ('bad_gateway', '服务暂时不可用'),
        ('timeout', '请求超时，请重试'),
        ('offline', '无法连接服务器'),
      ]) {
        await mode(scenario.$1);
        await mount();
        await submit(const String.fromEnvironment('QA_EMAIL'));
        await until(() => find.text(scenario.$2).evaluate().isNotEmpty);
        expect(find.text('密码或邮箱错误'), findsNothing);
        expect(client.account.token, isNull);
        await shot(scenario.$1);
      }
      await mode('up');
      await submit(const String.fromEnvironment('QA_EMAIL'));
      await until(() => client.connection.ready);
      expect(
        client.account.me!['user']['email'],
        const String.fromEnvironment('QA_EMAIL'),
      );
      binding.reportData = {
        'platform': Platform.operatingSystem,
        'realRelay': true,
        'unverified': true,
        'proxy502': true,
        'timeout': true,
        'offline': true,
        'recoveredLogin': true,
      };
      debugPrint(
        'QA login recovery passed: unverified, 502, timeout, offline, recovery',
      );
    } finally {
      await mode('up');
      await tester.pumpWidget(const SizedBox.shrink());
      client.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
