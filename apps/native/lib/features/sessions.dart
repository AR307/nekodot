import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../data/client.dart';
import '../ui/design.dart';

class BotSessionsPage extends StatelessWidget {
  final NekodotClient client;
  final String botId;
  const BotSessionsPage({super.key, required this.client, required this.botId});

  @override
  Widget build(BuildContext context) => AppPage(
    title: client.tr('Hermes 会话', 'Hermes sessions'),
    body: AsyncPane(
      load: () => client.rpc('sessions.list', {'botId': botId}),
      builder: (context, data, reload) => PageList(
        children: [
          Text(
            client.tr(
              '切换只改变后续消息的原生上下文，不会删除聊天记录或重跑任务。',
              'Switching changes the native context for future messages. It never deletes messages or replays tasks.',
            ),
          ),
          const SizedBox(height: 12),
          for (final row in objects(data['sessions']))
            ListTile(
              key: ValueKey('native-session-${row['session_id'] ?? row['id']}'),
              leading: Icon(
                (row['session_id'] ?? row['id']) == data['currentSessionId']
                    ? Icons.chat_bubble
                    : Icons.chat_bubble_outline,
              ),
              title: Text(
                '${row['title'] ?? ''}'.isEmpty
                    ? '${row['session_id'] ?? row['id']}'
                    : '${row['title']}',
              ),
              subtitle: Text(
                '${row['message_count'] ?? 0} ${client.tr('条消息', 'messages')}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => pushPage(
                context,
                _SessionHistory(client: client, botId: botId, row: row),
              ),
            ),
        ],
      ),
    ),
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
