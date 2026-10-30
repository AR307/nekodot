import 'dart:math' as math;

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
  // A new Bot starts as a random face, so a team looks varied by default.
  String color = avatarColors[math.Random().nextInt(avatarColors.length)],
      shape = avatarShapes[math.Random().nextInt(avatarShapes.length)],
      mode = 'manual',
      error = '';
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
        shape = '${b['avatar']['shape']}';
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
          'avatar': {'shape': shape, 'color': color},
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
  Widget build(BuildContext context) {
    final tone = context.tone;
    const gap = SizedBox(height: 10);
    return AppPage(
      title: widget.group
          ? c.tr('群组', 'Group')
          : widget.existing == null
          ? c.tr('新建 Bot', 'New Bot')
          : c.tr('编辑 Bot', 'Edit Bot'),
      body: PageList(
        children: [
          if (!widget.group) ...[
            Center(
              child: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutBack,
                  ),
                  child: child,
                ),
                child: CatAvatar(
                  key: ValueKey('$shape$color'),
                  color: color,
                  shape: shape,
                  size: tone.glass ? 72 : 56,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 3,
                runSpacing: 3,
                children: [
                  for (final value in avatarShapes)
                    Tooltip(
                      message: switch (value) {
                        'dot' => c.tr('猫', 'Cat'),
                        'bear' => c.tr('熊', 'Bear'),
                        'bunny' => c.tr('兔', 'Bunny'),
                        'puppy' => c.tr('狗', 'Puppy'),
                        'mochi' => c.tr('团子', 'Mochi'),
                        'flower' => c.tr('花', 'Flower'),
                        'ghost' => c.tr('幽灵', 'Ghost'),
                        _ => c.tr('机器人', 'Robot'),
                      },
                      child: InkResponse(
                        radius: 24,
                        onTap: () => setState(() => shape = value),
                        child: Semantics(
                          button: true,
                          selected: value == shape,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: tone.glass ? 40 : 32,
                            height: tone.glass ? 40 : 32,
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: value == shape
                                    ? tone.ink
                                    : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: CatAvatar(color: color, shape: value),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: SizedBox(
                width: (tone.glass ? 34.0 : 26.0) * 8,
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final value in avatarColors)
                      GestureDetector(
                        onTap: () => setState(() => color = value),
                        child: Semantics(
                          button: true,
                          selected: value == color,
                          label: value,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: tone.glass ? 30 : 22,
                            height: tone.glass ? 30 : 22,
                            padding: const EdgeInsets.all(2.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: value == color
                                    ? tone.ink
                                    : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: hexColor(value),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          LabeledField(
            label: c.tr('名称', 'Name'),
            child: TextField(controller: name, decoration: InputDecoration()),
          ),
          gap,
          if (widget.group) ...[
            SectionLabel(
              c.tr('成员', 'Members'),
              trailing: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChainDots(count: members.length, max: 6),
              ),
            ),
            PanelGroup(
              children: [
                for (final bot in c.node.bots.where(
                  (b) => b['archived'] != true,
                ))
                  CheckboxListTile(
                    secondary: CatAvatar.of(bot),
                    title: Text('${bot['displayName']}'),
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
              ],
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: c.tr('主答', 'Lead'),
              child: DropdownButtonFormField<String>(
                key: ValueKey(lead),
                initialValue: lead,
                borderRadius: BorderRadius.circular(20),
                decoration: InputDecoration(),
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
            ),
          ] else ...[
            LabeledField(
              label: '@handle',
              child: TextField(
                controller: handle,
                decoration: const InputDecoration(),
              ),
            ),
            gap,
            LabeledField(
              label: c.tr('角色设定', 'Role'),
              child: TextField(
                controller: role,
                minLines: 3,
                maxLines: 8,
                decoration: InputDecoration(),
              ),
            ),
            gap,
            LabeledField(
              label: c.tr('模型来源', 'Model source'),
              child: DropdownButtonFormField<String>(
                key: ValueKey(source),
                initialValue: source,
                isExpanded: true,
                borderRadius: BorderRadius.circular(20),
                decoration: InputDecoration(),
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
            ),
            gap,
            Autocomplete<String>(
              key: ValueKey(source),
              initialValue: model.value,
              optionsBuilder: (value) => models.where(
                (m) => m.toLowerCase().contains(value.text.toLowerCase()),
              ),
              onSelected: (value) => model.text = value,
              fieldViewBuilder: (context, controller, focus, submit) =>
                  LabeledField(
                    label: c.tr('模型', 'Model'),
                    child: TextField(
                      controller: controller,
                      focusNode: focus,
                      onChanged: (value) => model.text = value,
                      decoration: InputDecoration(),
                    ),
                  ),
            ),
            gap,
            LabeledField(
              label: c.tr('审批', 'Approval'),
              child: DropdownButtonFormField<String>(
                key: ValueKey('approval-$mode-$permissionsReady'),
                initialValue: mode,
                borderRadius: BorderRadius.circular(20),
                decoration: InputDecoration(),
                items: [
                  DropdownMenuItem(
                    value: 'manual',
                    child: Text(c.tr('每次询问', 'Ask each time')),
                  ),
                  DropdownMenuItem(
                    value: 'smart',
                    child: Text(c.tr('智能审批', 'Smart approval')),
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
            ),
            if (!permissionsReady)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: c.tr('重新读取审批设置', 'Reload approval settings'),
                  onPressed: loadPermissions,
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 6),
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text(
                c.tr('高级', 'Advanced'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              children: [
                LabeledField(
                  label: c.tr('上下文覆盖', 'Context override'),
                  child: TextField(
                    controller: contextLength,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(),
                  ),
                ),
              ],
            ),
          ],
          ErrorNotice(error),
          const SizedBox(height: 16),
          Row(
            children: [
              if (widget.existing != null)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: tone.danger),
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
                  child: Text(c.tr('归档', 'Archive')),
                ),
              const Spacer(),
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
                child: busy
                    ? const Breathing(size: 8)
                    : Text(c.tr('保存', 'Save')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
