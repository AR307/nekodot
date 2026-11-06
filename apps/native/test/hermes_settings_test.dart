import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/data/hermes_zh.dart';
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
            'group': 'model',
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
            'group': 'model',
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
            'group': 'run',
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
      final client = SettingsClient()..prefs.language = 'en';
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: Scaffold(
            body: HermesSettings(client: client, botId: 'nk-settings'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Advanced settings stay hidden until explicitly opened.
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byKey(const ValueKey('advanced-settings')));
      await tester.pumpAndSettle();
      expect(find.text('Model'), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);
      expect(find.text('Voice'), findsNothing);
      expect(find.text('model_context_length'), findsNothing);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/ui_refinements_settings_390.png'),
      );
      await tester.tap(find.byKey(const ValueKey('settings-group-model')));
      await tester.pumpAndSettle();
      expect(find.text('model_context_length'), findsNothing);
      expect(find.text('compression.enabled'), findsOneWidget);
      expect(find.text('agent.api_key'), findsNothing);
      expect(
        find.textContaining('Change this in Bot model settings'),
        findsNothing,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'api_key');
      await tester.pumpAndSettle();
      expect(find.text('agent.api_key'), findsOneWidget);
      expect(find.text('configured-secret'), findsNothing);

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
      await tester.enterText(find.byType(TextField), 'model_context_length');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Change this in Bot model settings'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      client.dispose();
    },
  );

  testWidgets('In Chinese a setting leads with its name and keeps its key', (
    tester,
  ) async {
    final client = SettingsClient()..prefs.language = 'zh';
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Scaffold(
          body: HermesSettings(client: client, botId: 'nk-settings'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final (name, note) = hermesSettingZh['compression.enabled']!;
    await tester.tap(find.byKey(const ValueKey('advanced-settings')));
    await tester.pumpAndSettle();
    // Found by its Chinese name as well as by its key.
    await tester.enterText(find.byType(TextField), name);
    await tester.pumpAndSettle();
    final tile = find.widgetWithText(SwitchListTile, name);
    expect(tile, findsOneWidget);
    expect(
      find.descendant(of: tile, matching: find.textContaining(note)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: tile,
        matching: find.textContaining('compression.enabled'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    client.dispose();
  });
}
