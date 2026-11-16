import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nekodot_native/data/account.dart';
import 'package:nekodot_native/data/oauth_sign_in.dart';

/// A Relay that lists both providers and redeems `grant-1` for whoever holds
/// the verifier behind the challenge the browser was sent with.
class FakeRelay {
  String? challenge;
  final redeemed = <Map<String, dynamic>>[];
  late final account = AccountSession(
    server: 'http://127.0.0.1:4319',
    transport: MockClient((request) async {
      if (request.url.path == '/api/auth/providers') {
        return http.Response(
          jsonEncode({
            'providers': ['google', 'github'],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      redeemed.add(body);
      final digest = await Sha256().hash(ascii.encode('${body['verifier']}'));
      final proof = base64Url.encode(digest.bytes).replaceAll('=', '');
      if (body['code'] != 'grant-1' || proof != challenge) {
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'invalid_code',
              'message': 'Code is invalid or expired',
            },
          }),
          400,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'token': 'session-1'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

/// The browser: follows the Relay's start link and, after the provider, comes
/// back to the address the app asked for with what the Relay appended.
Future<String> arrive(Uri start, Map<String, String> back) async {
  final to = Uri.parse(start.queryParameters['return']!)
      .replace(queryParameters: back);
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(to)).close();
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

void main() {
  test('lists the providers the Relay offers', () async {
    expect(await OAuthSignIn.offered(FakeRelay().account), [
      'google',
      'github',
    ]);
  });

  test('a computer receives the code on 127.0.0.1 and redeems it with its verifier', () async {
    final relay = FakeRelay();
    Uri? opened;
    String? page;
    final signIn = OAuthSignIn(
      relay.account,
      'google',
      open: (url) async {
        opened = url;
        relay.challenge = url.queryParameters['challenge'];
        arrive(url, {'code': 'grant-1'}).then((body) => page = body);
        return true;
      },
    );
    final session = await signIn.run();
    expect(session['token'], 'session-1');
    expect(opened!.path, '/api/auth/oauth/google');
    expect(
      opened!.queryParameters['return'],
      matches(RegExp(r'^http://127\.0\.0\.1:\d+/oauth$')),
    );
    expect(relay.challenge, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    // The verifier goes only to the Relay, never into the browser.
    final verifier = '${relay.redeemed.single['verifier']}';
    expect(opened.toString(), isNot(contains(verifier)));
    while (page == null) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(page, contains('Signed in'));
  });

  test('a refusal, a lost code and giving up end without a session', () async {
    Future<String> attempt(
      Map<String, String>? back, {
      bool cancel = false,
    }) async {
      final relay = FakeRelay();
      late OAuthSignIn signIn;
      signIn = OAuthSignIn(
        relay.account,
        'github',
        open: (url) async {
          relay.challenge = 'not-the-challenge-of-this-verifier-000000000';
          if (back != null) arrive(url, back);
          if (cancel) signIn.cancel();
          return true;
        },
      );
      try {
        await signIn.run();
        return 'signed in';
      } on OAuthRefused catch (refused) {
        return refused.reason;
      }
    }

    expect(await attempt({'error': 'denied'}), 'denied');
    expect(await attempt({'error': 'unverified'}), 'unverified');
    expect(await attempt({'code': 'grant-1'}), 'expired');
    expect(await attempt(null, cancel: true), 'cancelled');
  });
}
