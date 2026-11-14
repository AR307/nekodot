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

/// A space served as a site of its own: where it lives, what it may load,
/// and the bridge to its records. The page shows it; the picture of a space
/// nobody has opened is taken through the same door.
class SpaceSite {
  final NekodotClient client;
  final String nodeId;
  final Space space;
  final SpaceBundle bundle;

  /// Whether the site may change its records.
  final bool writes;

  /// The account it was opened under; it stops answering under another.
  final Object? owner;
  SpaceSite({
    required this.client,
    required this.nodeId,
    required this.space,
    required this.bundle,
    this.writes = true,
  }) : owner = client.store;

  String get origin => 'https://s-${space.spaceId}.nekodot.invalid';
  // Opaque sandbox origins have no persistent web storage. Only our SDK can
  // persist data. Explicit resource origins keep local modules/fetch working.
  String get csp =>
      "default-src 'none'; sandbox allow-scripts allow-forms; "
      "script-src $origin 'unsafe-inline'; style-src $origin 'unsafe-inline'; "
      "img-src $origin data: blob: ${space.allowedOrigins.join(' ')}; "
      "font-src $origin; media-src $origin blob: ${space.allowedOrigins.join(' ')}; "
      "connect-src $origin ${space.allowedOrigins.join(' ')}; "
      "frame-src 'none'; worker-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'";

  URLRequest get home => URLRequest(url: WebUri('$origin/index.html'));
  UnmodifiableListView<UserScript> get scripts => UnmodifiableListView([
    UserScript(
      source: _sdk,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: true,
    ),
  ]);
  InAppWebViewSettings get settings => InAppWebViewSettings(
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
  );

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
      if (uri.scheme == 'https' && space.allowedOrigins.contains(uri.origin)) {
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
    final bytes = bundle.files[path.isEmpty ? 'index.html' : path];
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
    if (owner == null || !identical(owner, client.store)) {
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
    final store = client.spaces, data = store.data(nodeId, space.spaceId);
    if (operation == 'list') return {'value': data.records};
    if (operation == 'get') return {'value': data.records[key]};
    if (!writes) return {'error': 'Record was not saved'};
    try {
      // Method-channel JSON is the only external boundary; no IDs or RPC names
      // supplied by the page are accepted by the native store.
      final value = jsonDecode(jsonEncode(request['value']));
      await store.set(nodeId, space.spaceId, key as String, value);
      return {'value': true};
    } catch (_) {
      return {'error': 'Record was not saved'};
    }
  }

  /// The site stays on its own pages.
  NavigationActionPolicy navigation(NavigationAction action) {
    final uri = Uri.tryParse(action.request.url.toString());
    return uri?.scheme == 'https' && uri?.origin == origin
        ? NavigationActionPolicy.ALLOW
        : NavigationActionPolicy.CANCEL;
  }

  static Future<PermissionResponse> deny(
    InAppWebViewController _,
    PermissionRequest request,
  ) async => PermissionResponse(
    resources: request.resources,
    action: PermissionResponseAction.DENY,
  );
  static Future<GeolocationPermissionShowPromptResponse> nowhere(
    InAppWebViewController _,
    String origin,
  ) async => GeolocationPermissionShowPromptResponse(
    origin: origin,
    allow: false,
    retain: false,
  );
}

/// What a picture of a space is kept as.
final _shot = ScreenshotConfiguration(
  compressFormat: CompressFormat.JPEG,
  quality: 72,
);

/// How long a site is given to read its records and draw after it loads.
const _settle = Duration(milliseconds: 600);

/// What [site] draws when it is loaded out of sight at [size]: null when it
/// does not load in time. Nothing of it is ever shown.
Future<Uint8List?> pictureOf(
  SpaceSite site,
  Size size,
  WebViewEnvironment? environment,
) async {
  const patience = Duration(seconds: 20);
  final loaded = Completer<bool>();
  final view = HeadlessInAppWebView(
    webViewEnvironment: environment,
    initialSize: size,
    initialUrlRequest: site.home,
    initialUserScripts: site.scripts,
    initialSettings: site.settings,
    onWebViewCreated: (view) => view.addJavaScriptHandler(
      handlerName: 'spaceData',
      callback: site.bridge,
    ),
    shouldInterceptRequest: (_, request) => site.resource(request),
    shouldOverrideUrlLoading: (_, action) async => site.navigation(action),
    onCreateWindow: (_, _) async => false,
    onPermissionRequest: SpaceSite.deny,
    onGeolocationPermissionsShowPrompt: SpaceSite.nowhere,
    onLoadStop: (_, _) {
      if (!loaded.isCompleted) loaded.complete(true);
    },
    onReceivedError: (_, request, _) {
      if (request.isForMainFrame == true && !loaded.isCompleted) {
        loaded.complete(false);
      }
    },
  );
  await view.run();
  try {
    if (!await loaded.future.timeout(patience, onTimeout: () => false)) {
      return null;
    }
    if (Platform.isWindows) {
      // WebView2 out of sight sits in a window with a frame and is sized in
      // raw pixels: the page is told it has exactly the room asked for.
      await view.webViewController?.callDevToolsProtocolMethod(
        methodName: 'Emulation.setDeviceMetricsOverride',
        parameters: {
          'width': size.width.round(),
          'height': size.height.round(),
          'deviceScaleFactor': 0,
          'mobile': false,
        },
      );
    }
    await Future<void>.delayed(_settle);
    return await view.webViewController
        ?.takeScreenshot(screenshotConfiguration: _shot)
        .timeout(patience, onTimeout: () => null);
  } finally {
    await view.dispose();
  }
}

class SpaceWebView extends StatefulWidget {
  final NekodotClient client;
  final String nodeId;
  final Space space;
  final SpaceBundle bundle;
  final WebViewEnvironment? environment;
  final VoidCallback onError;

