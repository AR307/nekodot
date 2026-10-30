import 'dart:async';

import 'package:flutter/material.dart';

import '../data/client.dart';
import '../platform/desktop.dart';
import '../ui/design.dart';
import '../screen/viewer.dart';
import 'bot_editor.dart';
import 'files.dart';
import 'model_info.dart';
import 'user_memory.dart';

class BotDetails extends StatelessWidget {
  final NekodotClient client;
  final Json bot;

  /// Set when shown as a side panel; closes it instead of popping a page.
  final VoidCallback? onClose;
  const BotDetails({
    super.key,
    required this.client,
    required this.bot,
    this.onClose,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: client,
    builder: (context, child) {
      final c = client;
      final bot = c.node.bots
          .where((value) => value['botId'] == this.bot['botId'])
          .firstOrNull;
      if (bot == null || bot['archived'] == true) {
        return AppPage(
          title: c.tr('已归档', 'Archived'),
          body: const Center(
            child: Opacity(opacity: .25, child: CatAvatar(size: 72)),
          ),
        );
      }
      final text = Theme.of(context).textTheme;
      final panel = onClose != null;
      final pages = TabBarView(
        children: [
          AsyncPane(
            load: () => c.rpc('bots.jobs', {'botId': bot['botId']}),
            builder: (context, data, reload) {
              final jobs = objects(data['jobs']);
              return PageList(
                children: [
                  if (context.tone.glass) ...[
                    Center(child: CatAvatar.of(bot, size: 64)),
                    const SizedBox(height: 6),
                    Center(
                      child: Text('@${bot['handle']}', style: text.labelMedium),
                    ),
                    const SizedBox(height: 18),
                    SelectableText(
                      '${bot['role']}',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: 22),
                  ] else ...[
                    SectionLabel(c.tr('角色', 'Role')),
                    Panel(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: SelectableText(
                          '${bot['role']}',
                          style: text.bodyMedium,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  ModelInformation(
                    key: ValueKey('${bot['model']}:${bot['modelSettings']}'),
                    client: c,
                    botId: bot['botId'] as String,
                  ),
                  if (jobs.isNotEmpty) ...[
                    SectionLabel(c.tr('定时任务', 'Scheduled tasks')),
                    PanelGroup(
                      children: [
                        for (final job in jobs)
                          ExpansionTile(
                            title: Text(
                              '${job['name'] ?? job['prompt'] ?? job['id']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${job['schedule'] ?? ''} · ${job['timezone'] ?? ''}',
                              style: text.bodySmall,
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              16,
                            ),
                            children: [
                              SelectableText(
                                job.toString(),
                                style: text.bodySmall,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
          AsyncPane(
            load: () => c.rpc('memory.get', {'botId': bot['botId']}),
            builder: (context, data, reload) => PageList(
              children: [
                PanelGroup(
                  children: [
                    for (final doc in objects(data['documents']))
                      ListTile(
                        title: Text('${doc['name']}'),
                        subtitle:
                            doc['name'] == 'USER.md' ||
                                '${doc['content']}'.trim().isEmpty
                            ? null
                            : Text(
                                '${doc['content']}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                        trailing: doc['name'] == 'USER.md'
                            ? Tooltip(
                                message: c.tr(
                                  '同账号所有 Bot 共享',
                                  'Shared with every Bot on your account',
                                ),
                                child: Icon(
                                  Icons.group_outlined,
                                  size: 18,
                                  color: context.tone.ink3,
                                ),
                              )
                            : null,
                        onTap: () async {
                          await pushPage(
                            context,
                            doc['name'] == 'USER.md'
                                ? SharedUserMemoryPage(client: c)
                                : MemoryEditor(
                                    client: c,
                                    botId: bot['botId'] as String,
                                    document: doc,
                                  ),
                          );
                          reload();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await pushPage(
                        context,
                        RefinePage(client: c, botId: bot['botId'] as String),
                      );
                      reload();
                    },
                    icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
                    label: Text(c.tr('整理记忆', 'Refine memory')),
                  ),
                ),
                if ('${data['pending'] ?? ''}'.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SelectableText(
                      '${data['pending']}',
                      style: text.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          LibraryPage(client: c, bot: bot, embedded: true),
        ],
      );
      if (context.tone.glass && !panel) {
        return DefaultTabController(
          length: 3,
          child: AppPage(
            title: '${bot['displayName']}',
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(44),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: TabBar(
                      tabs: [
                        Tab(height: 34, text: c.tr('详情', 'Details')),
                        Tab(height: 34, text: c.tr('记忆', 'Memory')),
                        Tab(height: 34, text: c.tr('资料库', 'Files')),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              IconAction(
                tooltip: c.tr('屏幕', 'Screen'),
                icon: Icons.desktop_windows_outlined,
                onPressed: () =>
                    pushPage(context, ScreenPage(client: c, bot: bot)),
              ),
              IconAction(
                tooltip: c.tr('编辑', 'Edit'),
                icon: Icons.edit_outlined,
                onPressed: () =>
                    pushPage(context, BotEditor(client: c, existing: bot)),
              ),
            ],
            body: pages,
          ),
        );
      }
      return DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: !panel,
            flexibleSpace: const WindowDrag(),
            actions: [
              IconAction(
                tooltip: c.tr('屏幕', 'Screen'),
                icon: Icons.desktop_windows_outlined,
                onPressed: () =>
                    pushPage(context, ScreenPage(client: c, bot: bot)),
              ),
              IconAction(
                tooltip: c.tr('编辑', 'Edit'),
                icon: Icons.edit_outlined,
                onPressed: () =>
                    pushPage(context, BotEditor(client: c, existing: bot)),
              ),
              if (panel) ...[
                IconAction(
                  tooltip: c.tr('关闭', 'Close'),
                  icon: Icons.close,
                  onPressed: onClose,
                ),
              ],
              const SizedBox(width: 8),
              SizedBox(width: WindowChrome.reserved(context)),
            ],
          ),
          body: Column(
            children: [
              CatAvatar.of(bot, size: 56),
              const SizedBox(height: 8),
              Text(
                '${bot['displayName']}',
                style: text.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text('@${bot['handle']}', style: text.labelMedium),
              const SizedBox(height: 10),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.center,
                labelPadding: const EdgeInsets.symmetric(horizontal: 10),
                tabs: [
                  Tab(height: 28, text: c.tr('详情', 'Details')),
                  Tab(height: 28, text: c.tr('记忆', 'Memory')),
                  Tab(height: 28, text: c.tr('资料库', 'Files')),
                ],
              ),
              const SizedBox(height: 4),
              const Divider(height: 1),
              Expanded(child: pages),
            ],
          ),
        ),
      );
    },
  );
}

class MemoryEditor extends StatefulWidget {
  final NekodotClient client;
  final String botId;
  final Json document;
  const MemoryEditor({
    super.key,
    required this.client,
    required this.botId,
    required this.document,
  });
  @override
  State<MemoryEditor> createState() => _MemoryEditorState();
}

class _MemoryEditorState extends State<MemoryEditor> {
  late final text = TextEditingController(
    text: widget.document['content'] as String,
  );
  String error = '';
  bool busy = false;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: '${widget.document['name']}',
    actions: [
      TextButton(
        onPressed: busy
            ? null
            : () async {
                setState(() => busy = true);
                try {
                  await widget.client.rpc('memory.save', {
                    'botId': widget.botId,
                    'name': widget.document['name'],
                    'content': text.text,
                  });
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (mounted) setState(() => error = '$e');
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
        child: Text(widget.client.tr('保存', 'Save')),
      ),
    ],
    body: SafeArea(
      child: Column(
        children: [
          ErrorNotice(error),
          Expanded(
            child: TextField(
              controller: text,
              expands: true,
              minLines: null,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.all(24),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class RefinePage extends StatefulWidget {
  final NekodotClient client;
  final String botId;
  const RefinePage({super.key, required this.client, required this.botId});
  @override
  State<RefinePage> createState() => _RefinePageState();
}

class _RefinePageState extends State<RefinePage> {
  final focus = TextEditingController();
  Json? operation;
  String error = '';
  Timer? timer;
  @override
  void dispose() {
    focus.dispose();
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: widget.client.tr('整理记忆', 'Refine memory'),
    body: PageList(
      children: [
        LabeledField(
          label: widget.client.tr('重点', 'Focus'),
          child: TextField(
            controller: focus,
            minLines: 3,
            maxLines: 8,
            decoration: InputDecoration(),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: operation?['status'] == 'running'
                ? null
                : () async {
                    try {
                      final value = await widget.client.rpc('memory.refine', {
                        'botId': widget.botId,
                        'focus': focus.text,
                      });
                      if (!mounted) return;
                      setState(() => operation = value);
                      timer = Timer.periodic(const Duration(seconds: 2), (
                        _,
                      ) async {
                        try {
                          final value = await widget.client.rpc(
                            'operations.get',
                            {'operationId': operation!['operationId']},
                          );
                          if (mounted) setState(() => operation = value);
                          if (value['status'] != 'running') timer?.cancel();
                        } catch (e) {
                          if (mounted) setState(() => error = '$e');
                          timer?.cancel();
                        }
                      });
                    } catch (e) {
                      if (mounted) setState(() => error = '$e');
                    }
                  },
            child: Text(widget.client.tr('开始整理', 'Refine')),
          ),
        ),
        if (operation != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              '${operation!['status']}\n${operation!['detail']}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ErrorNotice(error),
      ],
    ),
  );
}
