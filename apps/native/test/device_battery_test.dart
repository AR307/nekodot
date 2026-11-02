import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/client_commands.dart';

void main() {
  testWidgets('a chat left open refreshes its battery label after a minute', (
    tester,
  ) async {
    const channel = MethodChannel('dev.fluttercommunity.plus/battery');
    var percentage = 72;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => percentage);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final client = NekodotClient()..language = 'en';
    addTearDown(client.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DeviceBattery(client: client)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Device battery: 72%'), findsOneWidget);
    percentage = 71;
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Device battery: 71%'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
