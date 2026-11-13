import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../local/runtime.dart';
import '../platform/desktop.dart';
import 'plugin_center.dart';
import 'hermes_settings.dart';
import 'local_setup.dart';
import '../ui/design.dart';
import 'updates.dart';
import 'user_memory.dart';
import 'statistics.dart';
import 'source_models.dart';

/// The parts of settings in order: id, title and icon. The page and the list
/// that leads to its parts both read them here.
List<(String, String, IconData)> settingsParts(NekodotClient c) => [
  ('account', c.tr('账户', 'Account'), Symbols.person),
  ('bots', c.tr('所有 Bot', 'All Bots'), Symbols.smart_toy),
  if (localRuntime?.location != null && localRuntime?.userId != null)
    ('computer', c.tr('这台电脑', 'This computer'), Symbols.computer),
  ('app', c.tr('应用', 'App'), Symbols.tune),
];

class SettingsPage extends StatefulWidget {
  final NekodotClient client;
  final String? sectionId;
  const SettingsPage({super.key, required this.client, this.sectionId});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

/// One titled run of settings, which the side list on a wide page jumps to.
typedef _Section = ({
  String id,
  String title,
  IconData icon,
  List<Widget> children,
});

class _SettingsPageState extends State<SettingsPage> {
  NekodotClient get client => widget.client;
  final anchors = <String, GlobalKey>{};
  String? current;

  Future<void> signOut(BuildContext context) async {
    try {
      await localRuntime?.stop();
      await client.logout();
      if (context.mounted) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (context.mounted) showNotice(context, '$e');
    }
  }

  GlobalKey anchor(String id) => anchors.putIfAbsent(id, GlobalKey.new);

