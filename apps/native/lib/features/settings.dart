import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/client.dart';
import '../ui/design.dart';
import 'pairing.dart';

class SettingsPage extends StatelessWidget {
  final NekodotClient client;
  const SettingsPage({super.key, required this.client});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: client,
    builder: (context, child) => Scaffold(
      appBar: AppBar(title: Text(client.tr('设置', 'Settings'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                '${client.me?['user']['email'] ?? ''}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: Text(client.tr('模型来源', 'Model sources')),
                subtitle: Text(
                  client.tr(
                    '授权登录和自定义 API 可以共存',
                    'Authorizations and custom APIs coexist',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => pushPage(context, SourcesPage(client: client)),
              ),
              ListTile(
                leading: const Icon(Icons.add_to_queue),
                title: Text(client.tr('添加电脑', 'Add computer')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => pushPage(context, PairingPage(client: client)),
              ),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: Text(client.tr('系统通知', 'System notifications')),
                subtitle: Text(
                  client.notificationError.isNotEmpty
                      ? client.notificationError
                      : client.notificationStatus.isEmpty
                      ? client.tr('正在检查通知状态', 'Checking notification status')
                      : client.notificationStatus,
                ),
                trailing: const Icon(Icons.open_in_new),
                onTap: () async {
                  final opened = await FlutterLocalNotificationsPlugin()
                      .openAppNotificationSettings();
                  if (opened != true && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          client.tr(
                            '请在系统设置的通知列表中找到 nekodot，开启通知。',
                            'Find nekodot in system notification settings to allow notifications.',
                          ),
                        ),
                      ),
                    );
                  }
                },
              ),
              const Divider(height: 32),
              DropdownButtonFormField<String>(
                initialValue: client.language,
                decoration: InputDecoration(
                  labelText: client.tr('语言', 'Language'),
                ),
                items: const [
                  DropdownMenuItem(value: 'zh', child: Text('中文')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                ],
                onChanged: (value) => client.preferences(locale: value),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: client.theme,
                decoration: InputDecoration(
                  labelText: client.tr('外观', 'Appearance'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'system',
                    child: Text(client.tr('跟随系统', 'System')),
                  ),
                  DropdownMenuItem(
                    value: 'light',
                    child: Text(client.tr('浅色', 'Light')),
                  ),
                  DropdownMenuItem(
                    value: 'dark',
                    child: Text(client.tr('深色', 'Dark')),
                  ),
                ],
                onChanged: (value) => client.preferences(appearance: value),
              ),
              const SizedBox(height: 30),
              ListTile(
                leading: const Icon(Icons.password),
                title: Text(client.tr('修改密码', 'Change password')),
                onTap: () => pushPage(context, PasswordPage(client: client)),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await client.logout();
                    if (context.mounted) {
                      Navigator.popUntil(context, (route) => route.isFirst);
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('$e')));
                    }
                  }
                },
                icon: const Icon(Icons.logout),
                label: Text(client.tr('退出账号', 'Sign out')),
              ),
              const SizedBox(height: 22),
              Text(
                'nekodot 0.2.0 · Flutter',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SourcesPage extends StatefulWidget {
  final NekodotClient client;
  const SourcesPage({super.key, required this.client});
  @override
  State<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends State<SourcesPage> {
  int revision = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.client.tr('模型来源', 'Model sources'))),
    body: AsyncPane(
      key: ValueKey(revision),
      load: () => widget.client.rpc('providers.list'),
      builder: (context, data, reload) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            widget.client.tr('授权登录', 'Authorized services'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          for (final provider in objects(data['oauth']))
            Card(
              child: ListTile(
                leading: const Icon(Icons.login),
                title: Text('${provider['name'] ?? provider['id']}'),
                subtitle: Text(
                  (provider['status'] as Map?)?['logged_in'] == true
                      ? widget.client.tr('已授权', 'Authorized')
                      : provider['flow'] == 'external'
                      ? widget.client.tr(
                          '需在节点终端授权',
                          'Authorize in node terminal',
                        )
                      : widget.client.tr('未授权', 'Not authorized'),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await pushPage(
                    context,
                    AuthorizationPage(
                      client: widget.client,
                      provider: provider,
                    ),
                  );
                  reload();
                },
              ),
            ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.client.tr('自定义 API', 'Custom APIs'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: widget.client.tr('新增', 'Add'),
                onPressed: () async {
                  await pushPage(
                    context,
                    CustomSourcePage(client: widget.client),
                  );
                  reload();
                },
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          for (final source in objects(
            data['sources'],
          ).where((s) => s['kind'] == 'custom'))
            Card(
              child: ListTile(
                leading: const Icon(Icons.api),
                title: Text('${source['name']}'),
                subtitle: Text(
                  '${source['baseUrl']}\n••••${source['apiKeyLast4']}',
                ),
                isThreeLine: true,
                onTap: () async {
                  await pushPage(
                    context,
                    CustomSourcePage(client: widget.client, source: source),
                  );
                  reload();
                },
              ),
            ),
        ],
      ),
    ),
  );
}

