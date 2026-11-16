import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'account.dart';
import 'json.dart';

/// Why a Google or GitHub sign-in came back without a session: `denied`,
/// `unverified`, `failed`, `expired` or `cancelled`.
class OAuthRefused implements Exception {
  final String reason;
  OAuthRefused(this.reason);
  @override
  String toString() => 'OAuthRefused($reason)';
}

/// Opens [url] in the system's browser; tests pass their own.
typedef OpenBrowser = Future<bool> Function(Uri url);

/// Signs in through Google or GitHub. The provider opens in the browser, the
/// Relay sends a one-time code back to this app (a listener on 127.0.0.1 on a
/// computer; on Android the nekodot://oauth link, which OAuthReturnActivity
/// hands over), and the app redeems it with a verifier that never left it, so
/// a code that reaches anyone else is useless.
class OAuthSignIn {
  final AccountSession account;
  final String provider;
  final OpenBrowser open;
  OAuthSignIn(this.account, this.provider, {OpenBrowser? open})
    : open = open ?? _openBrowser;

  static const _link = MethodChannel('app.nekodot/oauth');
  static Completer<Uri>? _linked;
  // Giving up may come before anyone waits on it; the waiting below still sees it.
  late final _returned = Completer<Uri>()..future.ignore();

  /// The providers this Relay offers, in the order it lists them.
  static Future<List<String>> offered(AccountSession account) async => [
    for (final name
        in (await account.request('/auth/providers'))['providers'] as List)
      '$name',
  ];

  /// Gives up waiting for the browser; [run] ends with `cancelled`.
  void cancel() {
    if (!_returned.isCompleted) {
      _returned.completeError(OAuthRefused('cancelled'));
    }
  }

  /// Runs the sign-in and returns the Relay's session, ready for
  /// `NekodotClient.acceptSession`.
  Future<Json> run() async {
    final verifier = _verifier();
    final digest = await Sha256().hash(ascii.encode(verifier));
    final challenge = base64Url.encode(digest.bytes).replaceAll('=', '');
    final server = Platform.isAndroid
        ? null
        : await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final returnTo = server == null
        ? 'nekodot://oauth'
        : 'http://127.0.0.1:${server.port}/oauth';
    if (server == null) {
      _linked = Completer<Uri>();
      _link.setMethodCallHandler((call) async {
        if (call.method == 'returned' && !(_linked?.isCompleted ?? true)) {
          _linked!.complete(Uri.parse('${call.arguments}'));
        }
      });
      unawaited(_linked!.future.then(_finish));
    } else {
      server.listen((request) => _answer(request));
    }
    try {
      final start = account
          .url('/api/auth/oauth/$provider')
          .replace(
            queryParameters: {'challenge': challenge, 'return': returnTo},
          );
      if (!await open(start)) throw OAuthRefused('failed');
      final back = await _returned.future.timeout(
        const Duration(minutes: 10),
        onTimeout: () => throw OAuthRefused('expired'),
      );
      final refused = back.queryParameters['error'];
      if (refused != null) throw OAuthRefused(refused);
      final code = back.queryParameters['code'];
      if (code == null) throw OAuthRefused('failed');
      try {
        return await account.request(
          '/auth/oauth/token',
          method: 'POST',
          body: {'code': code, 'verifier': verifier},
        );
      } on RelayError catch (error) {
        if (error.code == 'invalid_code') throw OAuthRefused('expired');
        rethrow;
      }
    } finally {
      await server?.close(force: true);
      if (server == null) {
        _linked = null;
        _link.setMethodCallHandler(null);
      }
    }
  }

  void _finish(Uri back) {
    if (!_returned.isCompleted) _returned.complete(back);
  }

  /// The browser arrives at the loopback listener; it gets a page that says
  /// where to go next, and the app gets the code.
  Future<void> _answer(HttpRequest request) async {
    if (request.uri.path != '/oauth' || _returned.isCompleted) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final ok = request.uri.queryParameters.containsKey('code');
    request.response.headers.contentType = ContentType.html;
    request.response.write(
      '<!doctype html><meta charset="utf-8"><title>nekodot</title>'
      '<meta name="viewport" content="width=device-width">'
      '<body style="font:16px system-ui,sans-serif;display:grid;place-items:center;'
      'min-height:90vh;margin:0;text-align:center">'
      '<div><p>${ok ? '已登录，可以回到 nekodot 了。' : '没有完成登录，请回到 nekodot。'}</p>'
      '<p>${ok ? 'Signed in. You can go back to nekodot.' : 'Sign-in was not completed. Go back to nekodot.'}</p></div>',
    );
    await request.response.close();
    _finish(request.uri);
  }

  static String _verifier() {
    final random = Random.secure();
    final bytes = [for (var i = 0; i < 32; i++) random.nextInt(256)];
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  // The default browser, in its own task, so that on Android the app's task
  // can simply come back to the front when the sign-in returns.
  static Future<bool> _openBrowser(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);
}
