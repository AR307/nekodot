import 'dart:async';

import 'package:flutter/material.dart';

import '../data/client.dart';
import '../ui/design.dart';
import '../screen/viewer.dart';
import 'bot_editor.dart';
import 'files.dart';
import 'model_info.dart';

class BotDetails extends StatelessWidget {
  final NekodotClient client;
  final Json bot;
  const BotDetails({super.key, required this.client, required this.bot});
  @override
  Widget build(BuildContext context) {
    final c = client;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${bot['displayName']}'),
          bottom: TabBar(
            tabs: [
              Tab(text: c.tr('详情', 'Details')),
              Tab(text: c.tr('记忆', 'Memory')),
              Tab(text: c.tr('资料库', 'Files')),
            ],
          ),
          actions: [
            IconButton(
              tooltip: c.tr('屏幕', 'Screen'),
              onPressed: () =>
                  pushPage(context, ScreenPage(client: c, bot: bot)),
              icon: const Icon(Icons.desktop_windows_outlined),
            ),
            IconButton(
              tooltip: c.tr('编辑', 'Edit'),
              onPressed: () =>
                  pushPage(context, BotEditor(client: c, existing: bot)),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        body: TabBarView(
          children: [
            AsyncPane(
              load: () => c.rpc('bots.jobs', {'botId': bot['botId']}),
              builder: (context, data, reload) => ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Center(
                    child: CatAvatar(
                      color: '${bot['avatar']['color']}',
                      size: 70,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '${bot['role']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  Text('${bot['model']}'),
                  const SizedBox(height: 16),
                  ModelInformation(client: c, botId: bot['botId'] as String),
                  const SizedBox(height: 26),
                  Text(
                    c.tr('定时任务', 'Scheduled tasks'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    c.tr(
                      '通过聊天创建和修改，按 Hermes 原生计划执行。',
                      'Create and edit through chat. Hermes runs the schedule.',
                    ),
                  ),
                  for (final job in objects(data['jobs']))
                    Card(
                      child: ExpansionTile(
                        title: Text(
                          '${job['name'] ?? job['prompt'] ?? job['id']}',
                        ),
                        subtitle: Text(
                          '${job['schedule'] ?? ''} · ${job['timezone'] ?? ''}',
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: SelectableText(job.toString()),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            AsyncPane(
              load: () => c.rpc('memory.get', {'botId': bot['botId']}),
              builder: (context, data, reload) => ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  for (final doc in objects(data['documents']))
                    Card(
                      child: ListTile(
                        title: Text('${doc['name']}'),
                        subtitle: Text(
                          doc['name'] == 'USER.md'
                              ? c.tr(
                                  '同账号所有 Bot 共享',
                                  'Shared with every Bot on your account',
                                )
                              : '${doc['content']}',
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await pushPage(
                            context,
                            MemoryEditor(
                              client: c,
                              botId: bot['botId'] as String,
                              document: doc,
                            ),
                          );
                          reload();
                        },
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () async {
                      await pushPage(
                        context,
                        RefinePage(client: c, botId: bot['botId'] as String),
                      );
                      reload();
                    },
                    icon: const Icon(Icons.auto_fix_high),
                    label: Text(c.tr('整理记忆', 'Refine memory')),
                  ),
                  if ('${data['pending'] ?? ''}'.isNotEmpty)
                    SelectableText('${data['pending']}'),
                ],
              ),
            ),
            LibraryPage(client: c, bot: bot, embedded: true),
          ],
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.document['name']}'),
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
    ),
    body: Column(
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
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(24),
            ),
          ),
        ),
      ],
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.client.tr('整理记忆', 'Refine memory'))),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          controller: focus,
          minLines: 3,
          maxLines: 8,
          decoration: InputDecoration(
            labelText: widget.client.tr('整理重点（可选）', 'Focus (optional)'),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
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
          child: Text(
            widget.client.tr('运行 Hermes /refine', 'Run Hermes /refine'),
          ),
        ),
        if (operation != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              '${operation!['status']}\n${operation!['detail']}',
            ),
          ),
        ErrorNotice(error),
      ],
    ),
  );
}
