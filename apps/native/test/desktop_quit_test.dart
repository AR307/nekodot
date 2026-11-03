import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/auth.dart';
import 'package:nekodot_native/features/settings.dart';
import 'package:nekodot_native/ui/design.dart';

void main() {
  for (final login in [true, false]) {
    testWidgets(
      'Windows ${login ? 'login' : 'settings'} quits rather than hiding to tray',
      (tester) async {
        tester.view.physicalSize = const Size(1180, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final calls = <String>[];
        const channel = MethodChannel('window_manager');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            calls.add(call.method);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final client = NekodotClient();
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(Brightness.light),
            home: login
                ? AuthPage(client: client)
                : SettingsPage(client: client),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('quit-application')));
        await tester.pump();
        expect(calls, contains('destroy'));
        expect(calls, isNot(contains('hide')));
        await tester.pumpWidget(const SizedBox.shrink());
        client.dispose();
      },
      skip: !Platform.isWindows,
    );
  }
}
