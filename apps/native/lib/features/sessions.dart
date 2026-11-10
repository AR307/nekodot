import 'package:flutter/material.dart';

import '../ui/message_markdown.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../ui/design.dart';

class SessionHistoryPage extends StatefulWidget {
  final NekodotClient client;
  final String botId;
  final Json row;
  const SessionHistoryPage({
    super.key,
    required this.client,
    required this.botId,
    required this.row,
  });
  @override
  State<SessionHistoryPage> createState() => _SessionHistoryState();
}

class _SessionHistoryState extends State<SessionHistoryPage> {
  String get id => '${widget.row['session_id'] ?? widget.row['id']}';
  late final history = widget.client.rpc('sessions.history', {
    'botId': widget.botId,
    'sessionId': id,
  });
  @override
  Widget build(BuildContext context) => AppPage(
    title: widget.client.tr('原生会话记录', 'Native transcript'),
    body: FutureBuilder<Json>(
      future: history,
      builder: (context, snapshot) {
        if (snapshot.hasError) return ErrorNotice('${snapshot.error}');
        if (!snapshot.hasData) {
          return const Center(child: ShiningText());
        }
        final rows = objects(snapshot.data!['messages'])
            .where((row) => row['hidden'] != true);
        return PageList(
          children: [
            if (rows.isEmpty) Text(widget.client.tr('暂无消息', 'No messages yet')),
            for (final row in rows) ...[
              Text(
                '${row['role']}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              MessageMarkdown(data: '${row['text'] ?? ''}'),
              const Divider(height: 24),
            ],
          ],
        );
      },
    ),
  );
}
