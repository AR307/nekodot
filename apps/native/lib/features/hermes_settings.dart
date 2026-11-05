import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/client.dart';
import '../data/hermes_zh.dart';
import '../ui/design.dart';
import 'model_selection.dart';

/// The kinds a Bot's own settings fall into, in page order; Node assigns each
/// Hermes setting its kind. Settings about the installation are app-wide.
const botSettingGroups = [
  'model',
  'tools',
  'memory',
  'security',
  'voice',
  'run',
  'other',
];
const sharedSettingGroups = [
  'services',
  'channels',
  'credentials',
  'network',
  'interface',
  'general',
];

String settingGroupName(NekodotClient c, String group) => switch (group) {
  'model' => c.tr('模型', 'Model'),
  'tools' => c.tr('能力', 'Capabilities'),
  'memory' => c.tr('记忆与学习', 'Memory & learning'),
  'security' => c.tr('安全与隐私', 'Security & privacy'),
  'voice' => c.tr('语音', 'Voice'),
  'run' => c.tr('运行', 'Running'),
  'services' => c.tr('模型服务', 'Model services'),
  'channels' => c.tr('消息平台', 'Messaging platforms'),
  'credentials' => c.tr('凭据管理', 'Credential managers'),
  'network' => c.tr('网络与代理', 'Network & proxy'),
  'interface' => c.tr('Hermes 界面', 'Hermes interface'),
  'general' => c.tr('通用', 'General'),
  _ => c.tr('其他', 'Other'),
};

/// A setting's name and note in the app's language. Hermes writes only the key
/// and an English note; a key newer than [hermesSettingZh] shows as Hermes wrote it.
(String, String) settingText(NekodotClient c, Json field) {
  final key = '${field['key']}';
  return (c.zh ? hermesSettingZh[key] : null) ??
      (key, '${field['description']}');
}

/// Hermes's own settings for one Bot, or with no Bot the ones every Bot on
/// this computer shares. With no [group] it shows the kinds, each with the
/// product's own controls for that kind ([extras]) and a way into the rest.
class HermesSettings extends StatefulWidget {
  final NekodotClient client;
  final String? botId;
  final String? group;
  final Map<String, List<Widget>> extras;
  const HermesSettings({
    super.key,
    required this.client,
    this.botId,
    this.group,
    this.extras = const {},
  });

  @override
  State<HermesSettings> createState() => _HermesSettingsState();
}

class _HermesSettingsState extends State<HermesSettings> {
  final search = TextEditingController();
  String query = '';
  bool advanced = false;
  NekodotClient get c => widget.client;
  bool get shared => widget.botId == null;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<Json> load() => shared
      ? c.rpc('hermes.shared.get')
      : c.rpc('hermes.settings.get', {'botId': widget.botId});

