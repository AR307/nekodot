import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/data/local_content.dart';
import 'package:nekodot_native/features/chat.dart';
import 'package:nekodot_native/features/chat_composer.dart';
import 'package:nekodot_native/features/chat_file_drop.dart';
import 'package:nekodot_native/features/office_preview.dart';
import 'package:nekodot_native/ui/design.dart';
import 'package:quds_office_editor/quds_office_editor.dart' as office;
import 'package:shared_preferences/shared_preferences.dart';

import 'product_test.dart' show JourneyClient;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('desktop_drop'),
          (_) async => null,
        );
  });

  test('Office file names and MIME types select native readers', () {
    expect(
      officeFormat('中文报告.DOCX', 'application/octet-stream'),
      OfficeFormat.word,
    );
    expect(
      officeFormat(
        'sheet',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ),
      OfficeFormat.sheet,
    );
    expect(officeFormat('slides.pptx', ''), OfficeFormat.slides);
    expect(officeFormat('legacy.doc', 'application/msword'), isNull);
  });

  testWidgets('closing while an Office document opens releases its canvas', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Scaffold(
          body: OfficePreview(
            bytes: File('test/fixtures/preview.docx').readAsBytesSync(),
            format: OfficeFormat.word,
            zoomInLabel: '放大',
            zoomOutLabel: '缩小',
          ),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a damaged Office attachment shows an error without a crash', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Scaffold(
          body: OfficePreview(
            bytes: Uint8List.fromList([1, 2, 3]),
            format: OfficeFormat.word,
            zoomInLabel: '放大',
            zoomOutLabel: '缩小',
          ),
        ),
      ),
    );
    for (
      var i = 0;
      i < 20 && find.byType(ErrorNotice).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(find.byType(ErrorNotice), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'multiple dropped files stay in the original offline chat draft, without sending',
    (tester) async {
      final client = JourneyClient();
      client.connection.ready = false;
      final root = Directory(
        '${Directory.systemTemp.path}/nekodot-file-preview-test',
      );
      root.createSync(recursive: true);
      client.store = LocalContent(root);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: ChatPage(client: client, conversationId: 'dm'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('chat-input')),
        'Keep this draft',
      );
      final composer = tester.state<ChatComposerState>(
        find.byType(ChatComposer),
      );
      await tester.runAsync(
        () => composer.attachDroppedFiles([
          DropItemFile(File('test/fixtures/preview.docx').absolute.path),
          DropItemFile(File('test/fixtures/preview.md').absolute.path),
        ]),
      );
      await tester.pumpAndSettle();
      expect(composer.error, isEmpty);
      expect(client.attachmentDrafts.keys, contains('test-node:dm'));
      final attached = client.attachmentDrafts['test-node:dm']!;
      expect(attached.map((f) => f['name']), ['preview.docx', 'preview.md']);
      expect(
        attached.every(
          (f) => f['nodeId'] == 'test-node' && f['conversationId'] == 'dm',
        ),
        isTrue,
      );
      expect(
        File(attached.first['localPath'] as String).readAsBytesSync(),
        File('test/fixtures/preview.docx').readAsBytesSync(),
      );
      expect(composer.input.text, 'Keep this draft');
      expect(client.deliveries.items, isEmpty);
      expect(find.byType(ChatFileDrop), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      client.dispose();
    },
  );

  for (final entry in {
    'docx': OfficeFormat.word,
    'xlsx': OfficeFormat.sheet,
    'pptx': OfficeFormat.slides,
  }.entries) {
    for (final narrow in [false, true]) {
      testWidgets(
        '${entry.key} renders real Office content, navigation and zoom at ${narrow ? 390 : 1000}px',
        (tester) async {
          tester.view.physicalSize = Size(narrow ? 390 : 1000, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final bytes = File('test/fixtures/preview.${entry.key}')
              .readAsBytesSync();
          await tester.pumpWidget(
            MaterialApp(
              theme: appTheme(narrow ? Brightness.dark : Brightness.light),
              home: RepaintBoundary(
                key: const ValueKey('office-preview-evidence'),
                child: Scaffold(
                  body: OfficePreview(
                    bytes: bytes,
                    format: entry.value,
                    zoomInLabel: '放大',
                    zoomOutLabel: '缩小',
                  ),
                ),
              ),
            ),
          );
          for (
            var i = 0;
            i < 120 &&
                find.byKey(const ValueKey('office-zoom-in')).evaluate().isEmpty;
            i++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(find.byKey(const ValueKey('office-zoom-in')), findsOneWidget);
          const evidence = String.fromEnvironment('FILE_PREVIEW_EVIDENCE');
          if (evidence.isNotEmpty) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 200)),
            );
            await tester.pump();
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('office-preview-evidence')),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final path = '$evidence/${entry.key}-${narrow ? 390 : 1000}.png';
              await File(path).parent.create(recursive: true);
              await File(path).writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
          if (entry.value == OfficeFormat.word) {
            final c = tester
                .widget<office.QudsWordEditor>(
                  find.byType(office.QudsWordEditor),
                )
                .controller;
            expect(c.pageCount, greaterThanOrEqualTo(2));
            expect(c.config.allowsMutation, isFalse);
            expect(
              find.text('${(c.viewport.scale * 100).round()}%'),
              findsOneWidget,
            );
          } else if (entry.value == OfficeFormat.sheet) {
            final c = tester
                .widget<office.QudsSheetEditor>(
                  find.byType(office.QudsSheetEditor),
                )
                .controller;
            expect(c.workbook.sheets.length, 2);
            expect(c.workbook.sheets.first.cellA1('D4').value, 3000);
            expect(c.workbook.sheets.first.cellA1('B9').value, 1200);
            await tester.tap(find.byKey(const ValueKey('office-sheet-1')));
            await tester.pump();
            expect(c.activeSheetIndex, 1);
            expect(c.config.allowsMutation, isFalse);
          } else {
            final c = tester
                .widget<office.QudsSlideEditor>(
                  find.byType(office.QudsSlideEditor),
                )
                .controller;
            expect(c.presentation.slides.length, 2);
            expect(c.presentation.slides.first.backgroundColor, 'F1F5F9');
            expect(c.presentation.slides.first.shapes.first.fontSizePt, 32);
            expect(c.presentation.slides.first.shapes.first.fontBold, isTrue);
            final stage = tester.widget<office.SlideStage>(
              find.byType(office.SlideStage),
            );
            expect(stage.slideSize.width, closeTo(959.976, 0.01));
            expect(stage.slideSize.height, 540);
            await tester.tap(find.byKey(const ValueKey('office-next-slide')));
            await tester.pump();
            expect(c.activeSlideIndex, 1);
            expect(c.config.allowsMutation, isFalse);
          }
          await tester.tap(find.byKey(const ValueKey('office-zoom-in')));
          await tester.pump();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
