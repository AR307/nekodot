import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/bot_editor.dart';
import 'package:nekodot_native/features/commands.dart';
import 'package:nekodot_native/features/files.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/ui/design.dart';

// Actual Flutter UI + product Relay/Node; Hermes replies replay native recordings.
// File-picker interaction and real-model image recognition are separate checks.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native commands, files and group everyone', (tester) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final client = NekodotClient();
    await tester.runAsync(() async {
      final login = await client.account.request(
        '/auth/login',
        method: 'POST',
        body: {
          'email': const String.fromEnvironment('QA_EMAIL'),
          'password': const String.fromEnvironment('QA_PASSWORD'),
        },
      );
      client.account.token = '${login['token']}';
      await client.bootstrap();
      await client.selectNode(const String.fromEnvironment('QA_NODE'));
    });
    Future<void> until(bool Function() ready) async {
      final end = DateTime.now().add(const Duration(seconds: 45));
      while (!ready() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(ready(), isTrue);
    }

    Future<void> tap(Finder target) async {
      await until(() => target.evaluate().length == 1);
      await Scrollable.ensureVisible(tester.element(target), alignment: .5);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(target);
      await tester.pump(const Duration(milliseconds: 200));
    }

    Future<void> shot(String name) async {
      if (!Platform.isWindows) return;
      await tester.pump(const Duration(milliseconds: 300));
      final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
      await tester.runAsync(() async {
        final image = await layer.toImage(
          Offset.zero & tester.view.physicalSize,
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('../../docs/evidence/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await until(() => client.online && client.node.bots.length == 2);
    final bot = client.node.bots.firstWhere((b) => b['handle'] == 'researcher');
    final dm = client.node.conversations.firstWhere(
      (c) => c['botId'] == bot['botId'],
    );
    final id = '${dm['conversationId']}';
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appTheme(Brightness.light),
        navigatorObservers: [nativeRoutes],
        home: HomePage(client: client),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tap(find.byKey(ValueKey('conversation-$id')));
    final input = find.byKey(const ValueKey('chat-input'));
    await tester.enterText(input, '/profile');
    await until(
      () =>
          find.byType(CommandPalette).evaluate().isNotEmpty &&
          find.text('/profile').evaluate().isNotEmpty,
    );
    await shot('composer-native-commands');
    await tap(
      find.descendant(
        of: find.byType(CommandPalette),
        matching: find.widgetWithText(ListTile, '/profile'),
      ),
    );
    await tap(find.byTooltip('发送'));
    await until(
      () => client.node.messages[id]!.any(
        (m) =>
            m.kind == 'system' && '${m.content['text']}'.contains('Profile:'),
      ),
    );
    await until(() => tester.widget<TextField>(input).controller!.text.isEmpty);

    final attachments = <Json>[];
    await tester.runAsync(() async {
      for (final (name, data) in [
        ('中文资料.txt', utf8.encode('NEKODOT_COMPOSER_UI')),
        (
          '图片.png',
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/lYQAAAAASUVORK5CYII=',
          ),
        ),
      ]) {
        final created = await client.rpc('imports.create', {});
        final response = await client.account.transport.put(
          client.account
              .url(
                '/api/nodes/${client.selectedNodeId}/imports/${created['importId']}',
              )
              .replace(queryParameters: {'path': name, 'offset': '0'}),
          headers: {
            'Authorization': 'Bearer ${client.account.token}',
            'Content-Type': 'application/octet-stream',
          },
          body: data,
        );
        expect(response.statusCode, 200);
        attachments.add(
          await client.rpc('files.receive', {
            'conversationId': id,
            'importId': created['importId'],
            'path': name,
          }),
        );
      }
      client.attachmentDrafts['${client.selectedNodeId}:$id'] = List<Json>.of(
        attachments,
      );
      await client.loadMessages(id);
    });
    final textFileId = attachments.first['fileId'];
    await tester.pump();
    expect(find.textContaining('中文资料.txt ·'), findsOneWidget);
    final previous = client.node.messages[id]!
        .where((m) => m.author.type == 'bot')
        .length;
    await tap(find.byTooltip('发送'));
    await until(
      () =>
          client.node.messages[id]!
                  .where((m) => m.author.type == 'bot')
                  .length >
              previous &&
          client.node.activities[id]?.state == 'idle',
    );
    await until(() => find.text('中文资料.txt').evaluate().isNotEmpty);
    await until(
      () =>
          client.attachmentDrafts['${client.selectedNodeId}:$id']?.isEmpty ==
          true,
    );
    await shot('composer-native-files');
    await tap(
      find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is FileCard && w.fileId == textFileId,
        ),
        matching: find.byType(InkWell),
      ),
    );
    await until(
      () =>
          find.byType(FileViewer).evaluate().isNotEmpty &&
          find.textContaining('NEKODOT_COMPOSER_UI').evaluate().isNotEmpty,
    );
    await shot('composer-native-preview');
    await tap(find.byTooltip('关闭').last);
    await tester.pump(const Duration(milliseconds: 300));

    final previousGroups = client.node.groups.map((g) => g['groupId']).toSet();
    await tap(find.byTooltip('新建'));
    await tap(find.text('新建群组'));
    final name = find.descendant(
      of: find.widgetWithText(LabeledField, '名称'),
      matching: find.byType(TextField),
    );
    await tester.enterText(name, 'Everyone journey');
    final memberCount = find.byType(CheckboxListTile).evaluate().length;
    for (var i = 0; i < memberCount; i++) {
      await tap(find.byType(CheckboxListTile).at(i));
    }
    await tap(find.text('保存'));
    await until(
      () =>
          find.byType(BotEditor).evaluate().isEmpty &&
          client.node.groups.any((g) => !previousGroups.contains(g['groupId'])),
    );
    final group = client.node.groups.firstWhere(
      (g) => !previousGroups.contains(g['groupId']),
    );
    final conversation = client.node.conversations.firstWhere(
      (c) => c['groupId'] == group['groupId'],
    );
    final groupId = '${conversation['conversationId']}';
    await until(
      () => find.byKey(ValueKey('conversation-$groupId')).evaluate().isNotEmpty,
    );
    await tap(find.byKey(ValueKey('conversation-$groupId')));
    await tester.enterText(input, '@');
    await tap(find.text('所有成员'));
    expect(tester.widget<TextField>(input).controller!.text, '@everyone ');
    await tester.enterText(input, '@everyone hello');
    await tap(find.byTooltip('发送'));
    await until(
      () =>
          client.node.messages[groupId]!
                  .where((m) => m.author.type == 'bot')
                  .map((m) => m.author.id)
                  .toSet()
                  .length ==
              2 &&
          client.node.activities[groupId]?.state == 'idle',
    );
    final response = await tester.runAsync(
      () => http.get(client.account.url('/qa/inspect')),
    );
    final runs = objects(object(jsonDecode(response!.body))['runs']);
    final upload = runs.firstWhere(
      (r) => '${r['input']}'.contains('[Attached file:'),
    );
    expect(upload['nativeInput'], isA<List>());
    await shot('composer-native-everyone');
    await tester.pumpWidget(const SizedBox.shrink());
    client.dispose();
  });
}