class CustomSourcePage extends StatefulWidget {
  final NekodotClient client;
  final Json? source;
  const CustomSourcePage({super.key, required this.client, this.source});
  @override
  State<CustomSourcePage> createState() => _CustomSourcePageState();
}

class _CustomSourcePageState extends State<CustomSourcePage> {
  late String? savedId = widget.source?['sourceId'] as String?;
  late final name = TextEditingController(
    text: widget.source?['name'] as String? ?? '',
  );
  late final url = TextEditingController(
    text: widget.source?['baseUrl'] as String? ?? '',
  );
  final key = TextEditingController();
  String error = '';
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    url.dispose();
    key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.client.tr('自定义 API', 'Custom API'))),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(
                labelText: widget.client.tr('名称', 'Name'),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'API URL'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: key,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'API KEY',
                hintText: savedId == null
                    ? null
                    : widget.client.tr(
                        '留空保留已有密钥',
                        'Leave blank to keep saved key',
                      ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              widget.client.tr(
                '保存后从 Hermes 获取模型目录。在创建 Bot 时选择模型，也可填写模型代号。密钥仅保存在服务器。',
                'Hermes loads the model catalog after saving. Select a model when creating a Bot, or enter its ID. Keys stay on the server.',
              ),
            ),
            ErrorNotice(error),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        final saved = await widget.client.rpc('providers.set', {
                          'kind': 'custom',
                          if (savedId != null) 'sourceId': savedId,
                          'name': name.text,
                          'baseUrl': url.text.trim(),
                          if (key.text.isNotEmpty) 'apiKey': key.text,
                        });
                        if (mounted) {
                          setState(() => savedId = saved['sourceId'] as String);
                        }
                        key.clear();
                        final catalog = await widget.client.rpc(
                          'models.options',
                          {'sourceId': saved['sourceId'], 'refresh': true},
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                widget.client.tr(
                                  '已保存 · 获取 ${(catalog['models'] as List).length} 个模型',
                                  'Saved · ${(catalog['models'] as List).length} models loaded',
                                ),
                              ),
                            ),
                          );
                        }
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (mounted) setState(() => error = '$e');
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              child: Text(widget.client.tr('保存并获取模型', 'Save & fetch models')),
            ),
          ],
        ),
      ),
    ),
  );
}

class AuthorizationPage extends StatefulWidget {
  final NekodotClient client;
  final Json provider;
  const AuthorizationPage({
    super.key,
    required this.client,
    required this.provider,
  });
  @override
  State<AuthorizationPage> createState() => _AuthorizationPageState();
}

