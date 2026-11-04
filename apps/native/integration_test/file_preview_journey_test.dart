import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:nekodot_native/main.dart' as product;
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/auth.dart';
import 'package:nekodot_native/features/chat.dart';
import 'package:nekodot_native/features/files.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/svg_file_preview.dart';

/// Uses a real delivered attachment and authenticated Node/Relay. Private paths
/// and credentials are supplied at run time and never written to test logs.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows real delivered SVG, side preview, source and open menu', (
    tester,
  ) async {
    final output = Directory(const String.fromEnvironment('LOCAL_EVIDENCE'));
    expect(output.path, isNotEmpty);
    final nodeId = const String.fromEnvironment('PREVIEW_NODE');
    final conversation = const String.fromEnvironment('PREVIEW_CONVERSATION');
    final fileId = const String.fromEnvironment('PREVIEW_FILE');
    expect([nodeId, conversation, fileId].every((s) => s.isNotEmpty), isTrue);
    Future<void> until(bool Function() condition) async {
      final deadline = DateTime.now().add(const Duration(seconds: 75));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('File preview journey timed out');
        }
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
    }

    await product.main();
    await until(() => find.byType(product.NekodotApp).evaluate().isNotEmpty);
    final client = tester
        .widget<product.NekodotApp>(find.byType(product.NekodotApp))
        .client;
    expect(client.origin.host, anyOf('localhost', '127.0.0.1'));
    await until(
      () =>
          find.byType(HomePage).evaluate().isNotEmpty ||
          find.byType(AuthPage).evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 500));
    if (find.byType(AlertDialog).evaluate().isNotEmpty) {
      await tester.tap(
        find.widgetWithText(TextButton, client.tr('继续', 'Continue')),
      );
    }
    final account = await tester.runAsync(
      () async => jsonDecode(
        await File(const String.fromEnvironment('LOCAL_ACCOUNT_FILE'))
            .readAsString(),
      ) as Json,
    );
    if (client.token == null ||
        client.me?['user']?['email'] != account!['email']) {
      await tester.runAsync(() async {
        if (client.token != null) await client.clearSession();
        await client.login(
          account!['email'] as String,
          account['password'] as String,
        );
      });
    }
    await tester.runAsync(
      () => client.preferences(locale: 'zh', appearance: 'light'),
    );
    await tester.runAsync(() => client.selectNode(nodeId));
    await until(() => client.ready && client.online && !client.node.syncing);
    await windowManager.unmaximize();
    await windowManager.setSize(const Size(1440, 960));
    await tester.pump(const Duration(milliseconds: 500));
    final metadata = await tester.runAsync(
      () => client.rpc('files.get', {'fileId': fileId}, nodeId),
    );
    expect(metadata!['available'], isTrue);
    expect(metadata['mime'], 'image/svg+xml');
    final bytes = await tester.runAsync(
      () => downloadFile(client, fileId, nodeId: nodeId),
    );
    expect(utf8.decode(bytes!), contains('<feGaussianBlur'));
    final providers = await tester.runAsync(
      () => client.rpc('providers.list', {}, nodeId),
    );
    expect(providers, isNotNull);
    await tester.tap(find.byKey(ValueKey('conversation-$conversation')));
    await until(() => find.byType(ChatPage).evaluate().isNotEmpty);
    final attachment = find.byWidgetPredicate(
      (w) => w is FileCard && w.fileId == fileId,
    );
    await until(() => attachment.evaluate().isNotEmpty);
    await tester.ensureVisible(attachment);
    await tester.tap(attachment);
    await until(
      () =>
          find.byKey(const ValueKey('svg-preview-ready')).evaluate().isNotEmpty,
    );
    expect(find.byType(ChatPage), findsOneWidget);
    expect(tester.widget<FilePage>(find.byType(FilePage)).embedded, isTrue);
    expect(tester.getTopLeft(find.byType(FilePage)).dx, greaterThan(800));
    expect(find.textContaining('MEDIA:', findRichText: true), findsNothing);

    Future<void> screenshot(String name) async {
      await windowManager.show();
      await windowManager.focus();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        await output.create(recursive: true);
        const script = String.fromEnvironment('PREVIEW_SCREENSHOT_SCRIPT');
        if (script.isNotEmpty) {
          final result = await Process.run('powershell.exe', [
            '-NoProfile',
            '-WindowStyle',
            'Hidden',
            '-File',
            script,
            '-PreviewProcessId',
            '$pid',
            '-OutputPath',
            '${output.path}/$name.png',
          ]);
          expect(result.exitCode, 0, reason: '${result.stderr}');
          return;
        }
        final view = tester.binding.renderViews.first;
        final image = await (view.debugLayer! as OffsetLayer).toImage(
          Offset.zero & tester.view.physicalSize,
        );
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${output.path}/$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    final svgState = tester.state<SvgFilePreviewState>(
      find.byType(SvgFilePreview),
    );
    // The browser may decode successfully while native composition is blank.
    // Verify actual pixels in Flutter's preview region, not just DOM readiness.
    final previewBounds = tester.getRect(find.byType(SvgFilePreview));
    final view = tester.binding.renderViews.first;
    final composited = await tester.runAsync(
      () => (view.debugLayer! as OffsetLayer).toImage(
        Offset.zero & tester.view.physicalSize,
      ),
    );
    final rgba = await tester.runAsync(
      () => composited!.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    final pixels = rgba!.buffer.asUint8List();
    final ratio = tester.view.devicePixelRatio;
    var colored = 0;
    for (
      var y = (previewBounds.top * ratio).ceil() + 10;
      y < previewBounds.bottom * ratio - 10;
      y += 20
    ) {
      for (
        var x = (previewBounds.left * ratio).ceil() + 10;
        x < previewBounds.right * ratio - 10;
        x += 20
      ) {
        final offset = (y * composited!.width + x) * 4;
        if (pixels[offset] < 180 && pixels[offset + 1] < 180) colored++;
      }
    }
    composited!.dispose();
    final imageInfo = await tester.runAsync(
      () => svgState.controller!.evaluateJavascript(
        source: 'JSON.stringify({width:document.querySelector("img").naturalWidth,height:document.querySelector("img").naturalHeight,complete:document.querySelector("img").complete})',
      ),
    );
    final decoded = jsonDecode(imageInfo as String) as Json;
    expect(decoded, {'width': 900, 'height': 1100, 'complete': true});
    final rendered = await tester.runAsync(
      () => svgState.controller!.takeScreenshot(),
    );
    expect(rendered, isNotNull);
    await tester.runAsync(() async {
      await output.create(recursive: true);
      await File('${output.path}/svg-webview.png').writeAsBytes(rendered!);
    });
    await screenshot('desktop-side-preview');
    expect(
      colored,
      greaterThan(40),
      reason: 'The actual right preview must contain the rendered SVG.',
    );
    await tester.tap(find.byTooltip('放大'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('125%'), findsOneWidget);
    await tester.tap(find.text('适合窗口'));
    await tester.tap(find.text('源码'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(utf8.decode(bytes)), findsOneWidget);
    await screenshot('desktop-svg-source');
    await tester.tap(find.text('预览'));
    await until(
      () =>
          find.byKey(const ValueKey('svg-preview-ready')).evaluate().isNotEmpty,
    );
    await tester.tap(find.byTooltip('打开文件菜单'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('打开方式…'), findsOneWidget);
    expect(find.text('在文件夹中显示'), findsOneWidget);
    await screenshot('desktop-file-actions');
    const observerScript = String.fromEnvironment('PREVIEW_OPEN_WITH_OBSERVER');
    if (observerScript.isNotEmpty) {
      final observer = await tester.runAsync(
        () => Process.start('powershell.exe', [
          '-NoProfile',
          '-WindowStyle',
          'Hidden',
          '-File',
          observerScript,
          '-OwnerProcessId',
          '$pid',
          '-EvidenceDirectory',
          output.path,
        ]),
      );
      await until(
        () => File('${output.path}/open-with-observer-ready').existsSync(),
      );
      await tester.tap(find.text('打开方式…'));
      await tester.pump(const Duration(milliseconds: 300));
      final exitCode = await tester.runAsync(
        () => observer!.exitCode.timeout(const Duration(seconds: 45)),
      );
      expect(exitCode, 0);
      expect(
        File('${output.path}/open-with-observed.json').existsSync(),
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await windowManager.focus();
    } else {
      await tester.tapAt(const Offset(700, 400));
    }
    const externalOpen = bool.fromEnvironment('PREVIEW_EXTERNAL_OPEN');
    if (externalOpen) {
      await tester.tap(find.byTooltip('打开文件菜单'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('用系统默认应用打开'));
      await until(
        () => find
            .descendant(
              of: find.byType(FilePage),
              matching: find.byType(LinearProgressIndicator),
            )
            .evaluate()
            .isEmpty,
      );
      expect(find.textContaining('Windows could not open'), findsNothing);
      await windowManager.focus();
    }
    await tester.pump(const Duration(milliseconds: 300));
    await windowManager.setSize(const Size(480, 760));
    await tester.pump(const Duration(milliseconds: 500));
    await until(
      () =>
          find.byKey(const ValueKey('svg-preview-ready')).evaluate().isNotEmpty,
    );
    expect(tester.widget<FilePage>(find.byType(FilePage)).embedded, isFalse);
    await screenshot('desktop-narrow-preview');
    expect(tester.takeException(), isNull);
    await windowManager.setSize(const Size(1440, 960));
    await tester.pump(const Duration(milliseconds: 500));
    await until(
      () =>
          find.byKey(const ValueKey('svg-preview-ready')).evaluate().isNotEmpty,
    );
    await tester.tap(find.byTooltip('关闭预览'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(FilePage), findsNothing);
    expect(find.byType(ChatPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    final report = {
      'realRelayNode': true,
      'hermesProvidersRpc': true,
      'originalSvgDownloaded': true,
      'svgNaturalDimensions': decoded,
      'rightPanel': true,
      'svgCompositedInFlutter': true,
      'sourceMatchesOriginal': true,
      'zoomAndFit': true,
      'openWithMenu': true,
      'narrowFullPage': true,
      'closeRetainsChat': true,
      'externalAppDialogTested': observerScript.isNotEmpty,
      'defaultAppOpenTested': externalOpen,
      'newModelGenerationTested': false,
    };
    binding.reportData = report;
    await tester.runAsync(
      () => File('${output.path}/journey.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(report)),
    );
  });
}
