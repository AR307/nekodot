import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/client.dart';
import '../data/account.dart';

String authError(
  NekodotClient client,
  Object error, {
  bool checkingPassword = false,
  bool sendingCode = false,
}) {
  if (error is RelayError) {
    if (error.status == 429) {
      return client.tr('请求过于频繁，请稍后重试', 'Too many attempts. Try again later');
    }
    if (error.code == 'unauthorized' && error.status == 401) {
      return checkingPassword
          ? client.tr('密码或邮箱错误', 'Email or password incorrect')
          : client.tr('登录已过期，请重新登录', 'Session expired. Sign in again');
    }
    if (error.code == 'invalid_code') {
      return client.tr('验证码错误或已过期', 'Code is invalid or expired');
    }
    if (error.status >= 500) {
      return sendingCode
          ? client.tr(
              '验证码发送失败，请稍后重试',
              'Unable to send the code. Try again later',
            )
          : client.tr('服务暂时不可用', 'Service temporarily unavailable');
    }
  }
  if (error is TimeoutException) {
    return client.tr('请求超时，请重试', 'Request timed out. Try again');
  }
  if (error is SocketException ||
      error is HandshakeException ||
      error is http.ClientException) {
    return client.tr('无法连接服务器', 'Unable to connect to the server');
  }
  return client.tr('请求失败，请重试', 'Request failed. Try again');
}