  void jump(String id) {
    setState(() => current = id);
    final target = anchors[id]?.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  /// The section whose title has passed the top of the list is the one shown.
  bool follow(ScrollNotification note, List<_Section> sections) {
    if (note.depth != 0) return false;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return false;
    var shown = sections.first.id;
    for (final section in sections) {
      final target = anchors[section.id]?.currentContext?.findRenderObject();
      if (target is! RenderBox || !target.attached) continue;
      final top = target.localToGlobal(Offset.zero, ancestor: box).dy;
      if (top <= 120) shown = section.id;
    }
    if (note.metrics.extentAfter < 1) shown = sections.last.id;
    if (shown != current) setState(() => current = shown);
    return false;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: client,
    builder: (context, child) {
      final c = client;
      final tone = context.tone;
      final email = '${c.account.me?['user']['email'] ?? ''}';
      final name = email.split('@').first;
      Widget link(String key, String title, Widget page) => ListTile(
        key: ValueKey(key),
        title: Text(title),
        trailing: const Icon(Symbols.chevron_right),
        onTap: () => pushPage(context, page),
      );
      final parts = {
        for (final (id, title, icon) in settingsParts(c)) id: (title, icon),
      };
      final sections = <_Section>[
        (
          id: 'account',
          title: parts['account']!.$1,
          icon: parts['account']!.$2,
          children: [
            PanelGroup(
              children: [
                ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tone.ink,
                    ),
                    child: Text(
                      name.isEmpty ? '' : name.characters.first.toUpperCase(),
                      style: TextStyle(
                        color: tone.base,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(name),
                  subtitle: Text(email),
                ),
                ListTile(
                  title: Text(c.tr('修改密码', 'Change password')),
                  trailing: const Icon(Symbols.chevron_right),
                  onTap: () => pushPage(context, PasswordPage(client: c)),
                ),
                link(
                  'settings-statistics',
                  c.tr('统计', 'Statistics'),
                  StatisticsPage(client: c),
                ),
                ListTile(
                  title: Text(c.tr('退出账号', 'Sign out')),
                  onTap: () => signOut(context),
                ),
              ],
            ),
          ],
        ),
        (
          id: 'bots',
          title: parts['bots']!.$1,
          icon: parts['bots']!.$2,
          children: [
            PanelGroup(
              children: [
                link(
                  'settings-sources',
                  c.tr('模型来源', 'Model sources'),
                  SourcesPage(client: c),
                ),
                link(
                  'settings-user-memory',
                  c.tr('关于你', 'About you'),
                  SharedUserMemoryPage(client: c),
                ),
                link(
                  'settings-extensions',
                  c.tr('插件中心', 'Plugin center'),
                  PluginCenterPage(client: c, kind: 'skills'),
                ),
                if (c.online)
                  link(
                    'settings-shared-hermes',
                    c.tr('共用 Hermes 设置', 'Shared Hermes settings'),
                    AppPage(
                      title: c.tr('共用 Hermes 设置', 'Shared Hermes settings'),
                      body: MasterDetail(master: HermesSettings(client: c)),
                    ),
                  ),
              ],
            ),
          ],
        ),
        if (parts.containsKey('computer'))
          (
            id: 'computer',
            title: parts['computer']!.$1,
            icon: parts['computer']!.$2,
            children: [LocalComputerPanel(client: c)],
          ),
        (
          id: 'app',
          title: parts['app']!.$1,
          icon: parts['app']!.$2,
          children: [
            PanelGroup(
              children: [
                ListTile(
                  title: Text(c.tr('语言', 'Language')),
                  trailing: Segment<String>(
                    value: c.prefs.language,
                    options: const {'zh': Text('中'), 'en': Text('EN')},
                    onChanged: (value) => c.prefs.update(locale: value),
                  ),
                ),
                ListTile(
                  title: Text(c.tr('外观', 'Appearance')),
                  trailing: Segment<String>(
                    value: c.prefs.theme,
                    options: {
                      'system': Tooltip(
                        message: c.tr('跟随系统', 'System'),
                        child: const Icon(Symbols.brightness_auto),
                      ),
                      'light': Tooltip(
                        message: c.tr('浅色', 'Light'),
                        child: const Icon(Symbols.light_mode),
                      ),
                      'dark': Tooltip(
                        message: c.tr('深色', 'Dark'),
                        child: const Icon(Symbols.dark_mode),
                      ),
                    },
                    onChanged: (value) => c.prefs.update(appearance: value),
                  ),
                ),
                ListTile(
                  title: Text(c.tr('通知', 'Notifications')),
                  subtitle: c.notificationError.isEmpty
                      ? null
                      : Text(c.notificationError),
                  trailing: StatusDot(
                    on:
                        c.notificationError.isEmpty &&
                        c.notificationStatus.isNotEmpty,
                  ),
                  onTap: () async {
                    final opened = await FlutterLocalNotificationsPlugin()
                        .openAppNotificationSettings();
                    if (opened != true && context.mounted) {
                      showNotice(
                        context,
                        c.tr(
                          '请在系统设置中开启通知',
                          'Allow notifications in system settings',
                        ),
                      );
                    }
                  },
                ),
                link(
                  'settings-updates',
                  c.tr('版本与更新', 'Versions & updates'),
                  UpdatesPage(client: c),
                ),
              ],
            ),
            if (DesktopHost.supported) ...[
              const SizedBox(height: 14),
              PanelGroup(
                children: [
                  ListTile(
                    key: const ValueKey('quit-application'),
                    title: Text(c.tr('退出应用', 'Quit application')),
                    subtitle: Text(
                      localRuntime?.running == true
                          ? c.tr(
                              '这台电脑上的 Bot 会停止，服务器任务继续运行',
                              'Bots on this computer stop; server tasks keep running',
                            )
                          : c.tr('服务器任务继续运行', 'Server tasks keep running'),
                    ),
                    onTap: DesktopHost.quit,
                  ),
                ],
              ),
            ],
          ],
        ),
      ];
      if (widget.sectionId != null) {
        final section = sections.firstWhere((s) => s.id == widget.sectionId);
        return AppPage(
          title: section.title,
          body: PageList(children: section.children),
        );
      }
      // Every section stays in one list; a wide page adds a side list that
      // jumps to them and shows where you are.
      return LayoutBuilder(
        builder: (context, box) {
          final wide = !tone.glass && box.maxWidth >= 640;
          // Keep the few section anchors mounted, including those below the
          // viewport: a category must work before it has been scrolled into view.
          final list = SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              MediaQuery.paddingOf(context).bottom + 28,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, section) in sections.indexed) ...[
                      if (index > 0 || wide)
                        KeyedSubtree(
                          key: anchor(section.id),
                          child: SectionLabel(section.title),
                        )
                      else
                        SizedBox(key: anchor(section.id)),
                      ...section.children,
                    ],
                  ],
                ),
              ),
            ),
          );
          return AppPage(
            title: c.tr('设置', 'Settings'),
            body: tone.glass
                ? PageList(
                    children: [
                      PanelGroup(
                        children: [
                          for (final section in sections)
                            ListTile(
                              key: ValueKey('settings-category-${section.id}'),
                              leading: Icon(section.icon),
                              title: Text(section.title),
                              trailing: const Icon(Symbols.chevron_right),
                              onTap: () => pushPage(
                                context,
                                SettingsPage(client: c, sectionId: section.id),
                              ),
                            ),
                        ],
                      ),
                    ],
                  )
                : !wide
                ? list
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 200,
                        child: SettingsNav(
                          sections: [
                            for (final section in sections)
                              (section.id, section.title, section.icon),
                          ],
                          current: current ?? sections.first.id,
                          onPick: jump,
                        ),
                      ),
                      Expanded(
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (note) => follow(note, sections),
                          child: list,
                        ),
                      ),
                    ],
                  ),
          );
        },
      );
    },
  );
}

