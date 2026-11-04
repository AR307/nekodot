import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/chat.dart';
import 'package:nekodot_native/features/files.dart';
import 'package:nekodot_native/platform/file_actions.dart';
import 'package:nekodot_native/ui/design.dart';

class PreviewClient extends NekodotClient {
  PreviewClient()
    : super(
        transport: MockClient((_) async => http.Response('file body', 200)),
      ) {
    selectedNodeId = 'node';
    ready = true;
    node.online = true;
    node.bots = [
      {
        'botId': 'bot',
        'displayName': 'Preview bot',
        'handle': 'preview',
        'avatar': {'shape': 'bunny', 'color': '#E8603C'},
      },
    ];
    node.conversations = [
      {'conversationId': 'dm', 'kind': 'dm', 'botId': 'bot'},
    ];
    node.messages['dm'] = [
      {
        'messageId': 'message',
        'seq': 1,
        'kind': 'text',
        'status': 'done',
        'author': {'type': 'bot', 'id': 'bot'},
        'content': {
          'text': 'Done\nMEDIA:C:\\scratch\\source.txt',
          'files': ['file'],
        },
      },
    ];
  }
  @override
  Future<Json> rpc(
    String method, [
    Json params = const {},
    String? target,
  ]) async => switch (method) {
    'files.get' => {
      'fileId': 'file',
      'name': 'source.txt',
      'mime': 'text/plain',
      'available': true,
      'size': 9,
    },
    'messages.list' => {'messages': node.messages['dm']},
    _ => throw StateError('Unexpected RPC: $method'),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'download stays with the selected file node after node switching',
    () async {
      final client = NekodotClient(
        transport: MockClient((request) async {
          expect(request.url.path, '/api/nodes/original/files/drawing');
          expect(request.headers['Authorization'], 'Bearer test-token');
          return http.Response('<svg/>', 200);
        }),
      )..token = 'test-token';
      client.selectedNodeId = 'other';
      expect(
        utf8.decode(await downloadFile(client, 'drawing', nodeId: 'original')),
        '<svg/>',
      );
      client.dispose();
    },
  );

  test('SVG is an isolated image document and preserves filters verbatim', () {
    const source =
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<filter id="blur"><feGaussianBlur stdDeviation="3"/></filter>'
        '<script>alert(1)</script></svg>';
    final document = svgPreviewDocument(utf8.encode(source), scale: 1.5);
    expect(document, contains("script-src 'none'"));
    expect(document, contains("default-src 'none'"));
    expect(document, contains('<img'));
    expect(document, isNot(contains('<script>')));
    final encoded = RegExp(r'data:image/svg\+xml;base64,([^"\s]+)')
        .firstMatch(document)!
        .group(1)!;
    expect(utf8.decode(base64Decode(encoded)), source);
    expect(document, contains('150vw'));
    expect(isSvgFile({'mime': 'image/svg+xml; charset=utf-8'}), isTrue);
    expect(
      isSvgFile({'name': 'DRAWING.SVG', 'mime': 'application/octet-stream'}),
      isTrue,
    );
  });

  test(
    'delivery markers are hidden only with delivered attachments, outside code',
    () {
      const text =
          '画好了\n\nMEDIA:C:\\scratch\\portrait.svg\n\n'
          '```text\nMEDIA:example.svg\n```';
      expect(readableMessageText(text, hasFiles: false), text);
      expect(
        readableMessageText(text, hasFiles: true),
        '画好了\n\n\n```text\nMEDIA:example.svg\n```',
      );
    },
  );

  test(
    'external copy names cannot escape their directory or use device names',
    () {
      expect(safeAttachmentName(r'..\other\portrait.svg'), 'portrait.svg');
      expect(safeAttachmentName('../../portrait.svg'), 'portrait.svg');
      expect(safeAttachmentName('CON.svg'), '_CON.svg');
      expect(safeAttachmentName('bad:name.svg. '), 'bad_name.svg');
      expect(safeAttachmentName('..'), 'attachment');
    },
  );

  test(
    'Windows open-with passes a literal path to the native channel',
    () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('app.nekodot/files'), (
            call,
          ) async {
            received = call;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('app.nekodot/files'),
              null,
            ),
      );
      const path = r'C:\private\drawing & $(literal).svg';
      await WindowsFileActions.invoke('openWith', path);
      expect(received!.method, 'openWith');
      expect(received!.arguments, {'path': path});
    },
  );

  testWidgets(
    'embedded preview keeps its host and has source, open and close controls',
    (tester) async {
      final client = NekodotClient(
        transport: MockClient(
          (_) async => http.Response('original source', 200),
        ),
      )..selectedNodeId = 'node';
      await tester.binding.setSurfaceSize(const Size(1180, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      bool closed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: Scaffold(
            body: Row(
              children: [
                const Expanded(child: Text('chat stays here')),
                SizedBox(
                  width: 420,
                  child: FilePage(
                    client: client,
                    nodeId: 'node',
                    embedded: true,
                    file: {
                      'fileId': 'text',
                      'name': 'source.txt',
                      'mime': 'text/plain',
                      'available': true,
                      'size': 15,
                    },
                    onClose: () => closed = true,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('original source'), findsOneWidget);
      expect(find.text('chat stays here'), findsOneWidget);
      await tester.tap(find.byTooltip('打开文件菜单'));
      await tester.pumpAndSettle();
      expect(find.text('用系统默认应用打开'), findsOneWidget);
      await tester.tapAt(const Offset(100, 100));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭预览'));
      expect(closed, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      client.dispose();
    },
  );

  testWidgets(
    'chat opens a side preview, resizing retains it, closing keeps the draft',
    (tester) async {
      final client = PreviewClient();
      await tester.binding.setSurfaceSize(const Size(1180, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: HomePage(client: client),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('conversation-dm')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('chat-input')),
        'unsent draft',
      );
      expect(find.textContaining('MEDIA:', findRichText: true), findsNothing);
      await tester.tap(find.byType(FileCard));
      await tester.pumpAndSettle();
      expect(find.byType(ChatPage), findsOneWidget);
      expect(find.byType(FilePage), findsOneWidget);
      expect(tester.widget<FilePage>(find.byType(FilePage)).embedded, isTrue);
      expect(tester.getTopLeft(find.byType(FilePage)).dx, greaterThan(700));
      await tester.binding.setSurfaceSize(const Size(390, 700));
      await tester.pumpAndSettle();
      expect(tester.widget<FilePage>(find.byType(FilePage)).embedded, isFalse);
      expect(find.text('file body'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.binding.setSurfaceSize(const Size(1180, 800));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭预览'));
      await tester.pumpAndSettle();
      expect(find.byType(FilePage), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chat-input')))
            .controller!
            .text,
        'unsent draft',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      client.dispose();
    },
  );
}
