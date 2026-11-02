import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../data/client.dart';
import '../ui/design.dart';

class BotSessionsPage extends StatefulWidget {
  final NekodotClient client;
  final String botId;
  const BotSessionsPage({super.key, required this.client, required this.botId});

  @override
  State<BotSessionsPage> createState() => _BotSessionsPageState();
}

class _BotSessionsPageState extends State<BotSessionsPage> {
  NekodotClient get c => widget.client;
  late Future<Json> sessions = load();
  String query = '', error = '';
  bool busy = false;
  Future<Json> load() => c.rpc('sessions.list', {'botId': widget.botId});

  Future<void> change(String command) async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final dm = c.node.conversations.firstWhere(
        (row) => row['kind'] == 'dm' && row['botId'] == widget.botId,
      );
      var op = await c.rpc('commands.execute', {
        'botId': widget.botId,
        'conversationId': dm['conversationId'],
        'command': command,
        'clientMsgId': uid(),
      });
      while (op['status'] == 'running' && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        op = await c.rpc('operations.get', {'operationId': op['operationId']});
      }
      if (op['status'] != 'done') throw RelayError('${op['detail']}');
      await c.loadMessages('${dm['conversationId']}');
      if (mounted) {
        showNotice(
          context,
          command.startsWith('/new')
              ? c.tr('已新建会话', 'Session created')
              : c.tr('已切换会话', 'Session switched'),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> create() async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) => _NewSessionDialog(client: c),
    );
    if (title != null && mounted) {
      await change(title.isEmpty ? '/new' : '/new $title');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bot = c.node.bots
        .where((b) => b['botId'] == widget.botId)
        .firstOrNull;
    return AppPage(
      title: c.tr('历史会话', 'Sessions'),
      actions: [
        IconButton(
          tooltip: c.tr('刷新', 'Refresh'),
          onPressed: busy
              ? null
              : () => setState(() {
                  sessions = load();
                }),
          icon: const Icon(Icons.refresh),
        ),
        TextButton.icon(
          key: const ValueKey('new-native-session'),
          onPressed: busy || !c.online ? null : create,
          icon: const Icon(Icons.add, size: 18),
          label: Text(c.tr('新建', 'New')),
        ),
      ],
      body: FutureBuilder<Json>(
        future: sessions,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return PageList(
              children: [
                ErrorNotice('${snapshot.error}'),
                TextButton(
                  onPressed: () => setState(() {
                    sessions = load();
                  }),
                  child: Text(c.tr('重试', 'Retry')),
                ),
              ],
            );
          }
          if (!snapshot.hasData) return const Center(child: Breathing());
          final data = snapshot.data!;
          final rows = objects(data['sessions']);
          final current = rows
              .where(
                (r) => (r['session_id'] ?? r['id']) == data['currentSessionId'],
              )
              .firstOrNull;
          final filtered = rows.where(
            (r) => '${r['title']} ${r['session_id'] ?? r['id']}'
                .toLowerCase()
                .contains(query.toLowerCase()),
          );
          return PageList(
            children: [
              if (busy) const LinearProgressIndicator(),
              if (error.isNotEmpty) ErrorNotice(error),
              Text(
                '${bot?['displayName'] ?? 'Bot'} · ${c.tr('独立的 Hermes profile', 'Own Hermes profile')}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                c.tr(
                  '点击会话预览历史，或切换后继续聊天。新建会话保留旧记录；Bot 的记忆和技能不变。',
                  'Preview a transcript or switch to continue chatting. New sessions keep old records, Bot memory and skills.',
                ),
              ),
              if (current != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${c.tr('当前会话', 'Current session')}: ${'${current['title'] ?? ''}'.isEmpty ? data['currentSessionId'] : current['title']}',
                  key: const ValueKey('current-native-session'),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('native-session-search'),
                onChanged: (value) => setState(() => query = value),
                decoration: InputDecoration(
                  hintText: c.tr('搜索会话名称或 ID', 'Search title or ID'),
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              if (filtered.isEmpty)
                Text(c.tr('没有匹配的会话', 'No matching sessions')),
              for (final row in filtered)
                ListTile(
                  key: ValueKey(
                    'native-session-${row['session_id'] ?? row['id']}',
                  ),
                  selected:
                      (row['session_id'] ?? row['id']) ==
                      data['currentSessionId'],
                  leading: Icon(
                    (row['session_id'] ?? row['id']) == data['currentSessionId']
                        ? Icons.chat_bubble
                        : Icons.chat_bubble_outline,
                  ),
                  title: Text(
                    '${row['title'] ?? ''}'.isEmpty
                        ? '${row['session_id'] ?? row['id']}'
                        : '${row['title']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${row['message_count'] ?? 0} ${c.tr('条消息', 'messages')}${row['running'] == true ? ' · ${c.tr('运行中', 'Running')}' : ''}',
                  ),
                  trailing:
                      (row['session_id'] ?? row['id']) ==
                          data['currentSessionId']
                      ? Text(
                          c.tr('当前', 'Current'),
                          style: Theme.of(context).textTheme.labelMedium,
                        )
                      : TextButton(
                          key: ValueKey(
                            'switch-session-${row['session_id'] ?? row['id']}',
                          ),
                          onPressed: busy || !c.online
                              ? null
                              : () => change(
                                  '/resume ${row['session_id'] ?? row['id']}',
                                ),
                          child: Text(c.tr('切换', 'Switch')),
                        ),
                  onTap: busy
                      ? null
                      : () async {
                          await pushPage(
                            context,
                            _SessionHistory(
                              client: c,
                              botId: widget.botId,
                              row: row,
                            ),
                          );
                          if (mounted) {
                            setState(() {
                              sessions = load();
                            });
                          }
                        },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _NewSessionDialog extends StatefulWidget {
  final NekodotClient client;
  const _NewSessionDialog({required this.client});
  @override
  State<_NewSessionDialog> createState() => _NewSessionDialogState();
}

class _NewSessionDialogState extends State<_NewSessionDialog> {
  final title = TextEditingController();
  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.client.tr('新建会话', 'New session')),
    content: TextField(
      key: const ValueKey('native-session-title'),
      controller: title,
      autofocus: true,
      maxLength: 120,
      decoration: InputDecoration(
        labelText: widget.client.tr('会话名称（可选）', 'Title (optional)'),
      ),
      onSubmitted: (value) => Navigator.pop(context, value.trim()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.client.tr('取消', 'Cancel')),
      ),
      FilledButton(
        key: const ValueKey('create-native-session'),
        onPressed: () => Navigator.pop(context, title.text.trim()),
        child: Text(widget.client.tr('创建', 'Create')),
      ),
    ],
  );
}

class _SessionHistory extends StatefulWidget {
  final NekodotClient client;
  final String botId;
  final Json row;
  const _SessionHistory({
    required this.client,
    required this.botId,
    required this.row,
  });
  @override
  State<_SessionHistory> createState() => _SessionHistoryState();
}

class _SessionHistoryState extends State<_SessionHistory> {
  bool busy = false;
  String error = '';
  String get id => '${widget.row['session_id'] ?? widget.row['id']}';
  late final history = widget.client.rpc('sessions.history', {
    'botId': widget.botId,
    'sessionId': id,
  });
  Future<void> resume() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final c = widget.client;
      final dm = c.node.conversations.firstWhere(
        (row) => row['kind'] == 'dm' && row['botId'] == widget.botId,
      );
      var op = await c.rpc('commands.execute', {
        'botId': widget.botId,
        'conversationId': dm['conversationId'],
        'command': '/resume $id',
        'clientMsgId': uid(),
      });
      while (op['status'] == 'running' && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        op = await c.rpc('operations.get', {'operationId': op['operationId']});
      }
      if (op['status'] != 'done') {
        throw RelayError('${op['detail']}');
      }
      await c.loadMessages('${dm['conversationId']}');
      if (mounted) {
        showNotice(context, c.tr('已切换原生会话', 'Native session resumed'));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: widget.client.tr('原生会话记录', 'Native transcript'),
    actions: [
      TextButton(
        onPressed: busy ? null : resume,
        child: Text(widget.client.tr('继续此会话', 'Resume here')),
      ),
    ],
    body: FutureBuilder<Json>(
      future: history,
      builder: (context, snapshot) {
        if (snapshot.hasError) return ErrorNotice('${snapshot.error}');
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = objects(snapshot.data!['messages'])
            .where((row) => row['hidden'] != true);
        return PageList(
          children: [
            if (busy) const LinearProgressIndicator(),
            if (error.isNotEmpty) ErrorNotice(error),
            if (rows.isEmpty) Text(widget.client.tr('暂无消息', 'No messages yet')),
            for (final row in rows) ...[
              Text(
                '${row['role']}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              MarkdownBody(data: '${row['text'] ?? ''}', selectable: true),
              const Divider(height: 24),
            ],
          ],
        );
      },
    ),
  );
}