/// The side list of a wide settings page: where each section is, and which
/// one you are reading.
class SettingsNav extends StatelessWidget {
  final List<(String, String, IconData)> sections;
  final String current;
  final ValueChanged<String> onPick;
  final EdgeInsets padding;
  const SettingsNav({
    super.key,
    required this.sections,
    required this.current,
    required this.onPick,
    this.padding = const EdgeInsets.fromLTRB(12, 30, 8, 12),
  });
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final text = Theme.of(context).textTheme;
    final still = MediaQuery.disableAnimationsOf(context);
    return ListView(
      padding: padding,
      children: [
        for (final (id, title, icon) in sections)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: AnimatedContainer(
              duration: still ? Duration.zero : Motion.tint,
              decoration: ShapeDecoration(
                color: id == current ? tone.hover : Colors.transparent,
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(Tone.r8),
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: ValueKey('settings-nav-$id'),
                  customBorder: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onTap: () => onPick(id),
                  child: SizedBox(
                    height: 38,
                    child: Row(
                      children: [
                        const SizedBox(width: 10),
                        Icon(
                          icon,
                          size: 18,
                          color: id == current ? tone.ink : tone.ink2,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium?.copyWith(
                              fontSize: 14,
                              fontWeight: id == current
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: id == current ? tone.ink : tone.ink2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
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
    body: MasterDetail(
      master: AsyncPane(
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
                      selected: MasterDetail.shows(
                        context,
                        'service:${provider['id'] ?? provider['provider']}',
                      ),
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
                          row:
                              'service:${provider['id'] ?? provider['provider']}',
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
                  icon: const Icon(Symbols.add),
                ),
              ),
              if (custom.isNotEmpty)
                PanelGroup(
                  children: [
                    for (final source in custom)
                      ListTile(
                        selected: MasterDetail.shows(
                          context,
                          'source:${source['sourceId']}',
                        ),
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
                            row: 'source:${source['sourceId']}',
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
  late String apiMode = widget.source?['apiMode'] as String? ?? '';
  int modelRevision = 0;
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
        LabeledField(
          label: widget.client.tr('接口', 'API'),
          child: MenuSelect<String>(
            value: apiMode,
            options: [
              ('', widget.client.tr('自动', 'Automatic')),
              ('chat_completions', 'Chat Completions'),
              ('codex_responses', 'Responses'),
              ('anthropic_messages', 'Messages'),
            ],
            onChanged: busy ? null : (v) => setState(() => apiMode = v),
          ),
        ),
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
                        'apiMode': apiMode,
                        if (key.text.isNotEmpty) 'apiKey': key.text,
                      });
                      if (mounted) {
                        setState(() {
                          savedId = saved['sourceId'] as String;
                          modelRevision++;
                        });
                      }
                      key.clear();
                    } catch (e) {
                      if (mounted) setState(() => error = '$e');
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: Text(widget.client.tr('保存', 'Save')),
          ),
        ),
        if (savedId != null)
          SourceModels(
            key: ValueKey('$savedId:$modelRevision'),
            client: widget.client,
            sourceId: savedId!,
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
            icon: const Icon(Symbols.open_in_new),
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
                    icon: const Icon(Symbols.open_in_browser),
                  ),
                IconButton(
                  tooltip: widget.client.tr('检查状态', 'Check status'),
                  onPressed: busy || session?['session_id'] == null
                      ? null
                      : () => action('poll'),
                  icon: const Icon(Symbols.refresh),
                ),
                if (session?['status'] == 'pending')
                  IconButton(
                    tooltip: widget.client.tr('取消', 'Cancel'),
                    onPressed: busy ? null : () => action('cancel'),
                    icon: const Icon(Symbols.close),
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
          if (authorized)
            SourceModels(
              key: ValueKey('oauth:${widget.provider['id']}'),
              client: widget.client,
              sourceId: 'oauth:${widget.provider['id']}',
            ),
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
                await widget.client.account.request(
                  '/auth/password/change',
                  method: 'POST',
                  body: {'currentPassword': old.text, 'password': next.text},
                );
                await widget.client.clearSession();
                if (context.mounted) {
                  Navigator.of(
                    context,
                    rootNavigator: true,
                  ).popUntil((route) => route.isFirst);
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
