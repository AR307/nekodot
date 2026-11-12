import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../platform/desktop.dart';
import '../ui/design.dart';
import 'connector_authorization.dart';
import 'connector_icon.dart';

class ConnectorServicePage extends StatefulWidget {
  final NekodotClient client;
  final Json service;
  const ConnectorServicePage({
    super.key,
    required this.client,
    required this.service,
  });
  @override
  State<ConnectorServicePage> createState() => _ConnectorServicePageState();
}

class _ConnectorServicePageState extends State<ConnectorServicePage>
    with WidgetsBindingObserver {
  late Json service = widget.service;
  List<Json> connections = [], authorizations = [], tools = [];
  final search = TextEditingController();
  final expanded = <String>{};
  StreamSubscription<Json>? changes;
  Timer? debounce;
  String? error, toolsError;
  bool loading = true, connecting = false, toolsLoading = true;
  int toolLimit = 5, toolRevision = 0;
  NekodotClient get c => widget.client;
  String get id => '${service['serviceId']}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    changes = c.connectorChanges.stream.listen((_) => unawaited(accounts()));
    unawaited(load());
    unawaited(loadTools());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    changes?.cancel();
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(accounts(refresh: true));
  }

  Future<void> accounts({bool refresh = false}) async {
    try {
      final result = await c.account.request(
        refresh ? '/connectors/refresh' : '/connectors/connections',
        method: refresh ? 'POST' : 'GET',
      );
      if (!mounted) return;
      setState(() {
        connections = objects(result['connections'])
            .where((row) => row['service']['serviceId'] == id)
            .toList();
        authorizations = objects(result['authorizations'])
            .where((row) => row['service']['serviceId'] == id)
            .toList();
      });
    } catch (_) {
      if (mounted) {
        setState(() => error = c.tr('请求失败，请重试', 'Request failed. Try again.'));
      }
    }
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await c.account.request('/connectors/services/$id');
      if (!mounted) return;
      setState(() => service = result);
      await accounts(refresh: true);
    } catch (_) {
      if (mounted) {
        setState(() => error = c.tr('请求失败，请重试', 'Request failed. Try again.'));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> loadTools() async {
    final generation = ++toolRevision;
    setState(() {
      toolsLoading = true;
      toolsError = null;
    });
    try {
      final result = await c.account.request(
        '/connectors/services/$id/tools',
        method: 'POST',
        body: {'query': search.text.trim(), 'limit': toolLimit},
      );
      if (!mounted || generation != toolRevision) return;
      setState(() => tools = objects(result['tools']));
    } catch (_) {
      if (mounted && generation == toolRevision) {
        setState(
          () => toolsError = c.tr('请求失败，请重试', 'Request failed. Try again.'),
        );
      }
    } finally {
      if (mounted && generation == toolRevision) {
        setState(() => toolsLoading = false);
      }
    }
  }

  Future<void> connect({String? reconnectId}) async {
    if (connecting) return;
    setState(() {
      connecting = true;
      error = null;
    });
    try {
      final auth = await c.account.request(
        reconnectId == null
            ? '/connectors/authorizations'
            : '/connectors/connections/$reconnectId/authorize',
        method: 'POST',
        body: {'serviceId': id},
      );
      if (!mounted) return;
      await accounts();
      if (!mounted) return;
      final opened = await launchUrl(
        Uri.parse(auth['url'] as String),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        setState(() => error = c.tr('请求失败，请重试', 'Request failed. Try again.'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = c.tr('请求失败，请重试', 'Request failed. Try again.'));
      }
    } finally {
      if (mounted) setState(() => connecting = false);
    }
  }

  Future<void> edit(Json connection) async {
    final label = TextEditingController(
      text: connection['label'] as String? ?? '',
    );
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(c.tr('账号备注', 'Account label')),
        content: SizedBox(
          width: 320,
          child: TextField(
            controller: label,
            autofocus: true,
            maxLength: 120,
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(c.tr('取消', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, label.text),
            child: Text(c.tr('保存', 'Save')),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    label.dispose();
    if (value == null) return;
    await c.account.request(
      '/connectors/connections/${connection['connectionId']}',
      method: 'PUT',
      body: {'label': value},
    );
    await accounts();
  }

  Future<void> action(String value, Json connection) async {
    try {
      if (value == 'label') {
        await edit(connection);
      } else if (value == 'disconnect') {
        final yes = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(c.tr('断开此账号？', 'Disconnect this account?')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(c.tr('取消', 'Cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(c.tr('断开连接', 'Disconnect')),
              ),
            ],
          ),
        );
        if (yes != true) return;
        await c.account.request(
          '/connectors/connections/${connection['connectionId']}',
          method: 'DELETE',
        );
        await accounts();
      } else {
        await connect(reconnectId: connection['connectionId'] as String);
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = c.tr('请求失败，请重试', 'Request failed. Try again.'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final count = connections.where((row) => row['status'] == 'active').length;
    final pending = authorizations.map((row) => row['connectionId']).toSet();
    final website = Uri.tryParse(service['website'] as String? ?? '');
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 12),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: tone.glass ? const Frost() : const WindowDrag(),
        actions: [
          IconAction(
            icon: Icons.refresh,
            tooltip: c.tr('刷新', 'Refresh'),
            onPressed: loading
                ? null
                : () {
                    unawaited(load());
                    unawaited(loadTools());
                  },
          ),
          const SizedBox(width: 8),
          SizedBox(width: WindowChrome.reserved(context)),
        ],
      ),
      body: PageList(
        maxWidth: 800,
        children: [
          Row(
            children: [
              ConnectorIcon(url: service['icon'] as String?, size: 44),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  '${service['name']}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(width: 16),
              FilledButton(
                key: const ValueKey('connector-connect'),
                onPressed:
                    connecting || (service['authMethods'] as List).isEmpty
                    ? null
                    : connect,
                child: connecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(c.tr('连接', 'Connect')),
              ),
            ],
          ),
          if ((service['description'] as String? ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SelectableText(
                '${service['description']}',
                style: TextStyle(color: tone.ink2, height: 1.5),
              ),
            ),
          if (error != null)
            ErrorNotice(
              error!,
              action: TextButton(
                onPressed: load,
                child: Text(c.tr('重试', 'Retry')),
              ),
            ),
          heading('${c.tr('已连接账号', 'Connected accounts')} · $count'),
          if (loading)
            const Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (!loading && connections.isEmpty)
            Text(
              c.tr('暂无连接', 'No connections'),
              style: TextStyle(color: tone.ink2),
            ),
          for (final row in connections)
            if (!pending.contains(row['connectionId']))
              ListTile(
                key: ValueKey('connector-account-${row['connectionId']}'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  (row['label'] as String).isNotEmpty
                      ? '${row['label']}'
                      : (row['account'] as String).isNotEmpty
                      ? '${row['account']}'
                      : '${service['name']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    if ((row['label'] as String).isNotEmpty &&
                        (row['account'] as String).isNotEmpty)
                      '${row['account']}',
                    connectorStatus(c, '${row['status']}'),
                  ].join(' · '),
                ),
                trailing: ActionMenu<String>(
                  tooltip: c.tr('更多', 'More'),
                  alignEnd: true,
                  onSelected: (value) => unawaited(action(value, row)),
                  items: [
                    MenuAction(
                      value: 'label',
                      label: c.tr('账号备注', 'Account label'),
                      icon: Icons.edit_outlined,
                    ),
                    MenuAction(
                      value: 'reconnect',
                      label: c.tr('重新授权', 'Reconnect'),
                      icon: Icons.refresh,
                      enabled: !connecting,
                    ),
                    null,
                    MenuAction(
                      value: 'disconnect',
                      label: c.tr('断开连接', 'Disconnect'),
                      icon: Icons.link_off,
                    ),
                  ],
                ),
              ),
          for (final auth in authorizations)
            ConnectorAuthorizationView(
              key: ValueKey(auth['authorizationId']),
              client: c,
              authorization: auth,
              onChanged: () => unawaited(accounts()),
            ),
          if (connections.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: connecting ? null : connect,
                icon: const Icon(Icons.add, size: 18),
                label: Text(c.tr('连接其他账号', 'Connect another account')),
              ),
            ),
          heading(
            '${c.tr('可用工具', 'Available tools')}${service['toolCount'] == null ? '' : ' · ${service['toolCount']}'}',
          ),
          TextField(
            controller: search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: c.tr('搜索', 'Search'),
            ),
            onChanged: (_) {
              debounce?.cancel();
              toolLimit = 5;
              debounce = Timer(
                const Duration(milliseconds: 250),
                () => unawaited(loadTools()),
              );
            },
          ),
          const SizedBox(height: 8),
          if (toolsLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            if (toolsError != null)
              ErrorNotice(
                toolsError!,
                action: TextButton(
                  onPressed: loadTools,
                  child: Text(c.tr('重试', 'Retry')),
                ),
              ),
            if (tools.isEmpty && toolsError == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  c.tr('没有找到', 'Nothing found'),
                  style: TextStyle(color: tone.ink2),
                ),
              ),
            for (final tool in tools)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.extension_outlined,
                  size: 20,
                  color: tone.ink3,
                ),
                title: Text(
                  '${tool['name']}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                subtitle: Text(
                  '${tool['description']}',
                  maxLines: expanded.contains(tool['name']) ? null : 2,
                  overflow: expanded.contains(tool['name'])
                      ? null
                      : TextOverflow.ellipsis,
                ),
                onTap: () => setState(() {
                  if (!expanded.add('${tool['name']}')) {
                    expanded.remove(tool['name']);
                  }
                }),
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            if (tools.length == toolLimit)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    toolLimit += 20;
                    unawaited(loadTools());
                  },
                  child: Text(c.tr('加载更多', 'Load more')),
                ),
              ),
          ],
          heading(c.tr('授权方式', 'Authorization')),
          Text(
            (service['authMethods'] as List).join(' · '),
            style: TextStyle(color: tone.ink2),
          ),
          if (website != null &&
              ['https', 'http'].contains(website.scheme)) ...[
            heading(c.tr('网站', 'Website')),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    launchUrl(website, mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(website.host),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
