import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/plugin_center.dart';
import 'package:nekodot_native/ui/design.dart';

class DocumentClient extends NekodotClient {
  DocumentClient() {
    selectedNodeId = 'document-node';
    node.bots = [
      {
        'botId': 'nk-docs00',
        'displayName': 'Document Dot',
        'avatar': {'color': '#E8603C', 'shape': 'dot'},
      },
    ];
  }
  Json? requested;
  @override
  Future<Json> rpc(
    String method, [
    Json params = const {},
    String? target,
  ]) async {
    if (method == 'extensions.list') {
      return {
        'entries': [
          {
            'id': 'tools/package',
            'name': 'Readable package title',
            'description': 'A local extension',
            'source': 'local',
            'category': 'development',
            'states': [
              {'botId': 'nk-docs00', 'installed': true},
            ],
          },
        ],
      };
    }
    requested = params;
    return {
      'content': '# Package README\n\nActual package documentation.',
      'files': ['README.md', 'scripts/'],
      'repository': 'https://github.com/NousResearch/hermes-agent',
    };
  }
}

void main() {
  testWidgets('catalog search keeps its query when the page resizes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = DocumentClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light, glass: true),
        home: PluginCenterPage(client: client, kind: 'plugins'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'no-match');
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'no-match',
    );
    await tester.enterText(find.byType(TextField), 'Readable');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('extension-tools/package')),
      findsOneWidget,
    );
  });
  testWidgets(
    'A phone opens installed plugin documentation, reads it and returns without losing the detail page',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = DocumentClient();
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: PluginCenterPage(client: client, kind: 'plugins'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('extension-tools/package')));
      await tester.pumpAndSettle();
      expect(client.requested, {
        'kind': 'plugins',
        'name': 'tools/package',
        'botId': 'nk-docs00',
      });
      expect(find.text('Package README'), findsOneWidget);
      expect(
        find.text('https://github.com/NousResearch/hermes-agent'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('完整内容'));
      await tester.tap(find.text('完整内容'));
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('完整内容'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('extension-tools/package')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      client.dispose();
    },
  );
}
