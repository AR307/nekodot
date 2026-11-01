import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/auth.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

void main() {
  testWidgets(
    'login header reaches the native window gesture without covering language or form',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async {
          calls.add(call.method);
          return call.method.startsWith('is') ? false : null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          null,
        ),
      );
      final client = NekodotClient();
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          builder: (_, child) => WindowChrome(child: child!),
          home: AuthPage(client: client),
        ),
      );
      await tester.dragFrom(const Offset(250, 20), const Offset(160, 70));
      await tester.pump();
      expect(calls, contains('startDragging'));
      final language = find.text('EN');
      expect(
        tester.getRect(language).right,
        lessThan(1000 - WindowChrome.reserved(tester.element(language))),
      );
      await tester.tap(find.byKey(const ValueKey('auth-email')));
      await tester.enterText(
        find.byKey(const ValueKey('auth-email')),
        'test@example.test',
      );
      expect(find.text('test@example.test'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox.shrink());
      client.dispose();
    },
  );
}
