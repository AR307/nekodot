import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/client.dart';
import '../ui/design.dart';

class SettingsPage extends StatelessWidget {
  final NekodotClient client;
  const SettingsPage({super.key, required this.client});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: client,
    builder: (context, child) => AppPage(
      title: client.tr('设置', 'Settings'),
      body: PageList(
        children: [
          PanelGroup(
            children: [
              ListTile(
                title: Text(client.tr('模型来源', 'Model sources')),
                onTap: () => pushPage(context, SourcesPage(client: client)),
              ),
              ListTile(
                title: Text(client.tr('通知', 'Notifications')),
                subtitle: client.notificationError.isEmpty
                    ? null
                    : Text(client.notificationError),
                trailing: StatusDot(
                  on:
                      client.notificationError.isEmpty &&
                      client.notificationStatus.isNotEmpty,
                ),
                onTap: () async {
                  final opened = await FlutterLocalNotificationsPlugin()
                      .openAppNotificationSettings();
                  if (opened != true && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          client.tr(
                            '请在系统设置中开启通知',
                            'Allow notifications in system settings',
                          ),
                        ),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          PanelGroup(
            children: [
              ListTile(
                title: Text(client.tr('语言', 'Language')),
                trailing: Segment<String>(
                  value: client.language,
                  options: const {'zh': Text('中'), 'en': Text('EN')},
                  onChanged: (value) => client.preferences(locale: value),
                ),
              ),
              ListTile(
                title: Text(client.tr('外观', 'Appearance')),
                trailing: Segment<String>(
                  value: client.theme,
                  options: {
                    'system': Tooltip(
                      message: client.tr('跟随系统', 'System'),
                      child: const Icon(Icons.brightness_auto_outlined),
                    ),
                    'light': Tooltip(
                      message: client.tr('浅色', 'Light'),
                      child: const Icon(Icons.light_mode_outlined),
                    ),
                    'dark': Tooltip(
                      message: client.tr('深色', 'Dark'),
                      child: const Icon(Icons.dark_mode_outlined),
                    ),
                  },
                  onChanged: (value) => client.preferences(appearance: value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          PanelGroup(
            children: [
              ListTile(title: Text('${client.me?['user']['email'] ?? ''}')),
              ListTile(
                title: Text(client.tr('修改密码', 'Change password')),
                onTap: () => pushPage(context, PasswordPage(client: client)),
              ),
              if (context.tone.glass)
                ListTile(
                  title: Text(client.tr('退出账号', 'Sign out')),
                  onTap: () async {
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
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'nekodot 0.2.0',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
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
  Widget build(BuildContext context) => AppPage(
    title: widget.client.tr('模型来源', 'Model sources'),
    body: AsyncPane(
      key: ValueKey(revision),
      load: () => widget.client.rpc('providers.list'),
      builder: (context, data, reload) {
        final custom = objects(data['sources'])
            .where((s) => s['kind'] == 'custom')
            .toList();
        return PageList(
          children: [
            SectionLabel(widget.client.tr('授权登录', 'Authorized services')),
            PanelGroup(
              children: [
                for (final provider in objects(data['oauth']))
                  ListTile(
                    title: Text('${provider['name'] ?? provider['id']}'),
                    trailing: StatusDot(
                      on: (provider['status'] as Map?)?['logged_in'] == true,
                    ),
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
              ],
            ),
            SectionLabel(
              widget.client.tr('自定义 API', 'Custom APIs'),
              trailing: IconButton(
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
            ),
            if (custom.isNotEmpty)
              PanelGroup(
                children: [
                  for (final source in custom)
                    ListTile(
                      title: Text('${source['name']}'),
                      subtitle: Text(
                        '${source['baseUrl']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () async {
                        await pushPage(
                          context,
                          CustomSourcePage(
                            client: widget.client,
                            source: source,
                          ),
                        );
                        reload();
                      },
                    ),
                ],
              ),
          ],
        );
      },
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
  Widget build(BuildContext context) => AppPage(
    title: widget.client.tr('自定义 API', 'Custom API'),
    body: PageList(
      children: [
        LabeledField(
          label: widget.client.tr('名称', 'Name'),
          child: TextField(controller: name, decoration: InputDecoration()),
        ),
        const SizedBox(height: 10),
        LabeledField(
          label: 'API URL',
          child: TextField(
            controller: url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(),
          ),
        ),
        const SizedBox(height: 10),
        LabeledField(
          label: 'API KEY',
          child: TextField(
            controller: key,
            obscureText: true,
            decoration: InputDecoration(
              hintText: savedId == null
                  ? null
                  : '••••${widget.source?['apiKeyLast4'] ?? ''}',
              floatingLabelBehavior: savedId == null
                  ? null
                  : FloatingLabelBehavior.always,
            ),
          ),
        ),
        ErrorNotice(error),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
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
                                '${(catalog['models'] as List).length} 个模型',
                                '${(catalog['models'] as List).length} models',
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
            child: Text(widget.client.tr('保存', 'Save')),
          ),
        ),
      ],
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
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final docs = widget.provider['docs_url'];
    return AppPage(
      title: '${widget.provider['name'] ?? widget.provider['id']}',
      actions: [
        if (docs is String)
          IconButton(
            tooltip: widget.client.tr('授权说明', 'Authorization guide'),
            onPressed: () => launchUrl(
              Uri.parse(docs),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new),
          ),
      ],
      body: PageList(
        children: [
          if (authorized)
            Row(
              children: [
                const StatusDot(),
                const SizedBox(width: 10),
                Text(
                  widget.client.tr('已授权', 'Authorized'),
                  style: text.titleMedium,
                ),
              ],
            )
          else if (widget.provider['flow'] == 'device_code')
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: busy || session?['status'] == 'pending'
                    ? null
                    : () => action('start'),
                child: Text(widget.client.tr('开始授权', 'Start authorization')),
              ),
            )
          else
            Panel(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: SelectableText(
                  '${widget.provider['cli_command'] ?? ''}',
                  style: const TextStyle(fontFamily: monoFont, fontSize: 13),
                ),
              ),
            ),
          if (session != null && !authorized) ...[
            const SizedBox(height: 18),
            SelectableText(
              '${session!['user_code'] ?? ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: monoFont,
                fontSize: 28,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              '${session!['error_message'] ?? session!['message'] ?? session!['status'] ?? ''}',
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                if (session!['verification_url'] is String)
                  IconButton(
                    tooltip: widget.client.tr(
                      '打开授权页面',
                      'Open authorization page',
                    ),
                    onPressed: () => launchUrl(
                      Uri.parse(session!['verification_url'] as String),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_browser),
                  ),
                IconButton(
                  tooltip: widget.client.tr('检查状态', 'Check status'),
                  onPressed: busy || session?['session_id'] == null
                      ? null
                      : () => action('poll'),
                  icon: const Icon(Icons.refresh),
                ),
                if (session?['status'] == 'pending')
                  IconButton(
                    tooltip: widget.client.tr('取消', 'Cancel'),
                    onPressed: busy ? null : () => action('cancel'),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
          ],
          if (widget.provider['disconnectable'] == true && authorized) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: busy ? null : () => action('disconnect'),
                child: Text(widget.client.tr('断开', 'Disconnect')),
              ),
            ),
          ],
          ErrorNotice(error),
        ],
      ),
    );
  }
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
  Widget build(BuildContext context) => AppPage(
    title: widget.client.tr('修改密码', 'Change password'),
    body: PageList(
      children: [
        LabeledField(
          label: widget.client.tr('当前密码', 'Current password'),
          child: TextField(
            controller: old,
            obscureText: true,
            decoration: InputDecoration(),
          ),
        ),
        const SizedBox(height: 10),
        LabeledField(
          label: widget.client.tr('新密码', 'New password'),
          child: TextField(
            controller: next,
            obscureText: true,
            decoration: InputDecoration(),
          ),
        ),
        ErrorNotice(error),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
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
            child: Text(widget.client.tr('修改', 'Change')),
          ),
        ),
      ],
    ),
  );
}
