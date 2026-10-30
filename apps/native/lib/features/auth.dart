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
          notice = c.tr(
            '如可发送，验证码将发往此邮箱。10 分钟内有效。',
            'If eligible, a code will arrive in your inbox. It expires in 10 minutes.',
          );
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
            notice = c.tr('密码已更新，请重新登录。', 'Password updated. Sign in again.');
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
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: CatAvatar(size: 68)),
                const SizedBox(height: 16),
                Text(
                  'nekodot',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  c.tr('你的 AI 团队，随时在身边。', 'Your AI team, always by your side.'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),
                Text(
                  mode == 'login'
                      ? c.tr('欢迎回来', 'Welcome back')
                      : mode == 'reset'
                      ? c.tr('重置密码', 'Reset password')
                      : mode == 'verify'
                      ? c.tr('验证你的邮箱', 'Verify your email')
                      : c.tr('创建账号', 'Create account'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 20),
                TextField(
                  key: const ValueKey('auth-email'),
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(labelText: c.tr('邮箱', 'Email')),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('auth-password'),
                  controller: password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: c.tr('密码（至少 8 位）', 'Password (8+ characters)'),
                  ),
                  onSubmitted: (_) {
                    if (mode == 'login') submit();
                  },
                ),
                if (mode != 'login') ...[
                  const SizedBox(height: 14),
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
                      const SizedBox(width: 10),
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
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(notice),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: Text(
                    busy
                        ? c.tr('请稍候…', 'Please wait…')
                        : mode == 'login'
                        ? c.tr('登录', 'Sign in')
                        : mode == 'reset'
                        ? c.tr('更新密码', 'Update password')
                        : c.tr('验证并继续', 'Verify & continue'),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        mode = mode == 'signup' ? 'login' : 'signup';
                        error = '';
                        notice = '';
                      }),
                      child: Text(
                        mode == 'signup'
                            ? c.tr('已有账号？登录', 'Already registered? Sign in')
                            : c.tr('创建账号', 'Create account'),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        mode = mode == 'reset' ? 'login' : 'reset';
                        error = '';
                        notice = '';
                      }),
                      child: Text(c.tr('忘记密码', 'Forgot password')),
                    ),
                    TextButton(
                      onPressed: () =>
                          c.preferences(locale: c.zh ? 'en' : 'zh'),
                      child: Text(c.zh ? 'English' : '中文'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
