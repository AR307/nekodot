import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/desktop_control.dart';
import 'package:nekodot_native/ui/design.dart';

class DesktopClient extends NekodotClient {
  bool enabled = false;
  final writes = <bool>[];
  DesktopClient() {
    selectedNodeId = 'desktop-node';
    connection.ready = true;
    node.online = true;
  }
  @override
  Future<Json> rpc(
    String method, [
    Json params = const {},
    String? target,
  ]) async {
    switch (method) {
      case 'bots.desktopControl':
        if (params['enabled'] is bool) {
          enabled = params['enabled'] as bool;
          writes.add(enabled);
        }
        return {'enabled': enabled};
      case 'desktop.status':
        return {
          'platform': 'win32',
          'computerUse': false,
          'host': 'desktop',
          'desktopControl': {
            'platformSupported': true,
            'installed': true,
            'ready': true,
            'canGrant': false,
            'detail': '',
          },
        };
      default:
        throw StateError('Unexpected test request: $method');
    }
  }
}

void main() {
  testWidgets('A Bot is switched on to operate this computer only on request', (
    tester,
  ) async {
    final client = DesktopClient();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Scaffold(
          body: DesktopControlTile(client: client, botId: 'nk-desk00'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('bot-desktop-control'));
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.textContaining('可用'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(client.writes, [true]);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
  });
}
