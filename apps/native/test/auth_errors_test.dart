import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/account.dart';
import 'package:nekodot_native/features/auth_errors.dart';

void main() {
  test('only credential verification describes a 401 as a wrong password', () {
    final client = NekodotClient();
    final rejected = RelayError(
      'server text is not the UI contract',
      'unauthorized',
      401,
    );
    expect(authError(client, rejected, checkingPassword: true), '密码或邮箱错误');
    expect(authError(client, rejected), '登录已过期，请重新登录');
    client.prefs.language = 'en';
    expect(
      authError(client, rejected, checkingPassword: true),
      'Email or password incorrect',
    );
    client.dispose();
  });
  test(
    'network, limit and service failures never report wrong credentials',
    () {
      final client = NekodotClient();
      expect(
        authError(
          client,
          RelayError('raw', 'unavailable', 429),
          checkingPassword: true,
        ),
        '请求过于频繁，请稍后重试',
      );
      expect(
        authError(client, RelayError('raw', '', 502), checkingPassword: true),
        '服务暂时不可用',
      );
      expect(
        authError(client, const SocketException('private host')),
        '无法连接服务器',
      );
      expect(
        authError(client, TimeoutException('private request')),
        '请求超时，请重试',
      );
      expect(
        authError(client, const FormatException('private payload')),
        '请求失败，请重试',
      );
      client.dispose();
    },
  );
}
