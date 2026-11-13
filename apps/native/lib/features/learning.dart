import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../ui/design.dart';

class LearningPage extends StatelessWidget {
  final NekodotClient client;
  final String botId;
  const LearningPage({super.key, required this.client, required this.botId});

  @override
  Widget build(BuildContext context) => AppPage(
    title: client.tr('学习历程', 'Learning journey'),
    body: MasterDetail(
      master: AsyncPane(
        load: () => client.rpc('learning.list', {'botId': botId}),
        builder: (context, data, reload) => PageList(
          children: [
            Text(
              client.tr(
                '来自此 Bot 的原生记忆与学习技能。更改按 Hermes 原生时机生效，不重建当前对话。',
                'Native memories and learned skills for this Bot. Changes follow Hermes timing; the current context is not rebuilt.',
              ),
            ),
            for (final line in (data['summary'] as List? ?? [])) Text('$line'),
            if (data['count'] == 0)
              Text(client.tr('暂无学习记录', 'No learning entries yet')),
            for (final bucket in objects(data['buckets'])) ...[
              const SizedBox(height: 16),
              Text(
                '${bucket['label']}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final entry in objects(bucket['nodes']))
                ListTile(
                  key: ValueKey('learning-${entry['id']}'),
                  leading: Icon(
                    '${entry['id']}'.startsWith('memory:')
                        ? Icons.psychology_outlined
                        : Icons.auto_awesome,
                  ),
                  title: Text('${entry['fullLabel'] ?? entry['label']}'),
                  subtitle: Text('${entry['meta'] ?? ''}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await pushPage(
                      context,
                      LearningEntryPage(
                        client: client,
                        botId: botId,
                        entryId: '${entry['id']}',
                      ),
                    );
                    reload();
                  },
                ),
            ],
          ],
        ),
      ),
    ),
  );
}

class LearningEntryPage extends StatefulWidget {
  final NekodotClient client;
  final String botId, entryId;
  const LearningEntryPage({
    super.key,
    required this.client,
    required this.botId,
    required this.entryId,
  });
  @override
  State<LearningEntryPage> createState() => _LearningEntryPageState();
}

class _LearningEntryPageState extends State<LearningEntryPage> {
  final content = TextEditingController();
  late final entry = widget.client
      .rpc('learning.get', {'botId': widget.botId, 'id': widget.entryId})
      .then((row) {
        content.text = '${row['content'] ?? ''}';
        return row;
      });
  bool editing = false, saving = false;
  String error = '';
  @override
  void dispose() {
    content.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      error = '';
    });
    try {
      await widget.client.rpc('learning.save', {
        'botId': widget.botId,
        'id': widget.entryId,
        'content': content.text,
      });
      if (mounted) {
        showNotice(context, widget.client.tr('已保存到 Hermes', 'Saved to Hermes'));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: widget.client.tr('学习记录', 'Learning entry'),
    body: FutureBuilder<Json>(
      future: entry,
      builder: (context, snapshot) {
        if (snapshot.hasError) return ErrorNotice('${snapshot.error}');
        if (!snapshot.hasData) {
          return const Center(child: ShiningText());
        }
        return PageList(
          children: [
            Text(
              '${snapshot.data!['label']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(widget.entryId, style: Theme.of(context).textTheme.bodySmall),
            if (widget.entryId.startsWith('memory:profile:'))
              Text(
                widget.client.tr(
                  '用户记忆由同账号所有 Bot 共享',
                  'User memory is shared by all Bots in this account',
                ),
              ),
            const SizedBox(height: 16),
            if (error.isNotEmpty) ErrorNotice(error),
            if (editing)
              TextField(
                key: const ValueKey('learning-editor'),
                controller: content,
                minLines: 12,
                maxLines: 30,
              )
            else
              MarkdownBody(data: content.text, selectable: true),
            const SizedBox(height: 16),
            if (saving) ShiningText(text: widget.client.tr('正在保存…', 'Saving…')),
            FilledButton(
              onPressed: saving
                  ? null
                  : editing
                  ? save
                  : () => setState(() => editing = true),
              child: Text(
                widget.client.tr(
                  editing ? '保存' : '编辑',
                  editing ? 'Save' : 'Edit',
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