  @override
  Widget build(BuildContext context) => AsyncPane(
    load: load,
    builder: (context, data, reload) {
      final text = Theme.of(context).textTheme;
      String groupOf(Json field) => '${field['group'] ?? 'other'}';
      final fields = objects(data['fields']);
      final all = fields
          .where((f) => widget.group == null || groupOf(f) == widget.group)
          .where(
            (f) => !const ['model', 'model_context_length'].contains(f['key']),
          )
          .where(
            (f) =>
                !RegExp(r'^(auxiliary\.[^.]+|delegation)\.(provider|base_url)$')
                    .hasMatch('${f['key']}') &&
                f['key'] != 'cron.model_provider',
          )
          .where(
            (f) =>
                !((f['type'] == 'string' &&
                        RegExp(r'(^|[._])model(_id)?$')
                            .hasMatch('${f['key']}') &&
                        !_catalogModel('${f['key']}')) ||
                    '${f['key']}'.startsWith('moa.presets.') ||
                    '${f['key']}'.endsWith('fallback_providers')),
          )
          .toList();
      final filtered = all.where((field) {
        final (name, note) = settingText(c, field);
        final words = '${field['key']} ${field['description']} $name $note'
            .toLowerCase();
        return words.contains(query.toLowerCase());
      }).toList();
      final categories = <String>[
        ...strings(data['categories']),
        ...all
            .map((field) => '${field['category']}')
            .where((name) => !strings(data['categories']).contains(name))
            .toSet(),
      ];
      final overview = widget.group == null && query.isEmpty;
      final order = shared ? sharedSettingGroups : botSettingGroups;
      return PageList(
        children: [
          if (!shared && widget.group == null)
            SwitchListTile.adaptive(
              key: const ValueKey('advanced-settings'),
              title: Text(c.tr('高级设置', 'Advanced settings')),
              value: advanced,
              onChanged: (value) => setState(() {
                advanced = value;
                query = '';
                search.clear();
              }),
            ),
          if (shared || widget.group != null || advanced)
            TextField(
              controller: search,
              onChanged: (value) => setState(() => query = value),
              decoration: InputDecoration(
                hintText: c.tr('搜索设置', 'Search settings'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: c.tr('清除搜索', 'Clear search'),
                        onPressed: () {
                          search.clear();
                          setState(() => query = '');
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
          if (overview && shared) ...[
            // Settings for every Bot have no app items beside them: one card
            // of kinds.
            const SizedBox(height: 14),
            PanelGroup(
              children: [
                for (final group in order)
                  if (all.any((field) => groupOf(field) == group))
                    groupRow(
                      context,
                      group,
                      all,
                      categories,
                      title: settingGroupName(c, group),
                    ),
              ],
            ),
          ] else if (overview) ...[
            for (final group in order)
              if ((widget.extras[group] ?? const []).isNotEmpty ||
                  (advanced &&
                      all.any((field) => groupOf(field) == group))) ...[
                SectionLabel(settingGroupName(c, group)),
                PanelGroup(
                  children: [
                    ...?widget.extras[group],
                    if (advanced && all.any((field) => groupOf(field) == group))
                      groupRow(context, group, all, categories),
                  ],
                ),
              ],
          ] else ...[
            for (final category in categories)
              if (filtered.any((field) => field['category'] == category)) ...[
                SectionLabel(_categoryName(c, category)),
                PanelGroup(
                  children: [
                    for (final field in filtered.where(
                      (field) => field['category'] == category,
                    ))
                      fieldTile(field, fields, reload),
                  ],
                ),
              ],
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    c.tr('没有匹配的设置', 'No matching settings'),
                    style: text.bodySmall,
                  ),
                ),
              ),
          ],
        ],
      );
    },
  );

  /// The way into one kind: what it covers, and how many settings it holds.
  Widget groupRow(
    BuildContext context,
    String group,
    List<Json> all,
    List<String> categories, {
    String? title,
  }) {
    final fields = all.where((f) => '${f['group'] ?? 'other'}' == group);
    final names = [
      for (final category in categories)
        if (fields.any((field) => field['category'] == category))
          _categoryName(c, category),
    ];
    return ListTile(
      key: ValueKey('settings-group-$group'),
      title: Text(title ?? c.tr('Hermes 设置', 'Hermes settings')),
      subtitle: Text(
        names.join(c.tr('、', ', ')),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${fields.length}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => pushPage(
        context,
        AppPage(
          title: settingGroupName(c, group),
          body: HermesSettings(client: c, botId: widget.botId, group: group),
        ),
      ),
    );
  }

  /// The translated name leads; Hermes's key stays under it, small, so a
  /// setting can still be matched to Hermes's own documentation.
  Widget fieldTile(Json field, List<Json> fields, VoidCallback reload) {
    final key = '${field['key']}';
    final (name, note) = settingText(c, field);
    Widget subtitle(List<String> lines) => Text.rich(
      TextSpan(
        children: [
          TextSpan(text: lines.join('\n')),
          if (name != key)
            TextSpan(
              text: '\n$key',
              style: TextStyle(fontSize: 11.5, color: context.tone.ink3),
            ),
        ],
      ),
      maxLines: lines.length + 2,
      overflow: TextOverflow.ellipsis,
    );
    return field['type'] == 'boolean' && field['sensitive'] != true
        ? SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            title: Text(name),
            subtitle: subtitle([note]),
            value: field['value'] == true,
            onChanged: field['editable'] == true
                ? (value) => _save(field, value, reload)
                : null,
          )
        : ListTile(
            title: Text(name),
            subtitle: subtitle([
              note,
              _valueLabel(c, field),
              if (field['editable'] != true && field['sensitive'] != true)
                c.tr('修改请前往 Bot 模型设置', 'Change this in Bot model settings'),
            ]),
            trailing: field['sensitive'] == true
                ? const Icon(Icons.lock_outline, size: 18)
                : field['editable'] == true
                ? const Icon(Icons.chevron_right)
                : null,
            onTap: field['editable'] != true
                ? null
                : () => _edit(field, fields, reload),
          );
  }

  Future<void> _save(Json field, Object? value, VoidCallback reload) async {
    try {
      final result = shared
          ? await c.rpc('hermes.shared.set', {
              'key': field['key'],
              'value': value,
            })
          : await c.rpc('hermes.settings.set', {
              'botId': widget.botId,
              'key': field['key'],
              'value': value,
            });
      if (!mounted) return;
      reload();
      showNotice(
        context,
        shared
            ? c.tr(
                '已应用到这台电脑上的 ${result['profiles']} 个 Hermes profile',
                'Applied to ${result['profiles']} Hermes profiles on this computer',
              )
            : c.tr('已保存到 Hermes profile', 'Saved to Hermes profile'),
      );
    } catch (error) {
      if (mounted) showNotice(context, '$error');
    }
  }

  Future<void> _edit(Json field, List<Json> fields, VoidCallback reload) async {
    if (_catalogModel('${field['key']}')) {
      final bot = c.node.bots.firstWhere((b) => b['botId'] == widget.botId);
      final providerKey = field['key'] == 'cron.model'
          ? 'cron.model_provider'
          : '${field['key']}'.replaceFirst(RegExp(r'\.model$'), '.provider');
      final provider = fields
          .where((f) => f['key'] == providerKey)
          .firstOrNull?['value'];
      final sources = objects((await c.rpc('providers.list'))['sources']);
      if (!mounted) return;
      String? source =
          provider == null ||
              provider == '' ||
              provider == 'auto' ||
              provider == 'main'
          ? bot['sourceId'] as String?
          : sources
                    .where((s) => s['provider'] == provider)
                    .firstOrNull?['sourceId']
                as String?;
      var model = '${field['value'] ?? ''}';
      var busy = false;
      var error = '';
      await showDialog<void>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(settingText(c, field).$1),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ModelSelection(
                      client: c,
                      sourceId: source,
                      model: model,
                      enabled: !busy,
                      onChanged: (id, value) => update(() {
                        source = id;
                        model = value;
                      }),
                    ),
                    ErrorNotice(error),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(dialog),
                child: Text(c.tr('取消', 'Cancel')),
              ),
              FilledButton(
                onPressed: busy || source == null || model.isEmpty
                    ? null
                    : () async {
                        update(() => busy = true);
                        try {
                          await c.rpc('models.assign', {
                            'botId': widget.botId,
                            'key': field['key'],
                            'sourceId': source,
                            'model': model,
                          });
                          if (dialog.mounted) Navigator.pop(dialog);
                          reload();
                        } catch (e) {
                          if (dialog.mounted) {
                            update(() {
                              error = '$e';
                              busy = false;
                            });
                          }
                        }
                      },
                child: Text(c.tr('保存', 'Save')),
              ),
            ],
          ),
        ),
      );
      return;
    }
    final type = '${field['type']}';
    final initial = field['value'];
    final controller = TextEditingController(
      text: type == 'list' || type == 'object'
          ? const JsonEncoder.withIndent('  ').convert(initial)
          : initial is String
          ? initial
          : initial == null
          ? ''
          : '$initial',
    );
    final options = (field['options'] as List? ?? const []).toList();
    final selected = <String, Object?>{
      for (final (index, option) in options.indexed) 'option:$index': option,
    };
    if (initial != null && !selected.values.contains(initial)) {
      selected['current'] = initial;
    }
    if (field['clearable'] == true) selected['clear'] = null;
    final initialSelection = selected.entries
        .where((entry) => entry.value == initial)
        .firstOrNull
        ?.key;
    String? selectedKey = initialSelection;
    String? error;
    final result = await showDialog<({Object? value})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: Text(settingText(c, field).$1),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: type == 'select'
                      ? MenuSelect<String>(
                          key: const ValueKey('setting-select'),
                          value: selectedKey,
                          options: [
                            for (final entry in selected.entries)
                              (
                                entry.key,
                                entry.key == 'clear' ? '—' : '${entry.value}',
                              ),
                          ],
                          onChanged: (key) =>
                              updateDialog(() => selectedKey = key),
                        )
                      : TextField(
                          controller: controller,
                          autofocus: true,
                          keyboardType: type == 'number'
                              ? const TextInputType.numberWithOptions(
                                  decimal: true,
                                )
                              : null,
                          minLines: type == 'list' || type == 'object' ? 8 : 1,
                          maxLines: type == 'list' || type == 'object' ? 16 : 3,
                          decoration: InputDecoration(
                            helperText: type == 'list' || type == 'object'
                                ? 'JSON'
                                : settingText(c, field).$2,
                          ),
                        ),
                ),
                if (error != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: TextStyle(color: context.tone.danger),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(c.tr('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final Object? edited = switch (type) {
                    'select' => selected[selectedKey],
                    'number' => num.parse(controller.text.trim()),
                    'list' || 'object' => jsonDecode(controller.text),
                    _ => controller.text,
                  };
                  if (type == 'list' && edited is! List) {
                    throw const FormatException('Expected a JSON array');
                  }
                  if (type == 'object' && (edited is! Map || edited is List)) {
                    throw const FormatException('Expected a JSON object');
                  }
                  Navigator.pop(dialogContext, (value: edited));
                } on FormatException catch (exception) {
                  updateDialog(() => error = exception.message);
                }
              },
              child: Text(c.tr('保存', 'Save')),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result != null) await _save(field, result.value, reload);
  }
}

