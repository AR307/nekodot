import 'package:flutter/material.dart';

import '../data/client.dart';
import '../ui/design.dart';

class SharedUserMemoryPage extends StatefulWidget {
  final NekodotClient client;
  const SharedUserMemoryPage({super.key, required this.client});
  @override
  State<SharedUserMemoryPage> createState() => _SharedUserMemoryPageState();
}

class _SharedUserMemoryPageState extends State<SharedUserMemoryPage> {
  final text = TextEditingController();
  Json? view;
  String error = '';
  bool busy = false;
  bool edited = false;
  late bool wasOnline;
  @override
  void initState() {
    super.initState();
    wasOnline = widget.client.online;
    widget.client.addListener(connectionChanged);
    load();
  }

  void connectionChanged() {
    final online = widget.client.online;
    if (online == wasOnline) return;
    wasOnline = online;
    setState(() {});
    if (online) load();
  }

  @override
  void dispose() {
    widget.client.removeListener(connectionChanged);
    text.dispose();
    super.dispose();
  }

  Json? get state => view?['shared'] as Json?;
  List<Json> get imports =>
      objects(state?['imports']).where((v) => v['reviewed'] != true).toList();
  List<Json> get conflicts =>
      objects(state?['conflicts']).where((v) => v['resolved'] != true).toList();
  String combine(Iterable<String> values) => values
      .expand((v) => v.split('\n§\n'))
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toSet()
      .join('\n§\n');
  Future<void> load() async {
    try {
      final result = await widget.client.rpc('memory.user.get');
      if (!mounted) return;
      setState(() {
        view = result;
        error = '';
        if (!edited) {
          text.text = combine([
            '${state?['content'] ?? ''}',
            ...imports.map((v) => '${v['content']}'),
          ]);
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> save() async {
    if (state == null) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final result = await widget.client.rpc('memory.user.save', {
        'revision': state!['revision'],
        'content': text.text,
        'reviewedImports': imports.map((v) => v['id']).toList(),
        'reviewedConflicts': conflicts.map((v) => v['id']).toList(),
      });
      if (!mounted) return;
      setState(() {
        view = result;
        edited = false;
        text.text = '${state?['content'] ?? ''}';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.client.tr('记忆已保存', 'Memory saved'))),
      );
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    return Scaffold(
      appBar: AppBar(
        title: Text(c.tr('共享用户记忆', 'Shared user memory')),
        actions: [
          IconButton(
            tooltip: c.tr('刷新', 'Refresh'),
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            c.tr(
              '同账号所有 Bot 共享 USER.md。自身设定、任务经验和聊天仍独立；按 Hermes 原生时机生效，不重建运行中的提示词。',
              'USER.md is shared with every Bot on your account. Identity, task memory and chat remain separate. Hermes decides when changes take effect; live prompts are not rebuilt.',
            ),
          ),
          if (state != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                c.tr(
                  '账号修订 ${state!['revision']}',
                  'Account revision ${state!['revision']}',
                ),
              ),
            ),
          if (imports.isNotEmpty) ...[
            Text(
              c.tr('确认已有用户记忆', 'Review existing user memory'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              c.tr(
                '编辑后确认共享内容；原始内容保留，不会静默覆盖。',
                'Edit and confirm the shared document. Original content is kept, not silently overwritten.',
              ),
            ),
            for (final item in imports)
              Card(
                child: ExpansionTile(
                  title: Text('${item['name']} · ${item['botId']}'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText('${item['content']}'),
                    ),
                  ],
                ),
              ),
          ],
          if (conflicts.isNotEmpty) ...[
            Text(
              c.tr('同一条记忆有不同修改', 'Conflicting changes to one memory entry'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              c.tr(
                '双方内容已保留。编辑下方文档后确认；未采用的版本仍保存在冲突记录中。',
                'Both versions are kept. Edit the shared document below and confirm. Unused versions remain in the conflict record.',
              ),
            ),
            for (final item in conflicts)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${item['name']} · ${item['botId']}'),
                      Text(c.tr('修改前', 'Before changes')),
                      SelectableText('${item['base']}'),
                      Text(c.tr('当前共享版本', 'Current shared version')),
                      SelectableText('${item['current']}'),
                      Text(c.tr('另一份修改', 'Incoming version')),
                      SelectableText('${item['incoming']}'),
                      TextButton(
                        onPressed: () {
                          text.text = combine([
                            text.text,
                            '${item['incoming']}',
                          ]);
                          edited = true;
                        },
                        child: Text(
                          c.tr(
                            '将另一份内容也加入草稿',
                            'Add incoming content to draft too',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 16),
          if (view == null && error.isEmpty)
            const Center(child: CircularProgressIndicator()),
          TextField(
            key: const ValueKey('shared-user-memory-editor'),
            controller: text,
            minLines: 8,
            maxLines: 24,
            onChanged: (_) => edited = true,
            decoration: const InputDecoration(labelText: 'USER.md'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy || !c.online || view?['connected'] != true
                ? null
                : save,
            child: Text(
              busy
                  ? c.tr('保存中…', 'Saving…')
                  : imports.isNotEmpty ||
                        conflicts.isNotEmpty ||
                        state?['initialized'] != true
                  ? c.tr('保存并确认以上内容', 'Save and confirm the content above')
                  : c.tr('保存', 'Save'),
            ),
          ),
          if (!c.online || view?['connected'] == false)
            Text(
              c.tr(
                '共享记忆连接不可用；本机文件与草稿保留，恢复连接后同步。',
                'Shared memory is disconnected. Local files and drafts are kept and synchronize after reconnecting.',
              ),
            ),
          ErrorNotice(error.isNotEmpty ? error : '${view?['error'] ?? ''}'),
          if (objects(state?['imports']).any((v) => v['reviewed'] == true) ||
              objects(state?['conflicts']).any((v) => v['resolved'] == true))
            ExpansionTile(
              title: Text(
                c.tr('已保留的原件与处理记录', 'Preserved originals and decisions'),
              ),
              children: [
                for (final item in objects(
                  state?['imports'],
                ).where((v) => v['reviewed'] == true))
                  ListTile(
                    title: Text('${item['name']} · USER.md'),
                    subtitle: SelectableText('${item['content']}'),
                  ),
                for (final item in objects(
                  state?['conflicts'],
                ).where((v) => v['resolved'] == true))
                  ListTile(
                    title: Text('${item['name']}'),
                    subtitle: SelectableText(
                      '${item['base']}\n→ ${item['current']}\n↔ ${item['incoming']}',
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
