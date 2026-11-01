import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/hermes_settings.dart';
import 'package:nekodot_native/ui/design.dart';

class SettingsClient extends NekodotClient {
  bool compressionEnabled = true;
  final saves = <Json>[];

  @override
  Future<Json> rpc(
    String method, [
    Json params = const {},
    String? target,
  ]) async {
    if (method == 'hermes.settings.set') {
      saves.add(params);
      compressionEnabled = params['value'] as bool;
      return {'key': params['key'], 'saved': true};
    }
    if (method == 'hermes.settings.get') {
      return {
        'botId': 'nk-settings',
        'scope': 'Hermes profile',
        'categories': ['general', 'compression', 'security'],
        'fields': [
          {
            'key': 'model_context_length',
            'type': 'number',
            'description': 'Context window override',
            'category': 'general',
            'value': 8192,
            'sensitive': false,
            'editable': false,
            'configured': true,
          },
          {
            'key': 'compression.enabled',
            'type': 'boolean',
            'description': 'Enable native context compression',
            'category': 'compression',
            'value': compressionEnabled,
            'sensitive': false,
            'editable': true,
            'configured': true,
          },
          {
            'key': 'agent.api_key',
            'type': 'string',
            'description': 'Credential managed by Hermes',
            'category': 'security',
            'value': null,
            'sensitive': true,
            'editable': false,
            'configured': true,
          },
        ],
      };
    }
    throw StateError('Unexpected RPC: $method');
  }
}

void main() {
  testWidgets(
    'A phone can find and save native Hermes settings without revealing credentials',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fontLoader = FontLoader('Nunito')
        ..addFont(rootBundle.load('assets/fonts/nunito-400.ttf'))
        ..addFont(rootBundle.load('assets/fonts/nunito-600.ttf'))
        ..addFont(rootBundle.load('assets/fonts/nunito-700.ttf'))
        ..addFont(rootBundle.load('assets/fonts/nunito-800.ttf'));
      await fontLoader.load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final client = SettingsClient()..language = 'en';
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: Scaffold(
            body: HermesSettings(client: client, botId: 'nk-settings'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('model_context_length'), findsOneWidget);
      expect(find.text('agent.api_key'), findsOneWidget);
      expect(
        find.textContaining('Change this in Bot model settings'),
        findsOneWidget,
      );
      expect(find.text('configured-secret'), findsNothing);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/hermes_settings_390.png'),
      );

      await tester.enterText(find.byType(TextField), 'compression');
      await tester.pumpAndSettle();
      expect(find.text('compression.enabled'), findsOneWidget);
      expect(find.text('model_context_length'), findsNothing);
      expect(find.text('agent.api_key'), findsNothing);

      final setting = find.ancestor(
        of: find.text('compression.enabled'),
        matching: find.byType(SwitchListTile),
      );
      await tester.tap(setting);
      await tester.pumpAndSettle();
      expect(client.saves, [
        {'botId': 'nk-settings', 'key': 'compression.enabled', 'value': false},
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      client.dispose();
    },
  );
}
