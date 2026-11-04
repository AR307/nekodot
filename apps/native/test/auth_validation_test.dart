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
}
