import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'json.dart';

class RelayError implements Exception {
  final String message, code;
  final int status;
  RelayError(this.message, [this.code = '', this.status = 0]);
  @override
  String toString() => message;
}

bool isTransientConnectionError(Object error) =>
    error is SocketException ||
    error is WebSocketException ||
    error is TimeoutException ||
    error is http.ClientException ||
    (error is RelayError &&
        (const [
              'disconnected',
              'unavailable',
              'node_offline',
              'timeout',
            ].contains(error.code) ||
            error.status >= 500));

class AccountSession extends ChangeNotifier {
  final Uri origin;
  final http.Client transport;
  final FlutterSecureStorage vault;
  AccountSession({
    required String server,
    http.Client? transport,
    FlutterSecureStorage? vault,
  }) : origin = Uri.parse(server),
       transport = transport ?? http.Client(),
       vault =
           vault ??
           const FlutterSecureStorage(
             mOptions: MacOsOptions(usesDataProtectionKeychain: false),
           );
  String? _token;
  Json? _me;
  String? get token => _token;
  set token(String? value) {
    _token = value;
    notifyListeners();
  }

  Json? get me => _me;
  set me(Json? value) {
    _me = value;
    notifyListeners();
  }

  Uri url(String path) => origin.replace(path: path);
  Uri wsUrl(String path, [Map<String, String>? query]) => origin.replace(
    scheme: origin.scheme == 'https' ? 'wss' : 'ws',
    path: path,
    queryParameters: query,
  );
  Future<void> load() async {
    if (origin.scheme != 'https' &&
        !['127.0.0.1', 'localhost'].contains(origin.host)) {
      throw ArgumentError('A trusted HTTPS Relay is required');
    }
    token = await vault.read(key: 'nekodot-session');
  }

  Future<void> accept(Json result) async {
    if (result['token'] == null) {
      throw RelayError('Email verification required', 'verification_required');
    }
    token = result['token'] as String;
    await vault.write(key: 'nekodot-session', value: token!);
  }

  Future<void> clear() async {
    token = null;
    me = null;
    await vault.delete(key: 'nekodot-session');
  }

  Future<Json> request(String path, {String method = 'GET', Json? body}) async {
    final req = http.Request(method, url('/api$path'));
    req.headers['Content-Type'] = 'application/json';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);
    final response = await transport
        .send(req)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode >= 400) {
      // Reverse proxies may return an HTML error page; retain the HTTP status.
      final e =
          response.headers['content-type']?.contains('application/json') == true
          ? object(object(jsonDecode(response.body))['error'] ?? {})
          : <String, dynamic>{};
      throw RelayError(
        '${e['message'] ?? 'HTTP ${response.statusCode}'}',
        '${e['code'] ?? ''}',
        response.statusCode,
      );
    }
    return object(jsonDecode(response.body));
  }

  @override
  void dispose() {
    transport.close();
    super.dispose();
  }
}
