import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart'
    show ChannelController, InternalChannelController;
import 'package:window_manager/window_manager.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../data/spaces.dart';
import '../ui/design.dart';

Future<WebViewEnvironment> createSpaceEnvironment(String folder) async {
  final environment = await WebViewEnvironment.create(
    settings: WebViewEnvironmentSettings(
      userDataFolder: folder,
      allowSingleSignOnUsingOSPrimaryAccount: false,
    ),
  );
  // Windows 0.6.0 creates the native environment with env.id but accidentally
  // binds Dart to the static factory's ID. Bind the actual instance so disposal
  // releases its native environment instead of calling a nonexistent channel.
  final platform = environment.platform as ChannelController;
  platform.channel?.setMethodCallHandler(null);
  platform.channel = MethodChannel(
    'com.pichillilorenzo/flutter_webview_environment_${environment.id}',
  );
  platform.initMethodCallHandler();
  return environment;
}

const _sdk = r'''
(() => {
  if (window.top !== window) return;
  const ready = new Promise(resolve => {
    if (window.flutter_inappwebview?.callHandler) resolve();
    else window.addEventListener('flutterInAppWebViewPlatformReady', resolve, {once:true});
  });
  const call = async (operation, key, value) => {
    await ready;
    const result = await window.flutter_inappwebview.callHandler('spaceData', {operation, key, value});
    if (result.error) throw new Error(result.error);
    return result.value;
  };
  Object.defineProperty(window, 'nekodotSpace', {value: Object.freeze({
    ready, get: key => call('get', key), list: () => call('list'),
    set: (key, value) => call('set', key, value)
  })});
})();
''';

/// A zip stays in the existing account file cache. No unpacked site directory,
/// public listener or file:// access is needed by the renderer.
class SpaceBundle {
  final Map<String, Uint8List> files;
  SpaceBundle(Uint8List bytes)
    : files = {
        for (final file in ZipDecoder().decodeBytes(bytes))
          if (file.isFile) file.name: file.readBytes()!,
      };
  static String mime(String path) =>
      switch (path.split('.').last.toLowerCase()) {
        'html' => 'text/html',
        'css' => 'text/css',
        'js' || 'mjs' => 'application/javascript',
        'json' => 'application/json',
        'svg' => 'image/svg+xml',
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        'ico' => 'image/x-icon',
        'woff' => 'font/woff',
        'woff2' => 'font/woff2',
        'ttf' => 'font/ttf',
        'mp3' => 'audio/mpeg',
        'wav' => 'audio/wav',
        'ogg' => 'audio/ogg',
        'mp4' => 'video/mp4',
        'webm' => 'video/webm',
        _ => 'application/octet-stream',
      };
}

class SpaceWebView extends StatefulWidget {
  final NekodotClient client;
  final String nodeId;
  final Space space;
  final SpaceBundle bundle;
  final WebViewEnvironment? environment;
  final VoidCallback onError;
  const SpaceWebView({
    super.key,
    required this.client,
    required this.nodeId,
    required this.space,
    required this.bundle,
    this.environment,
    required this.onError,
  });
  @override
  State<SpaceWebView> createState() => _SpaceWebViewState();
}

