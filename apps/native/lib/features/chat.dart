import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/client.dart';
import '../ui/design.dart';
import '../screen/viewer.dart';
import 'bot_details.dart';
import 'bot_editor.dart';
import 'files.dart';

class ChatPage extends StatefulWidget {
  final NekodotClient client;
  final String conversationId;
  final bool embedded;
  const ChatPage({
    super.key,
    required this.client,
    required this.conversationId,
    this.embedded = false,
  });
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with RouteAware {
  final input = TextEditingController(), scroll = ScrollController();
  bool sending = false;
  String error = '', notice = '';
  String? pendingId, pendingText;
  NekodotClient get c => widget.client;
  String get id => widget.conversationId;
  String get draftKey => '${c.selectedNodeId}:$id';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    nativeRoutes.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void didPushNext() {
    if (c.visibleConversation == id) c.visibleConversation = null;
  }

  @override
  void didPopNext() {
    c.visibleConversation = id;
  }

  @override
  void initState() {
    super.initState();
    input.text = c.drafts[draftKey] ?? '';
    input.addListener(() {
      c.drafts[draftKey] = input.text;
    });
    c.visibleConversation = id;
    unawaited(
      c.loadMessages(id).catchError((Object e) {
        if (mounted) setState(() => error = '$e');
      }),
    );
  }

  @override
  void dispose() {
    nativeRoutes.unsubscribe(this);
    if (c.visibleConversation == id) c.visibleConversation = null;
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || sending) return;
    final running =
        c.node.activities[id]?['state'] != null &&
        c.node.activities[id]?['state'] != 'idle';
    setState(() {
      sending = true;
      error = '';
      notice = '';
    });
    if (pendingText != text) {
      pendingText = text;
      pendingId = uid();
    }
    try {
      await c.rpc('messages.send', {
        'conversationId': id,
        'text': text,
        'clientMsgId': pendingId,
      });
      if (!mounted) return;
      input.clear();
      pendingId = null;
      pendingText = null;
      setState(
        () => notice = running
            ? c.tr('已向当前回合补充指令', 'Instruction added to this run')
            : '',
      );
      await c.loadMessages(id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.jumpTo(0);
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> stop() async {
    try {
      await c.rpc('runs.stop', {'conversationId': id});
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, child) {
      final conversation = c.node.conversations
          .where((x) => x['conversationId'] == id)
          .firstOrNull;
      if (conversation == null) return const SizedBox.shrink();
      final group = conversation['kind'] == 'group'
          ? c.node.groups
                .where((x) => x['groupId'] == conversation['groupId'])
                .firstOrNull
          : null;
      final activity = c.node.activities[id] ?? {'state': 'idle'};
      final state = activity['state'],
          running = state != 'idle',
          waiting = state == 'waiting_approval' || state == 'waiting_question';
      final members = c.node.bots
          .where(
            (b) => group == null
                ? b['botId'] == conversation['botId']
                : (group['botIds'] as List).contains(b['botId']),
          )
          .toList();
      final messages = c.node.messages[id] ?? [];
      final lastBot = messages
          .where((m) => m['author']['type'] == 'bot')
          .lastOrNull?['author']['id'];
      final bot =
          members
              .where(
                (b) =>
                    b['botId'] ==
                    (activity['botId'] ??
                        lastBot ??
                        group?['leadBotId'] ??
                        conversation['botId']),
              )
              .firstOrNull ??
          members.firstOrNull;
      final title =
          group?['name'] as String? ?? bot?['displayName'] as String? ?? 'Bot';
      final status = !c.online
          ? c.tr('电脑离线', 'Computer offline')
          : activity['connection'] == 'reconnecting'
          ? c.tr('输出连接恢复中，未重跑任务', 'Reconnecting the same run')
          : switch (state) {
              'thinking' => c.tr('正在回复', 'Replying'),
              'tool' => c.tr('运行工具', 'Using tools'),
              'waiting_approval' => c.tr('等待审批', 'Waiting for approval'),
              'waiting_question' => c.tr('等待回答', 'Waiting for your answer'),
              _ =>
                group == null
                    ? '@${bot?['handle'] ?? ''}'
                    : c.tr(
                        '${members.length} 位成员',
                        '${members.length} members',
                      ),
            };
      final header = AppBar(
        automaticallyImplyLeading: !widget.embedded,
        titleSpacing: widget.embedded ? 20 : 0,
        title: InkWell(
          onTap: () {
            if (group != null) {
              pushPage(
                context,
                BotEditor(client: c, group: true, existing: group),
              );
            } else if (bot != null) {
              pushPage(context, BotDetails(client: c, bot: bot));
            }
          },
          child: Row(
            children: [
              if (bot != null)
                CatAvatar(color: '${bot['avatar']['color']}', size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    Text(
                      status,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: c.tr('屏幕', 'Screen'),
            onPressed: bot == null
                ? null
                : () => pushPage(
                    context,
                    ScreenPage(client: c, bot: bot, members: members),
                  ),
            icon: const Icon(Icons.desktop_windows_outlined),
          ),
          IconButton(
            tooltip: c.tr('详情', 'Details'),
            onPressed: bot == null
                ? null
                : () => pushPage(
                    context,
                    group == null
                        ? BotDetails(client: c, bot: bot)
                        : BotEditor(client: c, group: true, existing: group),
                  ),
            icon: const Icon(Icons.info_outline),
          ),
          const SizedBox(width: 10),
        ],
      );
      return Scaffold(
        appBar: header,
        body: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: scroll,
                reverse: true,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
                itemCount: messages.length + 1,
                itemBuilder: (context, index) {
                  if (index == messages.length) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: messages.length >= 50
                            ? TextButton(
                                onPressed: () async {
                                  try {
                                    await c.loadMessages(
                                      id,
                                      before: messages.first['seq'] as int,
                                    );
                                  } catch (e) {
                                    if (mounted) setState(() => error = '$e');
                                  }
                                },
                                child: Text(
                                  c.tr('加载更早消息', 'Load earlier messages'),
                                ),
                              )
                            : Column(
                                children: [
                                  if (bot != null)
                                    CatAvatar(
                                      size: 56,
                                      color: '${bot['avatar']['color']}',
                                    ),
                                  const SizedBox(height: 12),
                                  Text(
                                    title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    group == null
                                        ? '${bot?['role'] ?? ''}'
                                        : c.tr(
                                            '使用 @ 指定成员，或由主答开始。',
                                            'Mention members, or let the lead begin.',
                                          ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                      ),
                    );
                  }
                  final m = messages[messages.length - 1 - index],
                      author = members
                          .where((b) => b['botId'] == m['author']['id'])
                          .firstOrNull;
                  return Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: MessageTile(
                        client: c,
                        message: m,
                        bot: author,
                        onRetry: (text) {
                          input.text = text;
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            if (running)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                color: accent.withValues(alpha: .08),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$status${activity['chain'] == null ? '' : ' · ${activity['chain']['count']}/${activity['chain']['max']}'}',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: c.online ? stop : null,
                      icon: const Icon(Icons.stop_rounded),
                      label: Text(c.tr('停止', 'Stop')),
                    ),
                  ],
                ),
              ),
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ErrorNotice(error),
              ),
            if (notice.isNotEmpty)
              Padding(padding: const EdgeInsets.all(8), child: Text(notice)),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  children: [
                    if (group != null && input.text.contains('@'))
                      SizedBox(
                        height: 42,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: members
                              .map(
                                (b) => TextButton.icon(
                                  onPressed: () {
                                    final start = input.text.lastIndexOf('@');
                                    input.text =
                                        '${input.text.substring(0, start)}@${b['handle']} ';
                                    setState(() {});
                                  },
                                  icon: CatAvatar(
                                    color: '${b['avatar']['color']}',
                                    size: 22,
                                  ),
                                  label: Text('${b['displayName']}'),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: CallbackShortcuts(
                            bindings: {
                              const SingleActivator(
                                LogicalKeyboardKey.enter,
                                control: true,
                              ): () {
                                if (!waiting && c.online) send();
                              },
                            },
                            child: TextField(
                              key: const ValueKey('chat-input'),
                              controller: input,
                              minLines: 1,
                              maxLines: 7,
                              textCapitalization: TextCapitalization.sentences,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: waiting
                                    ? c.tr(
                                        '先回答或审批，草稿会保留',
                                        'Answer or approve first. Drafts are kept.',
                                      )
                                    : running
                                    ? c.tr(
                                        '补充当前指令…',
                                        'Add instruction to this run…',
                                      )
                                    : c.tr('发消息…', 'Message…'),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filled(
                          tooltip: c.tr('发送', 'Send'),
                          onPressed:
                              !c.online ||
                                  waiting ||
                                  sending ||
                                  input.text.trim().isEmpty
                              ? null
                              : send,
                          icon: const Icon(Icons.arrow_upward_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class MessageTile extends StatelessWidget {
  final NekodotClient client;
  final Json message;
  final Json? bot;
  final ValueChanged<String> onRetry;
  const MessageTile({
    super.key,
    required this.client,
    required this.message,
    this.bot,
    required this.onRetry,
  });
  @override
  Widget build(BuildContext context) {
    final c = client,
        m = message,
        body = object(m['content']),
        user = m['author']['type'] == 'user',
        kind = m['kind'];
    if (kind == 'system') {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              '${body['text']}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (body['retryText'] != null)
              TextButton(
                onPressed: () => onRetry(body['retryText'] as String),
                child: Text(c.tr('重新编辑', 'Edit & resend')),
              ),
          ],
        ),
      );
    }
    Widget content;
    if (kind == 'tool') {
      content = Card(
        child: ExpansionTile(
          leading: Icon(
            m['status'] == 'streaming' ? Icons.hourglass_top : Icons.terminal,
          ),
          title: Text('${body['tool']}'),
          subtitle: Text(
            m['status'] == 'streaming'
                ? c.tr('运行中', 'Running')
                : '${body['durationMs'] ?? 0} ms',
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                '${body['preview'] ?? ''}\n${body['resultPreview'] ?? ''}',
              ),
            ),
          ],
        ),
      );
    } else if (kind == 'question' || kind == 'approval') {
      content = ControlCard(client: c, message: m);
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarkdownBody(
            data:
                '${body['text'] ?? ''}${m['status'] == 'streaming' ? ' ▍' : ''}',
            selectable: true,
            onTapLink: (text, href, title) {
              if (href != null) {
                launchUrl(
                  Uri.parse(href),
                  mode: LaunchMode.externalApplication,
                );
              }
            },
          ),
          if (body['files'] is List)
            for (final fileId in body['files'] as List)
              FileCard(
                client: c,
                fileId: '$fileId',
                botId: bot?['botId'] as String?,
                messageId: m['messageId'] as String,
              ),
          if (m['status'] == 'failed' || m['status'] == 'cancelled')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                m['status'] == 'cancelled'
                    ? c.tr('已停止', 'Stopped')
                    : body['failureReason'] as String? ??
                          c.tr(
                            '输出中断 · 请查看错误或手动继续',
                            'Interrupted · Check the error or continue manually',
                          ),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: user
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!user) ...[
            CatAvatar(
              color: bot?['avatar']['color'] as String? ?? '#8C8376',
              size: 30,
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Container(
              padding: user
                  ? const EdgeInsets.symmetric(horizontal: 18, vertical: 13)
                  : const EdgeInsets.only(top: 3),
              decoration: user
                  ? BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(18),
                    )
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!user && bot != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Text(
                        '${bot!['displayName']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  content,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ControlCard extends StatefulWidget {
  final NekodotClient client;
  final Json message;
  const ControlCard({super.key, required this.client, required this.message});
  @override
  State<ControlCard> createState() => _ControlCardState();
}

class _ControlCardState extends State<ControlCard> {
  final answer = TextEditingController();
  final selected = <String>{};
  bool busy = false;
  String error = '';
  @override
  void dispose() {
    answer.dispose();
    super.dispose();
  }

  Future<void> respond(String value) async {
    setState(() {
      busy = true;
      error = '';
    });
    final question = widget.message['kind'] == 'question';
    try {
      await widget.client.rpc(
        question ? 'questions.respond' : 'approvals.respond',
        {
          'messageId': widget.message['messageId'],
          question ? 'answer' : 'choice': value,
        },
      );
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client,
        m = widget.message,
        data = object(m['content']),
        question = m['kind'] == 'question',
        pending = m['status'] == 'streaming',
        multi = data['multiSelect'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  question ? Icons.help_outline : Icons.shield_outlined,
                  color: accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    question
                        ? c.tr('需要你的回答', 'Your answer is needed')
                        : c.tr('需要你的批准', 'Your approval is needed'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText('${data[question ? 'question' : 'prompt']}'),
            if (data['command'] != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: SelectableText(
                  '${data['command']}',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            if (!pending)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '${data['answer'] ?? data['choice'] ?? m['status']}',
                ),
              ),
            if (pending && question) ...[
              for (final option in data['choices'] as List? ?? [])
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('$option'),
                  value: selected.contains('$option'),
                  onChanged: busy
                      ? null
                      : (value) => setState(() {
                          if (!multi) selected.clear();
                          if (value == true) {
                            selected.add('$option');
                          } else {
                            selected.remove('$option');
                          }
                        }),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: answer,
                minLines: 1,
                maxLines: 4,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: c.tr('或输入你的回答…', 'Or write your answer…'),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed:
                    !c.online ||
                        busy ||
                        (selected.isEmpty && answer.text.trim().isEmpty)
                    ? null
                    : () => respond(
                        [
                          ...selected,
                          if (answer.text.trim().isNotEmpty) answer.text.trim(),
                        ].join('\n'),
                      ),
                child: Text(c.tr('提交回答', 'Submit answer')),
              ),
            ],
            if (pending && !question)
              Wrap(
                spacing: 8,
                children: [
                  for (final choice
                      in data['choices'] as List? ?? ['once', 'deny'])
                    OutlinedButton(
                      onPressed: !c.online || busy
                          ? null
                          : () => respond('$choice'),
                      child: Text(switch (choice) {
                        'once' => c.tr('允许一次', 'Allow once'),
                        'session' => c.tr('本会话允许', 'Allow session'),
                        'always' => c.tr('总是允许', 'Always allow'),
                        _ => c.tr('拒绝', 'Deny'),
                      }),
                    ),
                ],
              ),
            ErrorNotice(error),
          ],
        ),
      ),
    );
  }
}
