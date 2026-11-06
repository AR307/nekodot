import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/client.dart';
import '../platform/desktop.dart';
import '../ui/design.dart';
import '../ui/auth_layout.dart';
import 'auth_errors.dart';
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
  bool busy = false, showPassword = false;
  int seconds = 0;
  Timer? countdown;
  DateTime? retryAt;
  NekodotClient get c => widget.client;

  String? validate({bool needsPassword = true, bool needsCode = false}) {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.text.trim())) {
      return c.tr('请输入有效的邮箱', 'Enter a valid email address');
    }
    if (needsPassword && password.text.isEmpty) {
      return c.tr('请输入密码', 'Enter your password');
    }
    if (needsPassword &&
        (mode == 'signup' || mode == 'reset') &&
        password.text.length < 8) {
      return c.tr('密码至少需要 8 个字符', 'Use at least 8 characters for the password');
    }
    if (needsCode && !RegExp(r'^\d{6}$').hasMatch(code.text.trim())) {
      return c.tr('请输入 6 位邮箱验证码', 'Enter the 6-digit email code');
    }
    return null;
  }

  Future<void> sendCode() async {
    if (busy || seconds > 0) return;
    final invalid = validate(needsPassword: mode == 'verify');
    if (invalid != null) {
      setState(() => error = invalid);
      return;
    }
    setState(() {
      busy = true;
      error = '';
      notice = '';
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
          seconds = 60;
          retryAt = DateTime.now().add(const Duration(seconds: 60));
          notice = c.tr(
            '若邮箱符合条件，验证码已发出，10 分钟内有效。',
            'If eligible, a code has been sent. It expires in 10 minutes.',
          );
        });
        countdown?.cancel();
        countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) return timer.cancel();
          final remaining =
              (retryAt!.difference(DateTime.now()).inMilliseconds / 1000)
                  .ceil();
          setState(() => seconds = remaining.clamp(0, 60));
          if (seconds == 0) timer.cancel();
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = authError(c, e, sendingCode: true));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    if (busy) return;
    FocusScope.of(context).unfocus();
    final invalid = validate(needsCode: mode != 'login');
    if (invalid != null) {
      setState(() => error = invalid);
      return;
    }
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
            'code': code.text.trim(),
          },
        );
        if (mounted) {
          setState(() {
            mode = 'login';
            showPassword = false;
            code.clear();
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
              'code': code.text.trim(),
            },
          ),
        );
      }
    } on RelayError catch (e) {
      if (mounted) {
        setState(() {
          if (e.code == 'verification_required') {
            mode = 'verify';
            showPassword = false;
            code.clear();
            error = c.tr(
              '请验证这个账号的邮箱，已有电脑和历史会保留。',
              'Verify this account’s email. Your computers and history will be kept.',
            );
          } else {
            error = authError(
              c,
              e,
              checkingPassword: mode == 'login' || mode == 'verify',
            );
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = authError(c, e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void switchTo(String next) => setState(() {
    mode = next;
    showPassword = false;
    code.clear();
    error = '';
    notice = '';
  });

  @override
  void dispose() {
    countdown?.cancel();
    email.dispose();
    password.dispose();
    code.dispose();
    super.dispose();
  }

  Widget field(String label, Widget input) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      input,
    ],
  );

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final text = Theme.of(context).textTheme;
    final heading = switch (mode) {
      'signup' => c.tr('创建你的账号', 'Create your account'),
      'verify' => c.tr('验证邮箱', 'Verify email'),
      'reset' => c.tr('重置密码', 'Reset password'),
      _ => c.tr('欢迎回来', 'Welcome back'),
    };
    final form = AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            heading,
            style: text.headlineMedium?.copyWith(
              fontSize: 30,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            c.tr(
              '把你的 AI 小队，带到自己的电脑上。',
              'Your AI team, running on your own computer.',
            ),
            style: text.bodyMedium?.copyWith(color: tone.ink2, height: 1.7),
          ),
          const SizedBox(height: 28),
          field(
            c.tr('邮箱', 'Email'),
            TextField(
              key: const ValueKey('auth-email'),
              controller: email,
              enabled: !busy,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                hintText: 'you@example.com',
                prefixIcon: const Icon(Icons.alternate_email, size: 18),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(c.tr('密码', 'Password'), style: text.labelLarge),
              const Spacer(),
              if (mode == 'login')
                TextButton(
                  onPressed: busy ? null : () => switchTo('reset'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(
                    c.tr('忘记密码', 'Forgot password?'),
                    style: text.bodySmall?.copyWith(color: tone.ink2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('auth-password'),
            controller: password,
            enabled: !busy,
            obscureText: !showPassword,
            enableSuggestions: false,
            autocorrect: false,
            textInputAction: mode == 'login'
                ? TextInputAction.done
                : TextInputAction.next,
            autofillHints: [
              mode == 'signup' || mode == 'reset'
                  ? AutofillHints.newPassword
                  : AutofillHints.password,
            ],
            decoration: InputDecoration(
              hintText: c.tr('至少 8 位密码', 'At least 8 characters'),
              prefixIcon: const Icon(Icons.lock_outline, size: 18),
              suffixIcon: IconButton(
                key: const ValueKey('auth-reveal-password'),
                tooltip: showPassword
                    ? c.tr('隐藏密码', 'Hide password')
                    : c.tr('显示密码', 'Show password'),
                isSelected: showPassword,
                style: IconButton.styleFrom(minimumSize: const Size.square(44)),
                onPressed: busy
                    ? null
                    : () => setState(() => showPassword = !showPassword),
                icon: const Icon(Icons.visibility_outlined),
                selectedIcon: const Icon(Icons.visibility_off_outlined),
              ),
            ),
            onSubmitted: (_) {
              if (mode == 'login' && !busy) submit();
            },
          ),
          if (mode != 'login') ...[
            const SizedBox(height: 20),
            field(
              c.tr('邮箱验证码', 'Email code'),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('auth-code'),
                      controller: code,
                      enabled: !busy,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: InputDecoration(
                        hintText: c.tr('6 位验证码', '6-digit code'),
                        prefixIcon: const Icon(Icons.key_outlined, size: 18),
                      ),
                      onSubmitted: (_) => submit(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      key: const ValueKey('auth-send-code'),
                      onPressed: busy || seconds > 0 ? null : sendCode,
                      child: Text(
                        seconds > 0
                            ? '${seconds}s'
                            : c.tr('获取验证码', 'Send code'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (error.isNotEmpty) ErrorNotice(error),
          if (notice.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  notice,
                  style: text.bodySmall?.copyWith(color: tone.ink2),
                ),
              ),
            ),
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: FilledButton(
              key: const ValueKey('auth-submit'),
              onPressed: busy ? null : submit,
              child: busy
                  ? ShiningText(text: c.tr('正在提交…', 'Submitting…'))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          mode == 'login'
                              ? c.tr('登录', 'Sign in')
                              : mode == 'reset'
                              ? c.tr('更新密码', 'Update password')
                              : c.tr('验证并继续', 'Verify & continue'),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.arrow_forward, size: 17),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  mode == 'login'
                      ? c.tr('第一次来？', 'New here?')
                      : c.tr('已有账号？', 'Already have an account?'),
                  style: text.bodySmall?.copyWith(color: tone.ink2),
                ),
                TextButton(
                  key: const ValueKey('auth-switch-mode'),
                  onPressed: busy
                      ? null
                      : () => switchTo(mode == 'login' ? 'signup' : 'login'),
                  child: Text(
                    mode == 'login'
                        ? c.tr('创建账号', 'Create account')
                        : c.tr('登录', 'Sign in'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified_user_outlined, size: 14, color: tone.ink3),
              const SizedBox(width: 6),
              Text(
                c.tr('数据留在自己手里', 'Your data stays with you'),
                style: text.bodySmall?.copyWith(color: tone.ink3),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            children: [
              TextButton(
                onPressed: () => pushPage(context, UpdatesPage(client: c)),
                child: Text(
                  c.tr('检查更新', 'Check updates'),
                  style: text.bodySmall?.copyWith(color: tone.ink3),
                ),
              ),
              if (DesktopHost.supported)
                TextButton(
                  key: const ValueKey('quit-application'),
                  onPressed: DesktopHost.quit,
                  child: Text(
                    c.tr('退出应用', 'Quit application'),
                    style: text.bodySmall?.copyWith(color: tone.ink3),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            AuthLayout(
              headline: c.tr(
                '一个会干活的 AI 小队，住在你自己的电脑里。',
                'A working AI team that lives on your own computer.',
              ),
              description: c.tr(
                '创建几只有名字的 bot，私聊或拉进群里协作。它们在你的电脑上运行，数据不离开你的机器。',
                'Create bots with their own names. Chat one-on-one or bring them together in a group. They run on your computer, where your data stays.',
              ),
              home: TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse('https://nekodot.com'),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.chevron_left, size: 18),
                label: Text(c.tr('返回首页', 'Home')),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(
                  inputDecorationTheme: Theme.of(context).inputDecorationTheme
                      .copyWith(
                        constraints: const BoxConstraints(minHeight: 46),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                ),
                child: form,
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
}