class _SpaceWebViewState extends State<SpaceWebView>
    with WidgetsBindingObserver, RouteAware, WindowListener {
  InAppWebViewController? controller;
  late final owner = widget.client.store;
  ModalRoute<void>? route;
  bool visible = true;
  bool desktopVisible = true;
  String get origin => 'https://s-${widget.space.spaceId}.nekodot.invalid';
  // Opaque sandbox origins have no persistent web storage. Only our SDK can
  // persist data. Explicit resource origins keep local modules/fetch working.
  String get csp =>
      "default-src 'none'; sandbox allow-scripts allow-forms; "
      "script-src $origin 'unsafe-inline'; style-src $origin 'unsafe-inline'; "
      "img-src $origin data: blob: ${widget.space.allowedOrigins.join(' ')}; "
      "font-src $origin; media-src $origin blob: ${widget.space.allowedOrigins.join(' ')}; "
      "connect-src $origin ${widget.space.allowedOrigins.join(' ')}; "
      "frame-src 'none'; worker-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.client.spaces.addListener(recordsChanged);
    if (Platform.isWindows) windowManager.addListener(this);
  }

  void recordsChanged() {
    if (visible) {
      unawaited(
        controller?.evaluateJavascript(
          source: 'window.dispatchEvent(new Event("nekodotspacechange"));',
        ),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ModalRoute.of(context);
    if (route == next) return;
    nativeRoutes.unsubscribe(this);
    route = next;
    if (next != null) nativeRoutes.subscribe(this, next);
  }

  Future<void> activity(bool active) async {
    visible = active;
    final view = controller;
    if (view == null) return;
    if (active) {
      await view.resume();
      if (Platform.isAndroid) await view.resumeTimers();
      recordsChanged();
    } else {
      await view.pause();
      if (Platform.isAndroid) await view.pauseTimers();
    }
  }

  void updateActivity() =>
      unawaited(activity((route?.isCurrent ?? true) && desktopVisible));

  @override
  void onWindowEvent(String eventName) {
    if (eventName == 'minimize' || eventName == 'hide') {
      desktopVisible = false;
    } else if (eventName == 'restore' || eventName == 'show') {
      desktopVisible = true;
    } else {
      return;
    }
    updateActivity();
  }

  @override
  void didPushNext() => unawaited(activity(false));
  @override
  void didPopNext() => updateActivity();
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      updateActivity();
    } else if (state != AppLifecycleState.inactive) {
      unawaited(activity(false));
    }
  }

  @override
  void dispose() {
    nativeRoutes.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    widget.client.spaces.removeListener(recordsChanged);
    if (Platform.isWindows) windowManager.removeListener(this);
    // Android timers are process-wide; do not leave the next space paused.
    if (!visible && Platform.isAndroid) unawaited(controller?.resumeTimers());
    controller = null;
    super.dispose();
  }

  Future<WebResourceResponse?> resource(WebResourceRequest request) async {
    final uri = Uri.parse(request.url.toString());
    if (uri.scheme != 'https') {
      return WebResourceResponse(
        statusCode: 403,
        reasonPhrase: 'Forbidden',
        headers: {},
        data: Uint8List(0),
      );
    }
    if (uri.origin != origin) {
      if (uri.scheme == 'https' &&
          widget.space.allowedOrigins.contains(uri.origin)) {
        return null;
      }
      return WebResourceResponse(
        statusCode: 403,
        reasonPhrase: 'Forbidden',
        headers: {},
        data: Uint8List(0),
      );
    }
    final path = Uri.decodeComponent(uri.path.substring(1));
    final bytes = widget.bundle.files[path.isEmpty ? 'index.html' : path];
    return WebResourceResponse(
      contentType: Platform.isWindows
          ? '${SpaceBundle.mime(path)}; charset=utf-8'
          : SpaceBundle.mime(path),
      contentEncoding: Platform.isWindows ? null : 'utf-8',
      data: bytes ?? Uint8List(0),
      statusCode: bytes == null ? 404 : 200,
      reasonPhrase: bytes == null ? 'Not Found' : 'OK',
      headers: {
        'Content-Security-Policy': csp,
        'Access-Control-Allow-Origin': '*',
        'X-Content-Type-Options': 'nosniff',
        'Cache-Control': 'no-store',
      },
    );
  }

  Future<Json> bridge(List<dynamic> args) async {
    if (!mounted || owner == null || !identical(owner, widget.client.store)) {
      return {'error': 'Space closed'};
    }
    final request = args.length == 1 && args.first is Map
        ? object(args.first)
        : <String, dynamic>{};
    final operation = request['operation'], key = request['key'];
    if (!const ['get', 'list', 'set'].contains(operation) ||
        (operation != 'list' &&
            (key is! String || key.isEmpty || key.length > 256))) {
      return {'error': 'Invalid record operation'};
    }
    final store = widget.client.spaces,
        data = store.data(widget.nodeId, widget.space.spaceId);
    if (operation == 'list') return {'value': data.records};
    if (operation == 'get') return {'value': data.records[key]};
    try {
      // Method-channel JSON is the only external boundary; no IDs or RPC names
      // supplied by the page are accepted by the native store.
      final value = jsonDecode(jsonEncode(request['value']));
      await store.set(
        widget.nodeId,
        widget.space.spaceId,
        key as String,
        value,
      );
      return {'value': true};
    } catch (_) {
      return {'error': 'Record was not saved'};
    }
  }

  @override
  Widget build(BuildContext context) => InAppWebView(
    webViewEnvironment: widget.environment,
    initialUrlRequest: URLRequest(url: WebUri('$origin/index.html')),
    initialUserScripts: UnmodifiableListView([
      UserScript(
        source: _sdk,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: true,
      ),
    ]),
    initialSettings: InAppWebViewSettings(
      useShouldInterceptRequest: true,
      useShouldOverrideUrlLoading: true,
      javaScriptEnabled: true,
      javaScriptCanOpenWindowsAutomatically: false,
      supportMultipleWindows: true,
      allowFileAccess: false,
      allowContentAccess: false,
      allowFileAccessFromFileURLs: false,
      allowUniversalAccessFromFileURLs: false,
      domStorageEnabled: false,
      databaseEnabled: false,
      thirdPartyCookiesEnabled: false,
      incognito: true,
      mediaPlaybackRequiresUserGesture: true,
      disableDefaultErrorPage: true,
    ),
    onWebViewCreated: (view) async {
      controller = view;
      view.addJavaScriptHandler(handlerName: 'spaceData', callback: bridge);
      if (Platform.isWindows) {
        desktopVisible =
            await windowManager.isVisible() &&
            !await windowManager.isMinimized();
      }
      if (!mounted) return;
      if (!visible || !desktopVisible) unawaited(activity(false));
    },
    shouldInterceptRequest: (_, request) => resource(request),
    shouldOverrideUrlLoading: (_, action) async {
      final uri = Uri.tryParse(action.request.url.toString());
      return uri?.scheme == 'https' && uri?.origin == origin
          ? NavigationActionPolicy.ALLOW
          : NavigationActionPolicy.CANCEL;
    },
    onCreateWindow: (_, _) async => false,
    onPermissionRequest: (_, request) async => PermissionResponse(
      resources: request.resources,
      action: PermissionResponseAction.DENY,
    ),
    onGeolocationPermissionsShowPrompt: (_, origin) async =>
        GeolocationPermissionShowPromptResponse(
          origin: origin,
          allow: false,
          retain: false,
        ),
    onReceivedError: (_, request, _) {
      if (request.isForMainFrame == true && mounted) widget.onError();
    },
  );
}
