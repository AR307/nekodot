import 'package:flutter/material.dart';

import '../data/client.dart';
import '../ui/design.dart';

class AuthPage extends StatefulWidget {
  final NekodotClient client;
  const AuthPage({super.key, required this.client});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final email = TextEditingController(),
      password = TextEditingController(),
      code = TextEditingController();
  String mode = 'login', error = '', notice = '';
  bool busy = false, sent = false;
  NekodotClient get c => widget.client;
  Future<void> sendCode() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await c.request(
        '/auth/code',
        method: 'POST',
        body: {
          'email': email.text.trim(),
          'purpose': mode == 'reset'
              ? 'reset'
              : mode == 'verify'
              ? 'verify'
              : 'signup',
          if (mode == 'verify') 'password': password.text,
        },
      );
      if (mounted) {
        setState(() {
          sent = true;
          notice = c.tr('如可发送，验证码已发出', 'Code sent if eligible');
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = '';
    });
    try {
      if (mode == 'login') {
        await c.login(email.text.trim(), password.text);
      } else if (mode == 'reset') {
        await c.request(
          '/auth/password/reset',
          method: 'POST',
          body: {
            'email': email.text.trim(),
            'password': password.text,
            'code': code.text,
          },
        );
        if (mounted) {
          setState(() {
            mode = 'login';
            notice = c.tr('密码已更新', 'Password updated');
          });
        }
      } else {
        await c.acceptSession(
          await c.request(
            '/auth/${mode == 'verify' ? 'verify' : 'signup'}',
            method: 'POST',
            body: {
              'email': email.text.trim(),
              'password': password.text,
              'code': code.text,
            },
          ),
        );
      }
    } on RelayError catch (e) {
      if (mounted) {
        setState(() {
          error = e.message;
          if (e.code == 'verification_required') mode = 'verify';
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void switchTo(String next) => setState(() {
    mode = next;
    error = '';
    notice = '';
  });

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: CatAvatar(size: 84)),
                    const SizedBox(height: 14),
                    Text(
                      'nekodot',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      key: const ValueKey('auth-email'),
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(
                        labelText: c.tr('邮箱', 'Email'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const ValueKey('auth-password'),
                      controller: password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: c.tr('密码', 'Password'),
                      ),
                      onSubmitted: (_) {
                        if (mode == 'login') submit();
                      },
                    ),
                    if (mode != 'login') ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: code,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: c.tr('6 位验证码', '6-digit code'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: busy ? null : sendCode,
                            child: Text(
                              sent
                                  ? c.tr('重新发送', 'Resend')
                                  : c.tr('获取验证码', 'Send code'),
                            ),
                          ),
                        ],
                      ),
                    ],
                    ErrorNotice(error),
                    if (notice.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          notice,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: busy ? null : submit,
                      child: busy
                          ? const Breathing()
                          : Text(
                              mode == 'login'
                                  ? c.tr('登录', 'Sign in')
                                  : mode == 'reset'
                                  ? c.tr('更新密码', 'Update password')
                                  : c.tr('验证并继续', 'Verify & continue'),
                            ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        if (mode != 'signup')
                          TextButton(
                            onPressed: () => switchTo('signup'),
                            child: Text(c.tr('创建账号', 'Create account')),
                          ),
                        if (mode != 'login')
                          TextButton(
                            onPressed: () => switchTo('login'),
                            child: Text(c.tr('登录', 'Sign in')),
                          ),
                        if (mode != 'reset')
                          TextButton(
                            onPressed: () => switchTo('reset'),
                            child: Text(c.tr('忘记密码', 'Forgot password')),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: 8,
            child: TextButton(
              onPressed: () => c.preferences(locale: c.zh ? 'en' : 'zh'),
              child: Text(c.zh ? 'EN' : '中'),
            ),
          ),
        ],
      ),
    ),
  );
}
