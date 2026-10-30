import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/auth.dart';
import 'package:nekodot_native/ui/design.dart';

void main() {
  testWidgets(
    'An Android-sized account form scrolls and keeps password login separate from email verification',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = NekodotClient();
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: AuthPage(client: client),
        ),
      );
      expect(find.text('登录'), findsOneWidget);
      expect(find.text('6 位验证码'), findsNothing);
      await tester.ensureVisible(find.text('创建账号'));
      await tester.tap(find.text('创建账号'));
      await tester.pumpAndSettle();
      expect(find.text('6 位验证码'), findsOneWidget);
      expect(find.text('获取验证码'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('已有账号？登录'));
      await tester.tap(find.text('已有账号？登录'));
      await tester.pumpAndSettle();
      expect(find.text('6 位验证码'), findsNothing);
      client.dispose();
    },
  );
}
