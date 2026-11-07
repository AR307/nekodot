import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../data/account.dart';
import '../ui/design.dart';
import 'files.dart';
import 'model_selection.dart';

class BotEditor extends StatefulWidget {
  final NekodotClient client;
  final bool group;
  final Json? existing;
  final bool importProfile;
  final Json? initialArchive;
  final ValueChanged<Json?>? onCreating;
  const BotEditor({
    super.key,
    required this.client,
    this.group = false,
    this.existing,
    this.importProfile = false,
    this.initialArchive,
    this.onCreating,
  });
  @override
  State<BotEditor> createState() => _BotEditorState();
}

class _BotEditorState extends State<BotEditor> {
  final name = TextEditingController(),
      handle = TextEditingController(),
      model = TextEditingController(),
      contextLength = TextEditingController();
  // A new Bot starts as a random face, so a team looks varied by default.
  String color = avatarColors[math.Random().nextInt(avatarColors.length)],
      shape = avatarShapes[math.Random().nextInt(avatarShapes.length)],
      mode = 'manual',
      error = '';
  String? lead, source;
  Json? archive;
  final members = <String>{};
  bool busy = false, permissionsReady = true;
  bool handleEdited = false;
  NekodotClient get c => widget.client;
  @override
  void initState() {
    super.initState();
    archive = widget.initialArchive;
    final b = widget.existing;
    if (b != null) {
      name.text = '${b[widget.group ? 'name' : 'displayName']}';
      if (widget.group) {
        members.addAll((b['botIds'] as List).cast<String>());
        lead = b['leadBotId'] as String;
      } else {
        handle.text = '${b['handle']}';
        model.text = '${b['model']}';
        color = '${b['avatar']['color']}';
        shape = '${b['avatar']['shape']}';
        source = b['sourceId'] as String?;
        contextLength.text = '${b['modelSettings']?['contextLength'] ?? ''}';
        permissionsReady = false;
        loadPermissions();
      }
    }
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

  Future<void> save() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final existing = widget.existing;
      Json? created;
      if (widget.group) {
        created = await c.rpc(
          existing == null ? 'groups.create' : 'groups.update',
          {
            if (existing != null) 'groupId': existing['groupId'],
            'name': name.text,
            'botIds': members.toList(),
            'leadBotId': lead,
          },
        );
      } else {
        if (source == null || model.text.isEmpty) {
          throw RelayError(c.tr('请选择模型', 'Choose a model'));
        }
        if (widget.importProfile && archive == null) {
          throw RelayError(
            c.tr(
              '请先选择 Hermes profile 压缩包',
              'Choose a Hermes profile archive first',
            ),
          );
        }
        if (widget.importProfile && archive!['fileId'] == null) {
          final file = archive!;
          await c.deliveries.upload(
            file,
            file['nodeId'] as String,
            file['conversationId'] as String,
          );
        }
        if (existing == null) {
          widget.onCreating?.call({
            'nodeId': c.selectedNodeId,
            'displayName': name.text,
            'avatar': {'shape': shape, 'color': color},
          });
        }
        created = await c.rpc(
          existing == null ? 'bots.create' : 'bots.update',
          {
            if (existing != null) 'botId': existing['botId'],
            'displayName': name.text,
            if (existing != null || handleEdited) 'handle': handle.text,
            // The role is written in the chat once the Bot is open, not here.
            if (existing == null) 'role': '',
            'model': model.text.trim(),
            'avatar': {'shape': shape, 'color': color},
            'approvalMode': mode,
            if (source != null) 'sourceId': source,
            if (widget.importProfile) 'archiveFileId': archive!['fileId'],
            'modelSettings': {
              'contextLength': contextLength.text.trim().isEmpty
                  ? null
                  : int.parse(contextLength.text),
            },
          },
        );
      }
      if (mounted) {
        setState(() => busy = false);
        Navigator.pop(
          context,
          existing == null ? created['conversation'] : null,
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      widget.onCreating?.call(null);
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    name.dispose();
    handle.dispose();
    model.dispose();
    contextLength.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    const gap = SizedBox(height: 10);
    return PopScope(
      canPop: !busy,
      child: AppPage(
        title: widget.group
            ? c.tr('群组', 'Group')
            : widget.importProfile
            ? c.tr('导入 Hermes profile', 'Import Hermes profile')
            : widget.existing == null
            ? c.tr('新建 Bot', 'New Bot')
            : c.tr('编辑 Bot', 'Edit Bot'),
        body: PageList(
          children: [
            if (widget.importProfile) ...[
              Text(
                c.tr(
                  '从压缩包创建独立 Bot，保留导入的技能和设定。凭据不在可分享的压缩包中，请选择本节点已有模型来源。',
                  'Create an independent Bot with the archive’s skills and settings. Shared archives exclude credentials; choose a model source on this Node.',
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.folder_zip_outlined),
                label: Text(
                  '${archive?['name'] ?? c.tr('选择 .tar.gz 文件', 'Choose .tar.gz file')}',
                ),
                onPressed: busy
                    ? null
                    : () async {
                        try {
                          final dm = c.node.conversations.firstWhere(
                            (row) => row['kind'] == 'dm',
                          );
                          final file = await pickChatFile(
                            c,
                            '${dm['conversationId']}',
                            (_) {},
                          );
                          if (file != null && mounted) {
                            setState(() => archive = file);
                          }
                        } catch (e) {
                          if (mounted) setState(() => error = '$e');
                        }
                      },
              ),
              gap,
            ],
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
                    size: tone.glass ? 104 : 88,
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
                          radius: 30,
                          onTap: () => setState(() => shape = value),
                          child: Semantics(
                            button: true,
                            selected: value == shape,
                            child: AnimatedContainer(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 160),
                              width: tone.glass ? 52 : 44,
                              height: tone.glass ? 52 : 44,
                              padding: const EdgeInsets.all(7),
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
                  width: 44 * 8 + 4 * 7,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final value in avatarColors)
                        InkResponse(
                          key: ValueKey('avatar-color-$value'),
                          radius: 24,
                          onTap: () => setState(() => color = value),
                          child: Semantics(
                            button: true,
                            selected: value == color,
                            label: value,
                            child: SizedBox.square(
                              dimension: 44,
                              child: Center(
                                child: AnimatedContainer(
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                      ? Duration.zero
                                      : const Duration(milliseconds: 160),
                                  width: tone.glass ? 40 : 30,
                                  height: tone.glass ? 40 : 30,
                                  padding: const EdgeInsets.all(4),
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
              child: TextField(
                key: const ValueKey('bot-name'),
                controller: name,
                decoration: InputDecoration(),
                onChanged: widget.group || widget.existing != null
                    ? null
                    : (value) {
                        if (!handleEdited) {
                          handle.text = value
                              .trim()
                              .toLowerCase()
                              .replaceFirst(RegExp(r'^@'), '')
                              .replaceAll(RegExp(r'\s+'), '-')
                              .replaceAll(
                                RegExp(r'[^a-z0-9\u3400-\u9fff_-]'),
                                '-',
                              )
                              .replaceAll(RegExp(r'^-+|-+$'), '')
                              .characters
                              .take(24)
                              .toString();
                        }
                      },
              ),
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
                child: MenuSelect<String>(
                  value: lead,
                  options: [
                    for (final b in c.node.bots.where(
                      (b) => members.contains(b['botId']),
                    ))
                      (b['botId'] as String, '${b['displayName']}'),
                  ],
                  onChanged: (value) => setState(() => lead = value),
                ),
              ),
            ] else ...[
              ModelSelection(
                client: c,
                sourceId: source,
                model: model.text,
                enabled: !busy,
                onChanged: (selected, value) => setState(() {
                  source = selected;
                  model.text = value;
                }),
              ),
              gap,
              LabeledField(
                label: c.tr('审批', 'Approval'),
                child: MenuSelect<String>(
                  key: const ValueKey('approval-mode'),
                  value: mode,
                  options: [
                    ('manual', c.tr('每次询问', 'Ask each time')),
                    ('smart', c.tr('智能审批', 'Smart approval')),
                    ('off', c.tr('全部允许', 'Allow all')),
                  ],
                  onChanged: permissionsReady
                      ? (value) => setState(() => mode = value)
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
                    label: '@handle',
                    child: TextField(
                      controller: handle,
                      onChanged: (_) => handleEdited = true,
                      decoration: InputDecoration(
                        helperText: c.tr(
                          '默认与名称相同，支持中文；想换一个写法时再改',
                          'Same as the name by default, Chinese included; change it only if you want another',
                        ),
                        helperMaxLines: 3,
                      ),
                    ),
                  ),
                  gap,
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
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text(
                                  widget.group
                                      ? c.tr('归档此群聊？', 'Archive this group?')
                                      : c.tr('归档此 Bot？', 'Archive this Bot?'),
                                ),
                                content: Text(name.text),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: Text(c.tr('取消', 'Cancel')),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: Text(c.tr('归档', 'Archive')),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true || !mounted) return;
                            setState(() => busy = true);
                            try {
                              await c.rpc(
                                widget.group
                                    ? 'groups.archive'
                                    : 'bots.archive',
                                {
                                  widget.group ? 'groupId' : 'botId':
                                      widget.existing![widget.group
                                          ? 'groupId'
                                          : 'botId'],
                                },
                              );
                              if (context.mounted) {
                                setState(() => busy = false);
                                Navigator.pop(context);
                              }
                            } catch (e) {
                              if (mounted) {
                                setState(() {
                                  error = '$e';
                                  busy = false;
                                });
                              }
                            }
                          },
                    child: Text(c.tr('归档', 'Archive')),
                  ),
                const Spacer(),
                FilledButton(
                  key: const ValueKey('bot-save'),
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
                      ? ShiningText(
                          text: widget.existing == null
                              ? c.tr('创建中…', 'Creating…')
                              : c.tr('正在保存…', 'Saving…'),
                        )
                      : Text(c.tr('保存', 'Save')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
