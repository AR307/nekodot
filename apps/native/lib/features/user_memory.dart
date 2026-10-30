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
    final small = Theme.of(context).textTheme.bodySmall;
    final label = Theme.of(context).textTheme.titleSmall;
    return AppPage(
      title: c.tr('共享用户记忆', 'Shared user memory'),
      actions: [
        IconButton(
          tooltip: c.tr('刷新', 'Refresh'),
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: PageList(
        children: [
          if (imports.isNotEmpty) ...[
            SectionLabel(c.tr('待确认', 'To review')),
            PanelGroup(
              children: [
                for (final item in imports)
                  ExpansionTile(
                    title: Text('${item['name']} · ${item['botId']}'),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [SelectableText('${item['content']}')],
                  ),
              ],
            ),
          ],
          if (conflicts.isNotEmpty) ...[
            SectionLabel(c.tr('修改冲突', 'Conflicts')),
            for (final item in conflicts)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Panel(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item['name']} · ${item['botId']}',
                          style: small,
                        ),
                        const SizedBox(height: 10),
                        Text(c.tr('修改前', 'Before'), style: label),
                        SelectableText('${item['base']}'),
                        const SizedBox(height: 10),
                        Text(c.tr('当前', 'Current'), style: label),
                        SelectableText('${item['current']}'),
                        const SizedBox(height: 10),
                        Text(c.tr('另一份', 'Incoming'), style: label),
                        SelectableText('${item['incoming']}'),
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            tooltip: c.tr(
                              '将另一份内容也加入草稿',
                              'Add incoming content to draft too',
                            ),
                            onPressed: () {
                              text.text = combine([
                                text.text,
                                '${item['incoming']}',
                              ]);
                              edited = true;
                            },
                            icon: const Icon(Icons.playlist_add),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
          if (view == null && error.isEmpty)
            const Center(
              child: Padding(padding: EdgeInsets.all(16), child: Breathing()),
            ),
          const SizedBox(height: 8),
          LabeledField(
            label: 'USER.md',
            child: TextField(
              key: const ValueKey('shared-user-memory-editor'),
              controller: text,
              minLines: 8,
              maxLines: 24,
              onChanged: (_) => edited = true,
              decoration: const InputDecoration(),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: busy || !c.online || view?['connected'] != true
                  ? null
                  : save,
              child: busy ? const Breathing() : Text(c.tr('保存', 'Save')),
            ),
          ),
          ErrorNotice(
            error.isNotEmpty
                ? error
                : view?['error'] != null
                ? '${view!['error']}'
                : !c.online || view?['connected'] == false
                ? c.tr('未连接', 'Disconnected')
                : '',
          ),
          if (objects(state?['imports']).any((v) => v['reviewed'] == true) ||
              objects(state?['conflicts']).any((v) => v['resolved'] == true))
            ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 6),
              title: Text(c.tr('历史', 'History'), style: label),
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
