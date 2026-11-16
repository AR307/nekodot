import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nekodot_native/data/client.dart';

import 'package:nekodot_native/features/auth.dart';
import 'package:nekodot_native/ui/design.dart';

void main() {
  testWidgets('registration requires a code before contacting the Relay', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final client = NekodotClient(
      transport: MockClient((request) async {
        if (request.url.path == '/api/auth/providers') {
          return http.Response('{"providers":[]}', 200);
        }
        requests.add(request);
        return http.Response('{"error":{"message":"Invalid input"}}', 400);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: AuthPage(client: client),
      ),
    );
    await tester.tap(find.text('创建账号'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      'person@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      'example-password',
    );
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('请输入 6 位邮箱验证码'), findsOneWidget);
    expect(requests, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    client.dispose();
  });

  testWidgets('sending a code validates the email without requiring a code', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final client = NekodotClient(
      transport: MockClient((request) async {
        if (request.url.path == '/api/auth/providers') {
          return http.Response('{"providers":[]}', 200);
        }
        requests.add(request);
        return http.Response('{"retryAfter":60}', 200);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: AuthPage(client: client),
      ),
    );
    await tester.tap(find.text('创建账号'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      'invalid-email',
    );
    await tester.ensureVisible(find.text('获取验证码'));
    await tester.tap(find.text('获取验证码'));
    await tester.pumpAndSettle();
    expect(find.text('请输入有效的邮箱'), findsOneWidget);
    expect(requests, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      'person@example.test',
    );
    await tester.tap(find.text('获取验证码'));
    await tester.pumpAndSettle();
    expect(requests.single.url.path, '/api/auth/code');
    expect(find.text('请输入 6 位邮箱验证码'), findsNothing);
    expect(find.text('60s'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.dispose();
  });

  testWidgets('Google and GitHub appear only as the Relay offers them', (
    tester,
  ) async {
    Future<void> open(String providers) async {
      final client = NekodotClient(
        transport: MockClient(
          (request) async => http.Response(
            '{"providers":$providers}',
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: AuthPage(client: client),
        ),
      );
      await tester.pumpAndSettle();
      addTearDown(client.dispose);
    }

    await open('["google","github"]');
    expect(find.byKey(const ValueKey('auth-oauth-google')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-oauth-github')), findsOneWidget);
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);
    // Resetting a password is about the email account only.
    await tester.tap(find.text('忘记密码'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('auth-oauth-google')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());

    await open('["github"]');
    expect(find.byKey(const ValueKey('auth-oauth-google')), findsNothing);
    expect(find.byKey(const ValueKey('auth-oauth-github')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());

    await open('[]');
    expect(find.text('或'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
