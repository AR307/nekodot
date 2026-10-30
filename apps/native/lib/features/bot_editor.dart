import 'package:flutter/material.dart';

import '../data/client.dart';
import '../ui/design.dart';

class BotEditor extends StatefulWidget {
  final NekodotClient client;
  final bool group;
  final Json? existing;
  const BotEditor({
    super.key,
    required this.client,
    this.group = false,
    this.existing,
  });
  @override
  State<BotEditor> createState() => _BotEditorState();
}

class _BotEditorState extends State<BotEditor> {
  final name = TextEditingController(),
      handle = TextEditingController(),
      role = TextEditingController(),
      model = TextEditingController(),
      contextLength = TextEditingController();
  String color = avatarColors.first, mode = 'manual', error = '';
  String? lead, source;
  final members = <String>{};
  List<Json> sources = [];
  List<String> models = [];
  bool busy = false, permissionsReady = true;
  NekodotClient get c => widget.client;
  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    if (b != null) {
      name.text = '${b[widget.group ? 'name' : 'displayName']}';
      if (widget.group) {
        members.addAll((b['botIds'] as List).cast<String>());
        lead = b['leadBotId'] as String;
      } else {
        handle.text = '${b['handle']}';
        role.text = '${b['role']}';
        model.text = '${b['model']}';
        color = '${b['avatar']['color']}';
        source = b['sourceId'] as String?;
        contextLength.text = '${b['modelSettings']?['contextLength'] ?? ''}';
        permissionsReady = false;
        loadPermissions();
      }
    }
    if (!widget.group) loadSources();
  }

  Future<void> loadPermissions() async {
    try {
      final result = await c.rpc('bots.permissions.get', {
        'botId': widget.existing!['botId'],
      });
      if (mounted) {
        setState(() {
          mode = result['mode'] as String;
          permissionsReady = true;
          error = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> loadSources() async {
    try {
      final values = objects((await c.rpc('providers.list'))['sources'])
          .where((source) => source['ready'] == true)
          .toList();
      if (!mounted) return;
      setState(() {
        sources = values;
        source ??= values.firstOrNull?['sourceId'] as String?;
      });
      if (source != null) await loadModels();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> loadModels() async {
    final selected = source;
    if (selected == null) return;
    setState(() {
      models = [];
      error = '';
    });
    try {
      final values = await c.rpc('models.options', {'sourceId': selected});
      if (mounted && selected == source) {
        setState(() => models = (values['models'] as List).cast<String>());
      }
    } catch (e) {
      if (mounted && selected == source) setState(() => error = '$e');
    }
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final existing = widget.existing;
      if (widget.group) {
        await c.rpc(existing == null ? 'groups.create' : 'groups.update', {
          if (existing != null) 'groupId': existing['groupId'],
          'name': name.text,
          'botIds': members.toList(),
          'leadBotId': lead,
        });
      } else {
        await c.rpc(existing == null ? 'bots.create' : 'bots.update', {
          if (existing != null) 'botId': existing['botId'],
          'displayName': name.text,
          'handle': handle.text,
          'role': role.text,
          'model': model.text.trim(),
          'avatar': {'shape': 'dot', 'color': color},
          'approvalMode': mode,
          if (source != null) 'sourceId': source,
          'modelSettings': {
            'contextLength': contextLength.text.trim().isEmpty
                ? null
                : int.parse(contextLength.text),
          },
        });
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    name.dispose();
    handle.dispose();
    role.dispose();
    model.dispose();
    contextLength.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.group
            ? c.tr('群组', 'Group')
            : widget.existing == null
            ? c.tr('新建 Bot', 'New Bot')
            : c.tr('编辑 Bot', 'Edit Bot'),
      ),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (!widget.group) ...[
              Center(child: CatAvatar(color: color, size: 70)),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: avatarColors
                    .map(
                      (value) => IconButton(
                        onPressed: () => setState(() => color = value),
                        icon: Icon(
                          value == color ? Icons.check_circle : Icons.circle,
                          color: hexColor(value),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 18),
            ],
            TextField(
              controller: name,
              decoration: InputDecoration(labelText: c.tr('名称', 'Name')),
            ),
            const SizedBox(height: 16),
            if (widget.group) ...[
              Text(
                c.tr('选择 2–6 位成员', 'Choose 2–6 members'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final bot in c.node.bots.where((b) => b['archived'] != true))
                CheckboxListTile(
                  secondary: CatAvatar(color: '${bot['avatar']['color']}'),
                  title: Text('${bot['displayName']}'),
                  subtitle: Text('@${bot['handle']}'),
                  value: members.contains(bot['botId']),
                  onChanged: (value) => setState(() {
                    if (value == true) {
                      members.add(bot['botId'] as String);
                      lead ??= bot['botId'] as String;
                    } else {
                      members.remove(bot['botId']);
                      if (lead == bot['botId']) lead = members.firstOrNull;
                    }
                  }),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(lead),
                initialValue: lead,
                decoration: InputDecoration(
                  labelText: c.tr('主答 Bot', 'Lead Bot'),
                ),
                items: c.node.bots
                    .where((b) => members.contains(b['botId']))
                    .map(
                      (b) => DropdownMenuItem(
                        value: b['botId'] as String,
                        child: Text('${b['displayName']}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => lead = value),
              ),
            ] else ...[
              TextField(
                controller: handle,
                decoration: const InputDecoration(
                  labelText: '@handle',
                  helperText: 'a–z, 0–9, -',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: role,
                minLines: 3,
                maxLines: 8,
                decoration: InputDecoration(labelText: c.tr('角色设定', 'Role')),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey(source),
                initialValue: source,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: c.tr('模型来源', 'Model source'),
                ),
                items: sources
                    .map(
                      (s) => DropdownMenuItem(
                        value: s['sourceId'] as String,
                        child: Text(
                          '${s['name']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    source = value;
                    model.clear();
                  });
                  loadModels();
                },
              ),
              const SizedBox(height: 16),
              Autocomplete<String>(
                key: ValueKey(source),
                initialValue: model.value,
                optionsBuilder: (value) => models.where(
                  (m) => m.toLowerCase().contains(value.text.toLowerCase()),
                ),
                onSelected: (value) => model.text = value,
                fieldViewBuilder: (context, controller, focus, submit) =>
                    TextField(
                      controller: controller,
                      focusNode: focus,
                      onChanged: (value) => model.text = value,
                      decoration: InputDecoration(
                        labelText: c.tr(
                          '选择模型或填写代号',
                          'Choose model or enter its ID',
                        ),
                      ),
                    ),
              ),
              const SizedBox(height: 16),
              ExpansionTile(
                title: Text(c.tr('模型高级设置', 'Advanced model settings')),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextField(
                      controller: contextLength,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: c.tr(
                          '上下文覆盖值（可选）',
                          'Context override (optional)',
                        ),
                        hintText: c.tr(
                          '由 Hermes 自动识别',
                          'Hermes automatic detection',
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      c.tr(
                        '仅填写已确认的上下文容量，留空恢复自动。当前 Hermes 不支持通用最大输出覆盖；未知容量不会显示为实测值。',
                        'Enter only a confirmed context size; leave blank for automatic. This Hermes version has no generic output override. Unknown limits are not shown as measured values.',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey('approval-$mode-$permissionsReady'),
                initialValue: mode,
                decoration: InputDecoration(
                  labelText: c.tr('Hermes 审批等级', 'Hermes approval mode'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'manual',
                    child: Text(c.tr('每次询问', 'Ask each time')),
                  ),
                  DropdownMenuItem(
                    value: 'smart',
                    child: Text(c.tr('原生智能审批', 'Native smart approval')),
                  ),
                  DropdownMenuItem(
                    value: 'off',
                    child: Text(c.tr('全部允许', 'Allow all')),
                  ),
                ],
                onChanged: permissionsReady
                    ? (value) => setState(() => mode = value!)
                    : null,
              ),
              if (!permissionsReady)
                TextButton.icon(
                  onPressed: loadPermissions,
                  icon: const Icon(Icons.refresh),
                  label: Text(c.tr('重新读取审批设置', 'Reload approval settings')),
                ),
            ],
            ErrorNotice(error),
            const SizedBox(height: 20),
            FilledButton(
              onPressed:
                  busy ||
                      !permissionsReady ||
                      !c.online ||
                      (!widget.group &&
                          widget.existing == null &&
                          source == null) ||
                      (widget.group &&
                          (members.length < 2 || members.length > 6))
                  ? null
                  : save,
              child: Text(busy ? c.tr('保存中…', 'Saving…') : c.tr('保存', 'Save')),
            ),
            if (widget.existing != null)
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        try {
                          await c.rpc(
                            widget.group ? 'groups.archive' : 'bots.archive',
                            {
                              widget.group ? 'groupId' : 'botId':
                                  widget.existing![widget.group
                                      ? 'groupId'
                                      : 'botId'],
                            },
                          );
                          if (context.mounted) Navigator.pop(context);
                        } catch (e) {
                          if (mounted) setState(() => error = '$e');
                        }
                      },
                child: Text(c.tr('归档（保留历史）', 'Archive (keep history)')),
              ),
          ],
        ),
      ),
    ),
  );
}
