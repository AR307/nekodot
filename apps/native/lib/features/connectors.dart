import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../ui/design.dart';
import 'connector_icon.dart';

String connectorStatus(NekodotClient c, String status) => switch (status) {
  'active' => c.tr('已连接', 'Connected'),
  'pending' => c.tr('等待授权', 'Awaiting authorization'),
  'failed' => c.tr('授权失败', 'Authorization failed'),
  'expired' => c.tr('授权已过期', 'Authorization expired'),
  'cancelled' => c.tr('已取消', 'Cancelled'),
  'stopped' => c.tr('已停止', 'Stopped'),
  _ => c.tr('已断开', 'Disconnected'),
};

/// Account HTTP only: this view works without a selected or online Node.
class ConnectorsBody extends StatefulWidget {
  final NekodotClient client;
  const ConnectorsBody({super.key, required this.client});
  @override
  State<ConnectorsBody> createState() => _ConnectorsBodyState();
}

class _ConnectorsBodyState extends State<ConnectorsBody>
    with WidgetsBindingObserver {
  final search = TextEditingController();
  List<Json> connections = [], services = [], authorizations = [];
  StreamSubscription<Json>? changes;
  Timer? debounce;
  String? cursor, error;
  bool loading = true, more = false, configured = true;
  int revision = 0;
  NekodotClient get c => widget.client;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    changes = c.connectorChanges.stream.listen((_) => unawaited(accounts()));
    unawaited(load());
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
        connections = objects(result['connections']);
        authorizations = objects(result['authorizations']);
        configured = result['configured'] == true;
      });
    } catch (_) {
      if (mounted) {
        setState(() => error = c.tr('请求失败，请重试', 'Request failed. Try again.'));
      }
    }
  }

  Future<void> load({bool next = false, bool refresh = false}) async {
    final generation = ++revision;
    setState(() {
      error = null;
      if (next) {
        more = true;
      } else {
        loading = true;
      }
    });
    if (!next) await accounts(refresh: refresh);
    try {
      final page = await c.account.request(
        '/connectors/catalog',
        method: 'POST',
        body: {
          'query': search.text.trim(),
          if (next && cursor != null) 'cursor': cursor,
        },
      );
      if (!mounted || generation != revision) return;
      setState(() {
        services = [if (next) ...services, ...objects(page['services'])];
        cursor = page['cursor'] as String?;
      });
    } catch (_) {
      if (mounted && generation == revision) {
        setState(() => error = c.tr('连接器暂不可用', 'Connectors unavailable'));
      }
    } finally {
      if (mounted && generation == revision) {
        setState(() {
          loading = false;
          more = false;
        });
      }
    }
  }

  Future<void> connect(Json service, {String? reconnectId}) async {
    try {
      final auth = await c.account.request(
        reconnectId == null
            ? '/connectors/authorizations'
            : '/connectors/connections/$reconnectId/authorize',
        method: 'POST',
        body: {'serviceId': service['serviceId']},
      );
      if (!mounted) return;
      await accounts();
      await launchUrl(
        Uri.parse(auth['url'] as String),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      if (mounted) {
        setState(() => error = c.tr('请求失败，请重试', 'Request failed. Try again.'));
      }
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
    // The route's closing transition may still reference its text field.
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
        return;
      }
      if (value == 'disconnect') {
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
        await connect(
          object(connection['service']),
          reconnectId: value == 'reconnect'
              ? connection['connectionId'] as String
              : null,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = c.tr('请求失败，请重试', 'Request failed. Try again.'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.toLowerCase();
    final filtered = connections.where(
      (row) => '${row['label']} ${row['account']} ${row['service']['name']}'
          .toLowerCase()
          .contains(query),
    );
    final pending = authorizations.map((a) => a['connectionId']).toSet();
    Widget heading(String value) => Padding(
      padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
      child: Text(value, style: Theme.of(context).textTheme.titleSmall),
    );
    return ListView(
      key: const PageStorageKey('connectors'),
      padding: EdgeInsets.fromLTRB(
        16,
        context.tone.glass ? MediaQuery.paddingOf(context).top + 12 : 12,
        16,
        MediaQuery.paddingOf(context).bottom + 24,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: c.tr('搜索', 'Search'),
                ),
                onChanged: (_) {
                  setState(() {});
                  debounce?.cancel();
                  debounce = Timer(
                    const Duration(milliseconds: 250),
                    () => unawaited(load()),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            IconAction(
              icon: Icons.refresh,
              tooltip: c.tr('刷新', 'Refresh'),
              onPressed: loading ? null : () => load(refresh: true),
            ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(child: Text(error!)),
                TextButton(
                  onPressed: () => load(refresh: true),
                  child: Text(c.tr('重试', 'Retry')),
                ),
              ],
            ),
          ),
        heading(c.tr('已连接账号', 'Connected accounts')),
        if (!loading && filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              c.tr('暂无连接', 'No connections'),
              style: TextStyle(color: context.tone.ink2),
            ),
          ),
        for (final connection in filtered)
          if (!pending.contains(connection['connectionId']))
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: ConnectorIcon(
                url: connection['service']['icon'] as String?,
              ),
              title: Text(
                '${connection['service']['name']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  if ('${connection['label']}'.isNotEmpty)
                    '${connection['label']}',
                  if ('${connection['account']}'.isNotEmpty)
                    '${connection['account']}',
                  connectorStatus(c, '${connection['status']}'),
                ].join('  '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: ActionMenu<String>(
                tooltip: c.tr('更多', 'More'),
                alignEnd: true,
                onSelected: (value) => unawaited(action(value, connection)),
                items: [
                  MenuAction(
                    value: 'connect',
                    label: c.tr('连接其他账号', 'Connect another account'),
                    icon: Icons.add,
                  ),
                  MenuAction(
                    value: 'label',
                    label: c.tr('账号备注', 'Account label'),
                    icon: Icons.edit_outlined,
                  ),
                  MenuAction(
                    value: 'reconnect',
                    label: c.tr('重新授权', 'Reconnect'),
                    icon: Icons.refresh,
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
          ),
        heading(c.tr('可连接服务', 'Available services')),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (!loading && services.isEmpty && error == null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(c.tr('未找到服务', 'No services found')),
          ),
        for (final service in services)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: ConnectorIcon(url: service['icon'] as String?),
            title: Text(
              '${service['name']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: TextButton(
              onPressed: configured ? () => connect(service) : null,
              child: Text(c.tr('连接', 'Connect')),
            ),
          ),
        if (cursor != null)
          Center(
            child: TextButton(
              onPressed: more ? null : () => load(next: true),
              child: more
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(c.tr('加载更多', 'Load more')),
            ),
          ),
      ],
    );
  }
}

/// Shared pending authorization UI; polls only a visible, pending flow.
class ConnectorAuthorizationView extends StatefulWidget {
  final NekodotClient client;
  final Json authorization;
  final bool stopped;
  const ConnectorAuthorizationView({
    super.key,
    required this.client,
    required this.authorization,
    this.stopped = false,
  });
  @override
  State<ConnectorAuthorizationView> createState() =>
      _ConnectorAuthorizationViewState();
}

class _ConnectorAuthorizationViewState extends State<ConnectorAuthorizationView>
    with WidgetsBindingObserver, RouteAware {
  late Json auth = widget.authorization;
  Timer? timer;
  StreamSubscription<Json>? changes;
  bool refreshing = false, cancelling = false;
  bool visible = true, foreground = true, failed = false;
  NekodotClient get c => widget.client;
  String get id => '${auth['authorizationId']}';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    changes = c.connectorChanges.stream.listen((event) {
      final updated = object(event['authorization']);
      if (updated['authorizationId'] == id && mounted) {
        setState(() => auth = updated);
        schedule();
      }
    });
    schedule();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) nativeRoutes.subscribe(this, route);
  }

  @override
  void didUpdateWidget(ConnectorAuthorizationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.authorization != oldWidget.authorization) {
      auth = widget.authorization;
    }
    schedule();
  }

  void schedule() {
    timer?.cancel();
    if (visible &&
        foreground &&
        !cancelling &&
        !widget.stopped &&
        auth['status'] == 'pending') {
      timer = Timer(const Duration(seconds: 4), () => unawaited(refresh()));
    }
  }

  @override
  void didPushNext() {
    visible = false;
    schedule();
  }

  @override
  void didPopNext() {
    visible = true;
    unawaited(refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground && visible) {
      unawaited(refresh());
    } else {
      schedule();
    }
  }

  Future<void> refresh() async {
    if (refreshing ||
        cancelling ||
        widget.stopped ||
        auth['status'] != 'pending')
      return;
    setState(() => refreshing = true);
    try {
      final result = await c.account.request('/connectors/authorizations/$id');
      if (mounted && !cancelling && auth['status'] == 'pending') {
        setState(() {
          auth = result;
          failed = false;
        });
      }
    } catch (_) {
      if (mounted && !cancelling && auth['status'] == 'pending')
        setState(() => failed = true);
    } finally {
      if (mounted) {
        setState(() => refreshing = false);
        schedule();
      }
    }
  }

  Future<void> cancel() async {
    if (cancelling) return;
    timer?.cancel();
    setState(() => cancelling = true);
    try {
      final result = await c.account.request(
        '/connectors/authorizations/$id/cancel',
        method: 'POST',
      );
      if (mounted)
        setState(() {
          auth = result;
          failed = false;
        });
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) {
        setState(() => cancelling = false);
        schedule();
      }
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    changes?.cancel();
    nativeRoutes.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = object(auth['service']);
    final pending = !widget.stopped && auth['status'] == 'pending';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ConnectorIcon(url: service['icon'] as String?),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${service['name']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                connectorStatus(
                  c,
                  widget.stopped ? 'stopped' : '${auth['status']}',
                ),
                style: TextStyle(color: context.tone.ink2),
              ),
            ],
          ),
          if (failed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(c.tr('请求失败，请重试', 'Request failed. Try again.')),
            ),
          if (pending)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: cancelling
                        ? null
                        : () async {
                            final opened = await launchUrl(
                              Uri.parse(auth['url'] as String),
                              mode: LaunchMode.externalApplication,
                            );
                            if (!opened && mounted) {
                              setState(() => failed = true);
                            }
                          },
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(c.tr('打开授权页面', 'Open authorization')),
                  ),
                  TextButton(
                    onPressed: refreshing || cancelling ? null : refresh,
                    child: Text(c.tr('刷新', 'Refresh')),
                  ),
                  TextButton(
                    onPressed: cancelling ? null : cancel,
                    child: Text(c.tr('取消', 'Cancel')),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class ConnectorChatCard extends StatelessWidget {
  final NekodotClient client;
  final Json content;
  const ConnectorChatCard({
    super.key,
    required this.client,
    required this.content,
  });
  @override
  Widget build(BuildContext context) => ChatCard(
    child: ConnectorAuthorizationView(
      client: client,
      authorization: object(content['authorization']),
      stopped: content['stopped'] == true,
    ),
  );
}