  /// The site has loaded and had time to draw.
  final VoidCallback onDrawn;
  const SpaceWebView({
    super.key,
    required this.client,
    required this.nodeId,
    required this.space,
    required this.bundle,
    this.environment,
    required this.onError,
    required this.onDrawn,
  });
  @override
  State<SpaceWebView> createState() => _SpaceWebViewState();
}

class _SpaceWebViewState extends State<SpaceWebView>
    with WidgetsBindingObserver, WindowListener {
  InAppWebViewController? controller;
  late final site = SpaceSite(
    client: widget.client,
    nodeId: widget.nodeId,
    space: widget.space,
    bundle: widget.bundle,
  );
  Timer? settling;
  bool visible = true;
  bool desktopVisible = true;
  bool pageVisible = true;
  bool appActive = true;

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
    // Navigator disables tickers for routes covered by an opaque page, but
    // keeps them enabled under a menu/dialog. WebView2.pause also hides the
    // surface, so merely losing route.isCurrent must not pause a visible site.
    final next = TickerMode.valuesOf(context).enabled;
    if (pageVisible == next) return;
    pageVisible = next;
    updateActivity();
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
      unawaited(activity(pageVisible && desktopVisible && appActive));

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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      appActive = true;
    } else if (state != AppLifecycleState.inactive) {
      appActive = false;
    } else {
      return;
    }
    updateActivity();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.client.spaces.removeListener(recordsChanged);
    if (Platform.isWindows) windowManager.removeListener(this);
    settling?.cancel();
    // Android timers are process-wide; do not leave the next space paused.
    if (!visible && Platform.isAndroid) unawaited(controller?.resumeTimers());
    controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InAppWebView(
    webViewEnvironment: widget.environment,
    initialUrlRequest: site.home,
    initialUserScripts: site.scripts,
    initialSettings: site.settings,
    onWebViewCreated: (view) async {
      controller = view;
      view.addJavaScriptHandler(
        handlerName: 'spaceData',
        callback: (args) async =>
            mounted ? site.bridge(args) : {'error': 'Space closed'},
      );
      if (Platform.isWindows) {
        desktopVisible =
            await windowManager.isVisible() &&
            !await windowManager.isMinimized();
      }
      if (!mounted) return;
      updateActivity();
    },
    shouldInterceptRequest: (_, request) => site.resource(request),
    shouldOverrideUrlLoading: (_, action) async => site.navigation(action),
    onCreateWindow: (_, _) async => false,
    onPermissionRequest: SpaceSite.deny,
    onGeolocationPermissionsShowPrompt: SpaceSite.nowhere,
    // Loaded, and given time to read its records and draw, it can be seen.
    onLoadStop: (_, _) => settling ??= Timer(_settle, widget.onDrawn),
    onReceivedError: (_, request, _) {
      if (request.isForMainFrame == true && mounted) widget.onError();
    },
  );
}