class _AuthorizationPageState extends State<AuthorizationPage> {
  Json? session;
  String error = '';
  bool busy = false;
  Timer? timer;
  bool? loggedIn;
  bool get authorized =>
      loggedIn ?? (widget.provider['status'] as Map?)?['logged_in'] == true;
  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> action(String actionName) async {
    timer?.cancel();
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final result = await widget.client.rpc('providers.authorize', {
        'provider': widget.provider['id'] ?? widget.provider['provider'],
        'action': actionName,
        if (session?['session_id'] != null) 'sessionId': session!['session_id'],
      });
      if (mounted) {
        setState(() {
          session = actionName == 'disconnect' || actionName == 'cancel'
              ? null
              : {'status': 'pending', ...?session, ...result};
          if (result['status'] == 'approved') loggedIn = true;
          if (actionName == 'disconnect') loggedIn = false;
          error = '';
        });
      }
      final url = result['verification_url'];
      if (actionName == 'start' && url is String) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      if (!mounted) return;
      if (session?['session_id'] != null && session?['status'] == 'pending') {
        timer = Timer(
          Duration(seconds: (session?['poll_interval'] as num?)?.toInt() ?? 5),
          () {
            if (mounted) action('poll');
          },
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.provider['name'] ?? widget.provider['id']}'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          widget.client.tr(
            '使用 Hermes 原生授权流程。仅支持终端的服务会显示原生说明。',
            'Uses the native Hermes authorization flow. Terminal-only services show their original instructions.',
          ),
        ),
        const SizedBox(height: 18),
        if (authorized)
          Text(widget.client.tr('已授权', 'Authorized'))
        else if (widget.provider['flow'] == 'device_code')
          FilledButton(
            onPressed: busy || session?['status'] == 'pending'
                ? null
                : () => action('start'),
            child: Text(widget.client.tr('开始授权', 'Start authorization')),
          )
        else
          SelectableText('${widget.provider['cli_command'] ?? ''}'),
        if (widget.provider['docs_url'] is String)
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse(widget.provider['docs_url'] as String),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(widget.client.tr('原生授权说明', 'Authorization guide')),
          ),
        if (session != null && !authorized) ...[
          const SizedBox(height: 18),
          SelectableText(
            '${session!['user_code'] ?? ''}\n${session!['error_message'] ?? session!['message'] ?? session!['status'] ?? ''}',
          ),
          if (session!['verification_url'] is String)
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(session!['verification_url'] as String),
                mode: LaunchMode.externalApplication,
              ),
              child: Text(
                widget.client.tr('打开授权页面', 'Open authorization page'),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            children: [
              TextButton(
                onPressed: busy || session?['session_id'] == null
                    ? null
                    : () => action('poll'),
                child: Text(widget.client.tr('检查状态', 'Check status')),
              ),
              if (session?['status'] == 'pending')
                TextButton(
                  onPressed: busy ? null : () => action('cancel'),
                  child: Text(widget.client.tr('取消授权', 'Cancel authorization')),
                ),
            ],
          ),
        ],
        if (widget.provider['disconnectable'] == true && authorized)
          TextButton(
            onPressed: busy ? null : () => action('disconnect'),
            child: Text(widget.client.tr('断开授权', 'Disconnect authorization')),
          ),
        ErrorNotice(error),
      ],
    ),
  );
}

class PasswordPage extends StatefulWidget {
  final NekodotClient client;
  const PasswordPage({super.key, required this.client});
  @override
  State<PasswordPage> createState() => _PasswordPageState();
}

class _PasswordPageState extends State<PasswordPage> {
  final old = TextEditingController(), next = TextEditingController();
  String error = '';
  @override
  void dispose() {
    old.dispose();
    next.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.client.tr('修改密码', 'Change password'))),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          controller: old,
          obscureText: true,
          decoration: InputDecoration(
            labelText: widget.client.tr('当前密码', 'Current password'),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: next,
          obscureText: true,
          decoration: InputDecoration(
            labelText: widget.client.tr('新密码', 'New password'),
          ),
        ),
        ErrorNotice(error),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            try {
              await widget.client.request(
                '/auth/password/change',
                method: 'POST',
                body: {'currentPassword': old.text, 'password': next.text},
              );
              await widget.client.clearSession();
              if (context.mounted) {
                Navigator.popUntil(context, (route) => route.isFirst);
              }
            } catch (e) {
              if (mounted) setState(() => error = '$e');
            }
          },
          child: Text(widget.client.tr('修改并重新登录', 'Change & sign in again')),
        ),
      ],
    ),
  );
}
