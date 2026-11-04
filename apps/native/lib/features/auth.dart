import 'package:flutter/material.dart';

import '../data/client.dart';
import '../platform/desktop.dart';
import '../ui/design.dart';
import '../ui/auth_frame.dart';
import 'updates.dart';

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
          AuthFrame(
            zh: c.zh,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    CatAvatar(size: 28),
                    SizedBox(width: 8),
                    Text(
                      'nekoDOT',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(switch (mode) {
                  'signup' => c.tr('创建账号', 'Create account'),
                  'reset' => c.tr('重置密码', 'Reset password'),
                  'verify' => c.tr('验证邮箱', 'Verify email'),
                  _ => c.tr('登录', 'Sign in'),
                }, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  c.tr(
                    '把你的 AI 小队，带到自己的电脑上。',
                    'Bring your AI crew to your own computer.',
                  ),
                  style: TextStyle(color: context.tone.ink2, height: 1.6),
                ),
                const SizedBox(height: 24),
                TextField(
                  key: const ValueKey('auth-email'),
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(hintText: c.tr('邮箱', 'Email')),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('auth-password'),
                  controller: password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(hintText: c.tr('密码', 'Password')),
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
                            hintText: c.tr('6 位验证码', '6-digit code'),
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
                      ? ShiningText(text: c.tr('正在提交…', 'Submitting…'))
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
                    if (DesktopHost.supported)
                      TextButton(
                        key: const ValueKey('quit-application'),
                        onPressed: DesktopHost.quit,
                        child: Text(c.tr('退出应用', 'Quit application')),
                      ),
                    TextButton(
                      onPressed: () =>
                          pushPage(context, UpdatesPage(client: c)),
                      child: Text(c.tr('检查更新', 'Check updates')),
                    ),
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
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 44,
            child: WindowDrag(key: ValueKey('auth-window-drag')),
          ),
          Positioned(
            right: 12 + WindowChrome.reserved(context),
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
