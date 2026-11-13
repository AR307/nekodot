import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../ui/design.dart';
import 'plugin_catalog.dart';

class McpBody extends StatefulWidget {
  final NekodotClient client;
  const McpBody({super.key, required this.client});
  @override
  State<McpBody> createState() => _McpBodyState();
}

class _McpBodyState extends State<McpBody> {
  final search = TextEditingController(), scroll = ScrollController();
  String? botId;
  String query = '';
  int revision = 0;
  NekodotClient get c => widget.client;
  @override
  void dispose() {
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bots = c.node.bots.where((bot) => bot['archived'] != true).toList();
    if (!bots.any((bot) => bot['botId'] == botId)) {
      botId = bots.firstOrNull?['botId'] as String?;
    }
    final bot = bots.where((row) => row['botId'] == botId).firstOrNull;
    final selector = ActionMenu<String>(
      key: const ValueKey('mcp-bot-menu'),
      tooltip: 'Dot',
      items: [
        for (final row in bots)
          MenuAction(
            key: ValueKey('mcp-bot-${row['botId']}'),
            value: '${row['botId']}',
            label: '${row['displayName']}',
            leading: CatAvatar.of(row, size: 24),
            selected: row['botId'] == botId,
          ),
      ],
      onSelected: (id) => setState(() => botId = id),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (bot != null) CatAvatar.of(bot, size: 24),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${bot?['displayName'] ?? 'Dot'}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Symbols.expand_more, size: 18),
          ],
        ),
      ),
    );
    Widget catalog(List<Json> servers, {bool loading = false, Object? error}) {
      final filtered = servers
          .where(
            (row) => '${row['name']} ${row['url'] ?? row['command'] ?? ''}'
                .toLowerCase()
                .contains(query),
          )
          .toList();
      return PluginCatalog(
        scroll: scroll,
        loading: loading,
        count: filtered.length,
        search: TextField(
          key: const ValueKey('mcp-search'),
          controller: search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Symbols.search, size: 20),
            hintText: c.tr('搜索', 'Search'),
          ),
          onChanged: (value) => setState(() => query = value.toLowerCase()),
        ),
        actions: [
          IconAction(
            icon: Symbols.refresh,
            tooltip: c.tr('刷新', 'Refresh'),
            onPressed: loading ? null : () => setState(() => revision++),
          ),
          IconAction(
            key: const ValueKey('mcp-add'),
            icon: Symbols.add,
            tooltip: c.tr('添加 MCP', 'Add MCP'),
            onPressed: botId == null || !c.online
                ? null
                : () async {
                    await pushPage(context, McpAddPage(client: c, bot: bot!));
                    if (mounted) setState(() => revision++);
                  },
          ),
        ],
        filters: Align(alignment: Alignment.centerLeft, child: selector),
        notice: error == null
            ? null
            : ErrorNotice(c.tr('请求失败，请重试', 'Request failed. Try again.')),
        empty: error == null
            ? Text(
                c.tr('未配置', 'Not configured'),
                style: Theme.of(context).textTheme.bodySmall,
              )
            : null,
        itemBuilder: (index, wide) {
          final server = filtered[index];
          final enabled = server['enabled'] == true;
          return PluginTile(
            key: ValueKey('mcp-server-${server['name']}'),
            wide: wide,
            icon: const Icon(Symbols.hub),
            name: '${server['name']}',
            description: '${server['url'] ?? server['command'] ?? ''}',
            status: Text(
              '${server['transport']}  ${enabled ? c.tr('已配置', 'Configured') : c.tr('已停用', 'Disabled')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            onTap: () async {
              await pushPage(
                context,
                McpServerPage(client: c, bot: bot!, server: server),
              );
              if (mounted) setState(() => revision++);
            },
          );
        },
      );
    }

    if (botId == null) return catalog([]);
    return _McpList(
      key: ValueKey('$botId:$revision'),
      client: c,
      botId: botId!,
      builder: catalog,
    );
  }
}

