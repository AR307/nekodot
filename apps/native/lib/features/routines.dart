import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../ui/design.dart';
import '../ui/chat_notice.dart';
import '../ui/message_markdown.dart';
import 'chat.dart';
import 'sessions.dart';

String triggerLabel(NekodotClient c, Json routine) =>
    switch (routine['trigger']) {
      'both' => c.tr('定时 + Webhook', 'Schedule + Webhook'),
      'schedule' => c.tr('定时', 'Schedule'),
      _ => 'Webhook',
    };

String routineStatus(NekodotClient c, Json routine) {
  final enabled = routine['enabled'] == true;
  final status = enabled ? c.tr('已启用', 'Enabled') : c.tr('已暂停', 'Paused');
  if (routine['trigger'] != 'both') return status;
  final schedule = object(object(routine['native'] ?? {})['schedule'] ?? {});
  return 'Webhook $status, ${schedule['enabled'] == true ? c.tr('定时已启用', 'Schedule enabled') : c.tr('定时已暂停', 'Schedule paused')}';
}

class RoutineList extends StatelessWidget {
  final NekodotClient client;
  final List<Json> routines;
  final VoidCallback reload;
  const RoutineList({
    super.key,
    required this.client,
    required this.routines,
    required this.reload,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionLabel(client.tr('例行任务', 'Routines')),
      if (routines.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            client.tr(
              '通过聊天创建定时或 Webhook 任务',
              'Create scheduled or webhook tasks in chat',
            ),
          ),
        )
      else
        PanelGroup(
          children: [
            for (final routine in routines)
              ListTile(
                leading: Icon(
                  routine['trigger'] == 'schedule'
                      ? Icons.schedule
                      : Icons.webhook,
                ),
                title: Text(
                  '${routine['name']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: MetaText([
                  triggerLabel(client, routine),
                  routineStatus(client, routine),
                ]),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () async {
                  await pushPage(
                    context,
                    RoutinePage(
                      client: client,
                      botId: '${routine['botId']}',
                      routineId: '${routine['routineId']}',
                    ),
                  );
                  reload();
                },
              ),
          ],
        ),
    ],
  );
}

/// Only an identifier and delivery status are persisted in this chat card.
class RoutineCard extends StatelessWidget {
  final NekodotClient client;
  final Json content;
  const RoutineCard({super.key, required this.client, required this.content});

  /// One quiet line: what happened and to which routine; it opens the routine.
  @override
  Widget build(BuildContext context) {
    final action = content['card'] == 'credentials'
        ? client.tr('已保密交付', 'Delivered securely')
        : switch (content['action']) {
            'updated' => client.tr('已修改', 'Updated'),
            'enabled' => client.tr('已启用', 'Enabled'),
            'stopped' => client.tr('已停止', 'Stopped'),
            'started' => client.tr('正在执行', 'Running'),
            'executed' => client.tr('已执行', 'Executed'),
            'failed' => client.tr('执行失败', 'Failed'),
            _ => client.tr('已创建', 'Created'),
          };
    void openRoutine() => unawaited(
      pushPage(
        context,
        RoutinePage(
          client: client,
          botId: '${content['botId']}',
          routineId: '${content['routineId']}',
          executionId: content['executionId'] as String?,
        ),
      ),
    );
    return ChatNotice(
      text: '$action ${content['name']}',
      icon: content['card'] == 'credentials'
          ? Icons.lock_outline
          : Icons.schedule,
      onTap: openRoutine,
    );
  }
}

class RoutinePage extends StatefulWidget {
  final NekodotClient client;
  final String botId, routineId;
  final String? executionId;
  const RoutinePage({
    super.key,
    required this.client,
    required this.botId,
    required this.routineId,
    this.executionId,
  });
  @override
  State<RoutinePage> createState() => _RoutinePageState();
}