bool _catalogModel(String key) =>
    RegExp(r'^(auxiliary\.[^.]+|delegation|cron)\.model$').hasMatch(key);

List<String> strings(Object? value) =>
    (value as List? ?? const []).whereType<String>().toList();

String _valueLabel(NekodotClient client, Json field) {
  if (field['sensitive'] == true) {
    return client.tr(
      field['configured'] == true ? '已配置 · 凭据由 Hermes 保管' : '未配置',
      field['configured'] == true
          ? 'Configured · credential held by Hermes'
          : 'Not configured',
    );
  }
  final value = field['value'];
  final display = value is String ? value : jsonEncode(value);
  return display.isEmpty || display == 'null'
      ? client.tr('未设置', 'Not set')
      : display;
}

String _categoryName(NekodotClient client, String category) =>
    switch (category) {
      'general' => client.tr('常规', 'General'),
      'agent' => client.tr('智能体', 'Agent'),
      'terminal' => client.tr('终端', 'Terminal'),
      'display' => client.tr('显示', 'Display'),
      'delegation' => client.tr('委派', 'Delegation'),
      'memory' => client.tr('记忆', 'Memory'),
      'compression' => client.tr('上下文压缩', 'Context compression'),
      'auxiliary' => client.tr('辅助模型', 'Auxiliary models'),
      'security' => client.tr('安全', 'Security'),
      'browser' => client.tr('浏览器', 'Browser'),
      'web' => client.tr('网页', 'Web'),
      'vision' => client.tr('视觉', 'Vision'),
      'tools' => client.tr('工具', 'Tools'),
      'tool_output' => client.tr('工具输出', 'Tool output'),
      'tool_loop_guardrails' => client.tr('工具循环保护', 'Tool loop guardrails'),
      'worktrees' => client.tr('工作树', 'Worktrees'),
      'lsp' => client.tr('代码语言服务', 'Language servers'),
      'x_search' => client.tr('X 搜索', 'X search'),
      'moa' => client.tr('多模型协作', 'Mixture of agents'),
      'loops' => client.tr('循环任务', 'Loops'),
      'streaming' => client.tr('流式输出', 'Streaming'),
      'sessions' => client.tr('会话', 'Sessions'),
      'curator' => client.tr('技能整理', 'Curator'),
      'bot_desktop' => client.tr('Bot 桌面', 'Bot desktop'),
      'voice' => client.tr('语音对话', 'Voice chat'),
      'tts' => client.tr('语音合成', 'Text to speech'),
      'stt' => client.tr('语音识别', 'Speech to text'),
      'wake_word' => client.tr('唤醒词', 'Wake word'),
      'vault' => client.tr('密码库', 'Vault'),
      'secrets' => client.tr('密钥服务', 'Secret services'),
      'proxy' => client.tr('代理', 'Proxy'),
      'openrouter' => 'OpenRouter',
      'bedrock' => 'Bedrock',
      'vertex' => 'Vertex',
      'model_catalog' => client.tr('模型目录', 'Model catalog'),
      'local_runtime' => client.tr('本地模型', 'Local models'),
      'gateway' => client.tr('网关', 'Gateway'),
      'kanban' => client.tr('看板', 'Kanban'),
      'hosted_rooms' => client.tr('托管房间', 'Hosted rooms'),
      'webapp' => client.tr('网页应用', 'Web app'),
      'desktop' => client.tr('桌面应用', 'Desktop app'),
      'monitoring' => client.tr('监控', 'Monitoring'),
      'database' => client.tr('数据库', 'Database'),
      'attachments' => client.tr('附件', 'Attachments'),
      'logging' => client.tr('日志', 'Logging'),
      'discord' => 'Discord',
      'slack' => 'Slack',
      'mattermost' => 'Mattermost',
      'matrix' => 'Matrix',
      _ => category,
    };