class _McpList extends StatefulWidget {
  final NekodotClient client;
  final String botId;
  final Widget Function(List<Json>, {bool loading, Object? error}) builder;
  const _McpList({
    super.key,
    required this.client,
    required this.botId,
    required this.builder,
  });
  @override
  State<_McpList> createState() => _McpListState();
}

class _McpListState extends State<_McpList> {
  late final future = widget.client.rpc('mcp.list', {'botId': widget.botId});
  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
    future: future,
    builder: (context, result) => widget.builder(
      objects(result.data?['servers']),
      loading: result.connectionState == ConnectionState.waiting,
      error: result.error,
    ),
  );
}

class McpServerPage extends StatefulWidget {
  final NekodotClient client;
  final Json bot, server;
  const McpServerPage({
    super.key,
    required this.client,
    required this.bot,
    required this.server,
  });
  @override
  State<McpServerPage> createState() => _McpServerPageState();
}

class _McpServerPageState extends State<McpServerPage> {
  late bool enabled = widget.server['enabled'] == true;
  bool busy = false;
  Json? probe;
  String error = '';
  NekodotClient get c => widget.client;
  Future<void> run({bool? enable}) async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final result = await c.rpc(enable == null ? 'mcp.test' : 'mcp.toggle', {
        'botId': widget.bot['botId'],
        'name': widget.server['name'],
        'enabled': ?enable,
      });
      if (mounted) {
        setState(() {
          if (enable == null) {
            probe = result;
          } else {
            enabled = enable;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = c.tr('请求失败，请重试', 'Request failed. Try again.'));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final server = widget.server;
    final arguments = (server['args'] as List? ?? []).cast<String>();
    final environment = (server['env'] as List? ?? []).cast<String>();
    return AppPage(
      title: '${server['name']}',
      body: PageList(
        maxWidth: 720,
        children: [
          Row(
            children: [
              CatAvatar.of(widget.bot, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${widget.bot['displayName']}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${server['transport']}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 24),
          SelectableText(
            '${server['url'] ?? server['command'] ?? ''}',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (arguments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SelectableText(
                arguments.join('\n'),
                style: const TextStyle(fontFamily: monoFont),
              ),
            ),
          if (server['source'] == 'plugin') ...[
            const SizedBox(height: 16),
            Text('${c.tr('插件', 'Plugins')}: ${server['plugin']}'),
          ] else
            SwitchListTile(
              key: const ValueKey('mcp-enabled'),
              contentPadding: EdgeInsets.zero,
              title: Text(c.tr('启用', 'Enable')),
              value: enabled,
              onChanged: busy || !c.online
                  ? null
                  : (value) => run(enable: value),
            ),
          if (environment.isNotEmpty) ...[
            SectionLabel(c.tr('环境变量', 'Environment variables')),
            Text(
              environment.join('\n'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const ValueKey('mcp-test'),
              onPressed: busy || !c.online ? null : () => run(),
              icon: const Icon(Symbols.play_arrow, size: 18),
              label: Text(c.tr('测试连接', 'Test connection')),
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ErrorNotice(error),
          if (probe != null) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Icon(
                  probe!['ok'] == true ? Symbols.check_circle : Symbols.error,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    probe!['ok'] == true
                        ? c.tr('连接测试通过', 'Connection test passed')
                        : c.tr('连接测试失败', 'Connection test failed'),
                  ),
                ),
              ],
            ),
            if (probe!['error'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SelectableText(
                  '${probe!['error']}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (objects(probe!['tools']).isNotEmpty)
              SectionLabel(c.tr('可用工具', 'Available tools')),
            for (final tool in objects(probe!['tools']))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${tool['name']}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text('${tool['description']}'),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class McpAddPage extends StatefulWidget {
  final NekodotClient client;
  final Json bot;
  const McpAddPage({super.key, required this.client, required this.bot});
  @override
  State<McpAddPage> createState() => _McpAddPageState();
}

class _McpAddPageState extends State<McpAddPage> {
  final name = TextEditingController(),
      address = TextEditingController(),
      command = TextEditingController(),
      args = TextEditingController(),
      env = TextEditingController(),
      token = TextEditingController();
  final form = GlobalKey<FormState>();
  bool remote = true, busy = false;
  String error = '';
  NekodotClient get c => widget.client;
  @override
  void dispose() {
    for (final controller in [name, address, command, args, env, token]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await c.rpc('mcp.add', {
        'botId': widget.bot['botId'],
        'name': name.text.trim(),
        'config': remote
            ? {'url': address.text.trim()}
            : {
                'command': command.text.trim(),
                'args': args.text
                    .split('\n')
                    .where((line) => line.isNotEmpty)
                    .toList(),
                if (env.text.trim().isNotEmpty) 'env': jsonDecode(env.text),
              },
        if (remote && token.text.isNotEmpty) 'bearerToken': token.text,
      });
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => error = c.tr('请求失败，请重试', 'Request failed. Try again.'));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: c.tr('添加 MCP', 'Add MCP'),
    body: Form(
      key: form,
      child: PageList(
        children: [
          Row(
            children: [
              CatAvatar.of(widget.bot, size: 28),
              const SizedBox(width: 12),
              Expanded(child: Text('${widget.bot['displayName']}')),
            ],
          ),
          const SizedBox(height: 24),
          LabeledField(
            label: c.tr('名称', 'Name'),
            child: TextFormField(
              key: const ValueKey('mcp-name'),
              controller: name,
              enabled: !busy,
              validator: (v) => v!.trim().isEmpty ? c.tr('名称', 'Name') : null,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Segment<bool>(
              value: remote,
              options: const {true: Text('HTTP'), false: Text('stdio')},
              onChanged: (value) {
                if (!busy) setState(() => remote = value);
              },
            ),
          ),
          const SizedBox(height: 16),
          if (remote) ...[
            LabeledField(
              label: c.tr('MCP 地址', 'MCP URL'),
              child: TextFormField(
                key: const ValueKey('mcp-url'),
                controller: address,
                enabled: !busy,
                keyboardType: TextInputType.url,
                autocorrect: false,
                validator: (v) {
                  final uri = Uri.tryParse(v!.trim());
                  return uri != null &&
                          ['http', 'https'].contains(uri.scheme) &&
                          uri.host.isNotEmpty
                      ? null
                      : c.tr('MCP 地址', 'MCP URL');
                },
              ),
            ),
            const SizedBox(height: 16),
            LabeledField(
              label: 'Bearer token',
              child: TextField(
                controller: token,
                enabled: !busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
              ),
            ),
          ] else ...[
            LabeledField(
              label: c.tr('启动命令', 'Command'),
              child: TextFormField(
                controller: command,
                enabled: !busy,
                validator: (v) =>
                    v!.trim().isEmpty ? c.tr('启动命令', 'Command') : null,
              ),
            ),
            const SizedBox(height: 16),
            LabeledField(
              label: c.tr('参数（每行一个）', 'Arguments (one per line)'),
              child: TextField(
                controller: args,
                enabled: !busy,
                minLines: 2,
                maxLines: 6,
                autocorrect: false,
              ),
            ),
            const SizedBox(height: 16),
            LabeledField(
              label: '${c.tr('环境变量', 'Environment variables')} (JSON)',
              child: TextFormField(
                controller: env,
                enabled: !busy,
                minLines: 2,
                maxLines: 6,
                autocorrect: false,
                validator: (v) {
                  if (v!.trim().isEmpty) return null;
                  try {
                    final value = jsonDecode(v);
                    if (value is Map &&
                        value.values.every((v) => v is String)) {
                      return null;
                    }
                  } on FormatException {
                    /* Show the field label; do not submit invalid JSON. */
                  }
                  return c.tr('环境变量', 'Environment variables');
                },
              ),
            ),
          ],
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: const ValueKey('mcp-save'),
              onPressed: busy ? null : save,
              child: Text(c.tr('保存', 'Save')),
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ErrorNotice(error),
        ],
      ),
    ),
  );
}
