import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

import '../ui/design.dart';
import 'file_transfer.dart';

class SvgFilePreview extends StatefulWidget {
  final Uint8List bytes;
  final double scale;
  const SvgFilePreview({super.key, required this.bytes, required this.scale});

  @override
  State<SvgFilePreview> createState() => SvgFilePreviewState();
}

class SvgFilePreviewState extends State<SvgFilePreview> {
  static Future<WebViewEnvironment?>? _environment;
  InAppWebViewController? controller;
  final transform = TransformationController();
  Uint8List? png;
  String? error;
  Size renderSize = const Size(900, 1100);
  bool capturing = false;

  @override
  void initState() {
    super.initState();
    updateScale();
  }

  static Future<WebViewEnvironment?> createEnvironment() async {
    if (!Platform.isWindows) return null;
    if (await WebViewEnvironment.getAvailableVersion() == null) {
      throw StateError(
        'Microsoft Edge WebView2 Runtime is required for SVG preview.',
      );
    }
    final support = await getApplicationSupportDirectory();
    return WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(
        userDataFolder: '${support.path}/file-preview-webview',
      ),
    );
  }

  @override
  void didUpdateWidget(covariant SvgFilePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bytes != widget.bytes) {
      png = null;
      error = null;
      capturing = false;
      unawaited(controller?.loadData(data: svgPreviewDocument(widget.bytes)));
    }
    updateScale();
  }

  void updateScale() {
    transform.value = Matrix4.diagonal3Values(widget.scale, widget.scale, 1);
  }

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  Future<void> capture(InAppWebViewController browser) async {
    if (capturing) return;
    capturing = true;
    try {
      final dimensions = jsonDecode(
        await browser.evaluateJavascript(
          source: 'JSON.stringify({width:document.querySelector("img").naturalWidth,height:document.querySelector("img").naturalHeight})',
        ) as String,
      ) as Map;
      final width = (dimensions['width'] as num).toDouble();
      final height = (dimensions['height'] as num).toDouble();
      if (width <= 0 || height <= 0 || !width.isFinite || !height.isFinite) {
        throw const FormatException('SVG image could not be decoded');
      }
      // Render once at high resolution, with bounded bitmap dimensions.
      // Flutter owns presentation, scrolling and zoom; native browser surfaces
      // are not composited reliably by the current Windows Flutter renderer.
      final factor = math.min(3.0, 4096 / math.max(width, height));
      if (!mounted) return;
      setState(
        () => renderSize = Size(
          math.max(1, width * factor),
          math.max(1, height * factor),
        ),
      );
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final image = await browser.takeScreenshot();
      if (image == null || image.isEmpty) {
        throw StateError('SVG rendering returned no image');
      }
      if (mounted) setState(() => png = image);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isLinux) {
      return const Center(child: Text('SVG preview requires a browser.'));
    }
    return FutureBuilder<WebViewEnvironment?>(
      future: _environment ??= createEnvironment(),
      builder: (context, snapshot) {
        if (snapshot.hasError || error != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ErrorNotice(error ?? '${snapshot.error}'),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: Breathing(key: ValueKey('svg-preview-loading')),
          );
        }
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: renderSize.width,
              height: renderSize.height,
              child: IgnorePointer(
                child: InAppWebView(
                  webViewEnvironment: snapshot.data,
                  initialData: InAppWebViewInitialData(
                    data: svgPreviewDocument(widget.bytes),
                  ),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: false,
                    javaScriptCanOpenWindowsAutomatically: false,
                    supportZoom: false,
                    disableContextMenu: true,
                    allowFileAccess: false,
                    allowContentAccess: false,
                    allowFileAccessFromFileURLs: false,
                    allowUniversalAccessFromFileURLs: false,
                    useShouldOverrideUrlLoading: true,
                    isInspectable: false,
                  ),
                  onWebViewCreated: (value) => controller = value,
                  shouldOverrideUrlLoading: (_, action) async =>
                      action.request.url?.toString() == 'about:blank'
                      ? NavigationActionPolicy.ALLOW
                      : NavigationActionPolicy.CANCEL,
                  onCreateWindow: (_, action) async => false,
                  onPermissionRequest: (_, request) async => PermissionResponse(
                    resources: request.resources,
                    action: PermissionResponseAction.DENY,
                  ),
                  onLoadStop: (browser, url) => unawaited(capture(browser)),
                  onReceivedError: (_, request, value) {
                    if (mounted && request.isForMainFrame == true) {
                      setState(() => error = value.description);
                    }
                  },
                ),
              ),
            ),
            if (png == null)
              const ColoredBox(
                color: Color(0xfff4f4f4),
                child: Center(
                  child: Breathing(key: ValueKey('svg-preview-loading')),
                ),
              ),
            if (png != null)
              ColoredBox(
                color: const Color(0xfff4f4f4),
                child: ClipRect(
                  child: InteractiveViewer(
                    transformationController: transform,
                    minScale: .25,
                    maxScale: 4,
                    child: Center(
                      child: Image.memory(
                        png!,
                        fit: BoxFit.contain,
                        frameBuilder: (_, child, frame, synchronous) =>
                            frame == null
                            ? const Breathing(
                                key: ValueKey('svg-preview-loading'),
                              )
                            : KeyedSubtree(
                                key: const ValueKey('svg-preview-ready'),
                                child: child,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