class _RoutinePageState extends State<RoutinePage> {
  Json? data;
  String error = '', receipt = '';
  bool busy = false, loading = false;
  Timer? timer;
  NekodotClient get c => widget.client;
  Json get target => {'botId': widget.botId, 'routineId': widget.routineId};
  @override
  void initState() {
    super.initState();
    unawaited(load());
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (c.online && !busy) unawaited(load());
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    if (loading) return;
    loading = true;
    try {
      final value = await c.rpc('routines.get', target);
      if (mounted) {
        setState(() {
          data = value;
          error = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      loading = false;
    }
  }

  Future<void> action(Future<void> Function() run) async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await run();
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> copySecret() async {
    final credentials = await c.rpc('routines.credentials', target);
    await Clipboard.setData(ClipboardData(text: '${credentials['secret']}'));
    if (mounted) {
      showNotice(
        context,
        c.tr('已复制密钥，请勿粘贴到聊天中', 'Secret copied. Do not paste it into chat.'),
      );
    }
  }

  Future<void> continueExecution(Json execution) async {
    final dm = c.node.conversations.firstWhere(
      (row) => row['kind'] == 'dm' && row['botId'] == widget.botId,
    );
    final id = '${dm['conversationId']}';
    c.routineDrafts['${c.selectedNodeId}:$id'] = {
      'executionId': execution['executionId'],
      'name': data!['routine']['name'],
    };
    await pushPage(context, ChatPage(client: c, conversationId: id));
  }

  Future<void> test(Json routine) async {
    final input = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert({
        'event_type': (routine['events'] as List).firstOrNull ?? 'test',
        'message': 'nekodot routine test',
      }),
    );
    final payload = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(c.tr('测试唤醒', 'Test webhook')),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: input,
            minLines: 5,
            maxLines: 10,
            decoration: const InputDecoration(labelText: 'JSON'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(c.tr('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: Text(c.tr('发送', 'Send')),
          ),
        ],
      ),
    );
    // Keep the field alive until the dialog's reverse transition has finished.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    input.dispose();
    if (payload == null || !mounted) return;
    await action(() async {
      final body = object(jsonDecode(payload));
      final value = await c.rpc('routines.test', {
        ...target,
        'payload': body,
        'requestId': uid(),
      });
      if (mounted) {
        setState(
          () =>
              receipt = 'HTTP ${value['status']}\n${jsonEncode(value['body'])}',
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final routine = data == null ? null : object(data!['routine']);
      final native = object(routine?['native'] ?? {});
      final schedule = routine?['trigger'] == 'both'
          ? object(native['schedule'])
          : native;
      final webhook = routine != null && routine['trigger'] != 'schedule';
      final enabled = routine?['enabled'] == true;
      final allowed = c.online && !busy;
      return AppPage(
        title: '${routine?['name'] ?? c.tr('例行任务', 'Routine')}',
        extendBodyBehindAppBar: false,
        actions: [
          IconAction(
            tooltip: c.tr('刷新', 'Refresh'),
            icon: Icons.refresh,
            onPressed: busy ? null : load,
          ),
        ],
        body: data == null && error.isEmpty
            ? const Center(child: ShiningText())
            : PageList(
                children: [
                  if (!c.online)
                    Text(
                      c.tr(
                        '电脑离线，无法管理任务',
                        'Node is offline. Routine controls are unavailable.',
                      ),
                    ),
                  ErrorNotice(error),
                  if (routine != null) ...[
                    MetaText([
                      '${c.node.bots.where((b) => b['botId'] == widget.botId).firstOrNull?['displayName'] ?? widget.botId}',
                      routineStatus(c, routine),
                    ], style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Text(
                      triggerLabel(c, routine),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    SelectableText('${routine['description']}'),
                    const SizedBox(height: 12),
                    SectionLabel(c.tr('固定提示模板', 'Fixed prompt template')),
                    Panel(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: SelectableText('${routine['prompt']}'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SelectableText('${routine['permissions']}'),
                    if (routine['native'] != null &&
                        routine['trigger'] != 'webhook') ...[
                      SectionLabel(
                        c.tr('原生定时与记录', 'Native schedule and history'),
                      ),
                      Panel(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                '${schedule['schedule_display'] ?? ''}',
                              ),
                              Text(
                                '${c.tr('下次执行', 'Next run')}: ${schedule['next_run_at'] ?? '—'}',
                              ),
                              Text(
                                '${c.tr('最近结果', 'Last result')}: ${schedule['last_status'] ?? '—'}',
                              ),
                              if (schedule['last_error'] != null)
                                ErrorNotice('${schedule['last_error']}'),
                              SelectableText(
                                'Hermes cron: ${routine['cronJobId']}',
                              ),
                            ],
                          ),
                        ),
                      ),
                      for (final run in objects(native['runs']))
                        Panel(
                          child: ExpansionTile(
                            title: Text(
                              '${run['cron_status'] ?? run['status'] ?? (run['is_active'] == true ? c.tr('执行中', 'Running') : c.tr('原生记录', 'Native record'))}',
                            ),
                            subtitle: Text(
                              '${run['id'] ?? run['session_id'] ?? run['started_at'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            childrenPadding: const EdgeInsets.all(14),
                            children: [
                              SelectableText(
                                const JsonEncoder.withIndent('  ').convert(run),
                              ),
                            ],
                          ),
                        ),
                    ],
                    if (webhook) ...[
                      const SizedBox(height: 12),
                      SectionLabel('Webhook'),
                      SelectableText('${routine['url']}'),
                      const SizedBox(height: 8),
                      Text(
                        c.tr(
                          '密钥：••••••••，加密保存在电脑上',
                          'Secret: ••••••••, encrypted on the node',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: '${routine['url']}'),
                              );
                              if (context.mounted) {
                                showNotice(
                                  context,
                                  c.tr('已复制 URL', 'URL copied'),
                                );
                              }
                            },
                            icon: const Icon(Icons.link),
                            label: Text(c.tr('复制 URL', 'Copy URL')),
                          ),
                          OutlinedButton.icon(
                            onPressed: allowed
                                ? () => action(copySecret)
                                : null,
                            icon: const Icon(Icons.key),
                            label: Text(c.tr('复制密钥', 'Copy secret')),
                          ),
                          FilledButton.icon(
                            onPressed: !allowed || routine['granted'] == true
                                ? null
                                : () => action(() async {
                                    await c.rpc('routines.grant', target);
                                  }),
                            icon: const Icon(Icons.lock_outline),
                            label: Text(
                              c.tr('确认接入并保密交付', 'Connect & deliver securely'),
                            ),
                          ),
                          OutlinedButton(
                            onPressed: allowed && routine['granted'] == true
                                ? () => action(() async {
                                    await c.rpc('routines.enable', {
                                      ...target,
                                      'enabled': !enabled,
                                    });
                                  })
                                : null,
                            child: Text(
                              enabled
                                  ? c.tr('暂停 Webhook', 'Pause webhook')
                                  : c.tr('恢复 Webhook', 'Resume webhook'),
                            ),
                          ),
                          OutlinedButton(
                            onPressed: allowed && enabled
                                ? () => test(routine)
                                : null,
                            child: Text(c.tr('测试唤醒', 'Test webhook')),
                          ),
                          OutlinedButton(
                            onPressed: !allowed
                                ? null
                                : () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: Text(
                                          c.tr('更换密钥？', 'Rotate secret?'),
                                        ),
                                        content: Text(
                                          c.tr(
                                            '旧密钥立即失效。使用凭据引用的脚本无需修改；其他服务需重新复制。',
                                            'The old secret stops working immediately. Reference-based scripts keep working; other services need the new secret.',
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: Text(c.tr('取消', 'Cancel')),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: Text(c.tr('更换', 'Rotate')),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true && mounted) {
                                      await action(() async {
                                        await c.rpc('routines.rotate', target);
                                      });
                                    }
                                  },
                            child: Text(c.tr('更换密钥', 'Rotate secret')),
                          ),
                          OutlinedButton(
                            onPressed: allowed
                                ? () async {
                                    await pushPage(
                                      context,
                                      RoutineEditor(
                                        client: c,
                                        routine: routine,
                                      ),
                                    );
                                    await load();
                                  }
                                : null,
                            child: Text(c.tr('编辑', 'Edit')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        c.tr(
                          '暂停不取消已运行的任务；保密交付不扩大工具权限。',
                          'Pausing does not cancel a running task. Credential delivery does not grant additional tools.',
                        ),
                      ),
                      SectionLabel(c.tr('调用示例', 'Example request')),
                      SelectableText(
                        'curl -X POST "${routine['url']}" \\\n  -H "Authorization: Bearer \$NEKODOT_WEBHOOK_SECRET" \\\n  -H "Content-Type: application/json" \\\n  -H "X-Request-ID: event-001" \\\n  -d \'{"event_type":"${(routine['events'] as List).firstOrNull ?? 'test'}","message":"hello"}\'',
                      ),
                      const SizedBox(height: 10),
                      SelectableText(
                        'hermes routine send ${routine['routineId']} --request-id event-001 --payload \'{"event_type":"${(routine['events'] as List).firstOrNull ?? 'test'}","message":"hello"}\'',
                      ),
                      Text(
                        c.tr(
                          '脚本使用上面的凭据引用；密钥不进入脚本或模型上下文。HTTP 接收回执不等于执行完成。',
                          'Scripts use this credential reference, not the secret. An HTTP receipt is not task completion.',
                        ),
                      ),
                      Text(
                        c.tr(
                          '新事件使用新的 X-Request-ID；重试同一事件时保留原 ID。',
                          'Use a new X-Request-ID for each event; retries keep the original ID.',
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: !allowed
                            ? null
                            : () async {
                                final value = await pushPage<Json>(
                                  context,
                                  RoutineEditor(client: c, routine: routine),
                                );
                                await load();
                                if (context.mounted && value != null) {
                                  await pushPage(
                                    context,
                                    RoutinePage(
                                      client: c,
                                      botId: widget.botId,
                                      routineId: '${value['routineId']}',
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.webhook),
                        label: Text(
                          c.tr('添加 Webhook 触发', 'Add webhook trigger'),
                        ),
                      ),
                    ],
                    if (busy) const ShiningText(),
                    if (receipt.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: SelectableText(
                          receipt,
                          key: const ValueKey('routine-test-receipt'),
                        ),
                      ),
                    if (webhook) ...[
                      SectionLabel(c.tr('接收回执', 'Delivery receipts')),
                      Text(
                        c.tr(
                          '这是 Hermes 的接收或拒绝结果，不代表模型已完成任务。',
                          'These are native acceptance or refusal receipts, not model completion.',
                        ),
                      ),
                      for (final item in objects(data!['receipts']))
                        Panel(
                          child: ExpansionTile(
                            title: MetaText([
                              'HTTP ${item['status']}',
                              '${item['receivedAt']}',
                            ]),
                            subtitle: Text(
                              '${item['requestId']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            childrenPadding: const EdgeInsets.all(14),
                            children: [
                              SelectableText(
                                const JsonEncoder.withIndent('  ')
                                    .convert(item['body']),
                              ),
                            ],
                          ),
                        ),
                    ],
                    SectionLabel(c.tr('执行记录', 'Executions')),
                    for (final execution in objects(data!['executions']))
                      Panel(
                        child: ExpansionTile(
                          key: ValueKey(execution['executionId']),
                          initiallyExpanded:
                              widget.executionId == execution['executionId'],
                          title: MetaText([
                            '${execution['state']}',
                            '${execution['updatedAt']}',
                          ]),
                          subtitle: Text(
                            '${execution['requestId'] ?? execution['sessionId']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          childrenPadding: const EdgeInsets.all(14),
                          children: [
                            MessageMarkdown(
                              data: '${execution['text']}'.isEmpty
                                  ? c.tr(
                                      '原生任务未返回文本',
                                      'No text returned by the native task',
                                    )
                                  : '${execution['text']}',
                            ),
                            if (execution['reason'] != null)
                              SelectableText('${execution['reason']}'),
                            const SizedBox(height: 8),
                            SelectableText(
                              'Hermes session: ${execution['sessionId']}',
                            ),
                            Wrap(
                              spacing: 8,
                              children: [
                                if (!const [
                                  'running',
                                  'waiting_approval',
                                ].contains(execution['state']))
                                  TextButton.icon(
                                    key: ValueKey(
                                      'routine-followup-${execution['executionId']}',
                                    ),
                                    onPressed: c.online
                                        ? () => continueExecution(execution)
                                        : null,
                                    icon: const Icon(Icons.reply),
                                    label: Text(c.tr('继续对话', 'Discuss result')),
                                  ),
                                TextButton(
                                  onPressed: () => pushPage(
                                    context,
                                    SessionHistoryPage(
                                      client: c,
                                      botId: widget.botId,
                                      row: {
                                        'session_id': execution['sessionId'],
                                        'source': 'cron',
                                      },
                                    ),
                                  ),
                                  child: Text(c.tr('查看执行记录', 'View execution')),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
      );
    },
  );
}

class RoutineEditor extends StatefulWidget {
  final NekodotClient client;
  final Json routine;
  const RoutineEditor({super.key, required this.client, required this.routine});
  @override
  State<RoutineEditor> createState() => _RoutineEditorState();
}

class _RoutineEditorState extends State<RoutineEditor> {
  late final name = TextEditingController(text: '${widget.routine['name']}');
  late final description = TextEditingController(
    text: '${widget.routine['description']}',
  );
  late final prompt = TextEditingController(
    text: widget.routine['trigger'] == 'schedule'
        ? 'External event: {__raw__}'
        : '${widget.routine['prompt']}',
  );
  late final events = TextEditingController(
    text: (widget.routine['events'] as List).join(', '),
  );
  late final skills = TextEditingController(
    text: (widget.routine['skills'] as List).join(', '),
  );
  String error = '';
  bool busy = false;
  @override
  void dispose() {
    for (final c in [name, description, prompt, events, skills]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client, r = widget.routine;
    final create = r['trigger'] == 'schedule';
    List<String> entries(TextEditingController field) => field.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return AppPage(
      title: c.tr('Webhook 设置', 'Webhook settings'),
      extendBodyBehindAppBar: false,
      body: PageList(
        children: [
          TextField(
            controller: name,
            decoration: InputDecoration(labelText: c.tr('名称', 'Name')),
          ),
          TextField(
            controller: description,
            decoration: InputDecoration(labelText: c.tr('执行说明', 'Description')),
          ),
          TextField(
            controller: prompt,
            minLines: 4,
            maxLines: 12,
            decoration: InputDecoration(
              labelText: c.tr(
                '固定提示模板，{__raw__} 引用事件',
                'Fixed prompt template, {__raw__} for event data',
              ),
            ),
          ),
          TextField(
            controller: events,
            decoration: InputDecoration(
              labelText: c.tr(
                '事件类型（逗号分隔，留空接受全部）',
                'Event types (comma-separated, empty for all)',
              ),
            ),
          ),
          TextField(
            controller: skills,
            decoration: InputDecoration(
              labelText: c.tr('原生技能（逗号分隔）', 'Native skills (comma-separated)'),
            ),
          ),
          ErrorNotice(error),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() {
                      busy = true;
                      error = '';
                    });
                    try {
                      final value = await c.rpc(
                        create ? 'routines.create' : 'routines.update',
                        {
                          'botId': r['botId'],
                          if (!create) 'routineId': r['routineId'],
                          'name': name.text,
                          'description': description.text,
                          'prompt': prompt.text,
                          'events': entries(events),
                          'skills': entries(skills),
                          if (r['cronJobId'] != null)
                            'cronJobId': r['cronJobId'],
                        },
                      );
                      if (context.mounted) Navigator.pop(context, value);
                    } catch (e) {
                      if (mounted) setState(() => error = '$e');
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: Text(c.tr('保存', 'Save')),
          ),
        ],
      ),
    );
  }
}
