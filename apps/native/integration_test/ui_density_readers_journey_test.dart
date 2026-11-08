import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:quds_office_editor/quds_office_editor.dart' as office;
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/chat.dart';
import 'package:nekodot_native/features/files.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/settings.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/connection_notice.dart';
import 'package:nekodot_native/ui/design.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

// Actual native app and existing isolated Node. Preview only; no model reruns.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('compact settings and native Office readers on real services', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'notification-requested': true});
    final c = NekodotClient(vault: MemoryVault());
    final nav = GlobalKey<NavigatorState>();
    final phone = Platform.isAndroid;
    const dm = String.fromEnvironment('QA_CONVERSATION');
    const evidence = String.fromEnvironment('QA_EVIDENCE_DIR');
    var converted = false;
    addTearDown(c.dispose);
    Future<void> frames([int ms = 400]) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 40));
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }

    Future<void> until(bool Function() ready) async {
      final end = DateTime.now().add(const Duration(seconds: 60));
      while (!ready() && DateTime.now().isBefore(end)) {
        await frames(200);
      }
      expect(ready(), isTrue);
    }

    Future<void> tap(Finder target) async {
      await tester.ensureVisible(target.first);
      await frames(300);
      await tester.tap(target.hitTestable().first);
      await frames();
      expect(tester.takeException(), isNull);
    }

    Future<void> shot(String name) async {
      await frames(700);
      expect(tester.takeException(), isNull);
      final label =
          'density-${phone ? 'android' : 'windows'}-${c.prefs.theme}-$name';
      if (phone) {
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
          await tester.pump();
        }
        await binding.takeScreenshot(label);
      } else {
        final view = tester.binding.renderViews.first;
        final image = await (view.debugLayer! as OffsetLayer).toImage(
          Offset.zero & view.flutterView.physicalSize,
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(evidence).create(recursive: true);
        await File('$evidence/$label.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }
      debugPrint('DENSITY verified $label');
    }

    if (!phone) {
      await DesktopHost.initialize();
      await windowManager.setTitle('nekodot UI density QA');
      await windowManager.show();
      tester.view.physicalSize = const Size(1200, 850);
      tester.view.devicePixelRatio = 1;
    }
    await c.prefs.update(locale: 'zh', appearance: 'light');
    await c.login(
      const String.fromEnvironment('QA_EMAIL'),
      const String.fromEnvironment('QA_PASSWORD'),
    );
    await c.selectNode(const String.fromEnvironment('QA_NODE'));
    await until(() => c.online && c.node.bots.isNotEmpty);
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: c.prefs,
        builder: (_, child) => MaterialApp(
          navigatorKey: nav,
          navigatorObservers: [nativeRoutes],
          debugShowCheckedModeBanner: false,
          theme: appTheme(
            c.prefs.theme == 'dark' ? Brightness.dark : Brightness.light,
            glass: phone,
          ),
          builder: (_, child) => ConnectionNotice(
            client: c,
            child: phone ? Ambient(child: child!) : WindowChrome(child: child!),
          ),
          home: HomePage(client: c),
        ),
      ),
    );
    await frames(1000);
    await tap(find.byKey(const ValueKey('conversation-$dm')));
    await until(
      () => find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty,
    );
    final input = find.byKey(const ValueKey('chat-input'));
    await tester.enterText(input, 'UI density unsent draft');
    FocusManager.instance.primaryFocus?.unfocus();
    await frames();
    final files = objects(
      jsonDecode(const String.fromEnvironment('QA_FILES', defaultValue: '[]')),
    );
    const samples = ['docx', 'xlsx', 'pptx'];
    for (final extension in samples) {
      final name = 'ui-density-preview.$extension';
      if (files.any((f) => f['name'] == name)) continue;
      final created = await c.rpc('imports.create', {});
      final response = await c.account.transport.put(
        c.account
            .url(
              '/api/nodes/${c.selectedNodeId}/imports/${created['importId']}',
            )
            .replace(queryParameters: {'path': name, 'offset': '0'}),
        headers: {
          'Authorization': 'Bearer ${c.account.token}',
          'Content-Type': 'application/octet-stream',
        },
        body: await File(
          '${const String.fromEnvironment('QA_FIXTURES')}/preview.$extension',
        ).readAsBytes(),
      );
      expect(response.statusCode, 200);
      files.add(
        await c.rpc('files.receive', {
          'conversationId': dm,
          'importId': created['importId'],
          'path': name,
        }),
      );
    }
    final before = c.node.messages[dm]?.length;
    for (final theme in ['light', 'dark']) {
      await c.prefs.update(appearance: theme);
      await frames();
      for (final extension in samples) {
        final file = files.firstWhere(
          (f) => f['name'] == 'ui-density-preview.$extension',
        );
        unawaited(
          showFileViewer(tester.element(find.byType(ChatPage).first), c, file),
        );
        await until(
          () => find
              .byKey(const ValueKey('office-zoom-in'))
              .evaluate()
              .isNotEmpty,
        );
        await shot('$extension-open');
        if (!phone && extension != 'pptx') {
          final word = extension == 'docx';
          final office.OfficeController controller = word
              ? tester
                    .widget<office.QudsWordEditor>(
                      find.byType(office.QudsWordEditor),
                    )
                    .controller
              : tester
                    .widget<office.QudsSheetEditor>(
                      find.byType(office.QudsSheetEditor),
                    )
                    .controller;
          final canvas = find.byType(
            word ? office.WordCanvas : office.SheetGrid,
          );
          final rect = tester.getRect(canvas);
          final initial = controller.viewport.scale;
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: rect.center,
              scrollDelta: const Offset(0, -120),
            ),
          );
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await frames();
          expect(controller.viewport.scale, greaterThan(initial));
          await shot('$extension-ctrl-wheel');
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: rect.center,
              scrollDelta: const Offset(0, 120),
            ),
          );
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await frames();
          expect(controller.viewport.scale, closeTo(initial, .00001));
          // Enlarge through the visible control, never mutate the viewport.
          for (var i = 0; i < 3; i++) {
            await tap(find.byKey(const ValueKey('office-zoom-in')));
          }
          final center = controller.viewport.extent.center(Offset.zero);
          Offset anchor() {
            if (word) {
              return tester
                  .renderObject<office.RenderWordCanvas>(canvas)
                  .windowForPagePoint(0, const Offset(180, 220));
            }
            return (controller.viewport.origin +
                    center -
                    const Offset(28, 20)) /
                controller.viewport.scale;
          }

          final beforeAnchor = anchor();
          final beforeScale = controller.viewport.scale;
          await tap(find.byKey(const ValueKey('office-zoom-in')));
          final expected = word
              ? center +
                    (beforeAnchor - center) *
                        (controller.viewport.scale / beforeScale)
              : beforeAnchor;
          expect((anchor() - expected).distance, lessThan(.1));
          await shot('$extension-center-zoom');
          final beforeDrag = controller.viewport.origin.dx;
          await tester.dragFrom(
            Offset(rect.left + rect.width * .45, rect.bottom - 6),
            const Offset(90, 0),
            kind: PointerDeviceKind.mouse,
          );
          await frames();
          expect(controller.viewport.origin.dx, greaterThan(beforeDrag));
          await shot('$extension-scroll-right');
          final afterRight = controller.viewport.origin.dx;
          await tester.dragFrom(
            Offset(rect.left + rect.width * .6, rect.bottom - 6),
            const Offset(-120, 0),
            kind: PointerDeviceKind.mouse,
          );
          await frames();
          expect(controller.viewport.origin.dx, lessThan(afterRight));
          expect(controller.config.allowsMutation, isFalse);
          await shot('$extension-scroll-left');
        }
        await tap(find.byKey(const ValueKey('office-zoom-in')));
        await tap(find.byKey(const ValueKey('office-zoom-out')));
        if (extension == 'xlsx') {
          await tap(find.byKey(const ValueKey('office-sheet-1')));
        }
        if (extension == 'pptx') {
          await tap(find.byKey(const ValueKey('office-next-slide')));
        }
        await shot(extension);
        if (!phone) {
          await tap(find.byKey(const ValueKey('viewer-open')));
          expect(find.text(c.tr('分享文件', 'Share file')), findsOneWidget);
          await shot('$extension-menu');
          nav.currentState!.pop();
          await frames();
          await tap(find.byKey(const ValueKey('viewer-expand')));
          await shot('$extension-expanded');
          await tap(find.byKey(const ValueKey('viewer-expand')));
        }
        await tap(find.byTooltip(c.tr('关闭', 'Close')).last);
        expect(
          tester.widget<TextField>(input).controller!.text,
          'UI density unsent draft',
        );
      }
      unawaited(
        openPage(
          nav.currentContext!,
          SettingsPage(client: c, sectionId: 'app'),
        ),
      );
      await frames(700);
      await shot('settings');
      await tap(find.text('EN'));
      expect(c.prefs.language, 'en');
      await shot('settings-en');
      await tap(find.text('中'));
      await tap(find.byTooltip('深色'));
      expect(c.prefs.theme, 'dark');
      await tap(find.byTooltip('浅色'));
      expect(c.prefs.theme, 'light');
      nav.currentState!.pop();
      await frames();
    }
    await c.connection.disconnect();
    await frames(3300);
    expect(find.text(c.tr('无法连接', 'Unable to connect')), findsOneWidget);
    await shot('offline');
    expect(
      tester.widget<TextField>(input).controller!.text,
      'UI density unsent draft',
    );
    await c.connection.connect();
    await until(() => c.online);
    await frames();
    expect(find.text(c.tr('无法连接', 'Unable to connect')), findsNothing);
    expect(c.node.messages[dm]?.length, before);
    expect(c.deliveries.items, isEmpty);
    await tester.enterText(input, '');
    await frames();
    debugPrint(
      'DENSITY PASS real Node file transfer, previews, settings, retained draft; no model execution',
    );
  });
}
