import 'dart:async';

import 'package:flutter/material.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../ui/design.dart';
import 'connector_icon.dart';
import 'connector_service.dart';
import 'plugin_catalog.dart';

/// Account HTTP only: browsing and connecting do not require an online Node.
class ConnectorsBody extends StatefulWidget {
  final NekodotClient client;
  const ConnectorsBody({super.key, required this.client});
  @override
  State<ConnectorsBody> createState() => _ConnectorsBodyState();
}

class _ConnectorsBodyState extends State<ConnectorsBody>
    with WidgetsBindingObserver {
  final search = TextEditingController();
  final scroll = ScrollController();
  final categories = <String, String>{};
  List<Json> connections = [], services = [];
  StreamSubscription<Json>? changes;
  Timer? debounce;
  String? cursor, error, category;
  bool loading = true, more = false;
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
    scroll.dispose();
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
      if (mounted) setState(() => connections = objects(result['connections']));
    } catch (_) {
      if (mounted) {
        setState(() => error = c.tr('请求失败，请重试', 'Request failed. Try again.'));
      }
    }
  }

  Future<void> load({bool next = false, bool refresh = false}) async {
    final generation = ++revision;
    final query = search.text.trim();
    final selected = category;
    setState(() {
      error = null;
      if (next) {
        more = true;
      } else {
        loading = true;
        services = [];
        cursor = null;
      }
    });
    if (!next) await accounts(refresh: refresh);
    try {
      final page = await c.account.request(
        '/connectors/catalog',
        method: 'POST',
        body: {
          'query': query,
          'category': ?selected,
          if (next && cursor != null) 'cursor': cursor,
        },
      );
      if (!mounted || generation != revision) return;
      setState(() {
        services = [if (next) ...services, ...objects(page['services'])];
        cursor = page['cursor'] as String?;
        for (final service in services) {
          for (final item in objects(service['categories'])) {
            categories['${item['categoryId']}'] = '${item['name']}';
          }
        }
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

  void select(String? value) {
    debounce?.cancel();
    search.clear();
    category = value;
    if (scroll.hasClients) scroll.jumpTo(0);
    unawaited(load());
  }

  Future<void> open(Json service) async {
    await pushPage(context, ConnectorServicePage(client: c, service: service));
    if (mounted) await accounts();
  }

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final text = Theme.of(context).textTheme;
    final query = search.text.trim();
    // Include the user's services even when they are not on the first catalog page.
    // Only service summaries live here; individual accounts belong to the detail.
    final entries = <String, Json>{
      if (category == null && query.isEmpty)
        for (final row in connections)
          '${row['service']['serviceId']}': object(row['service']),
      for (final service in services) '${service['serviceId']}': service,
    }.values.toList();
    final filters = {
      '': c.tr('全部', 'All'),
      ...Map.fromEntries(
        categories.entries.toList()..sort((a, b) => a.value.compareTo(b.value)),
      ),
    };

    return PluginCatalog(
      scroll: scroll,
      loading: loading,
      count: entries.length,
      search: TextField(
        key: const ValueKey('connector-search'),
        controller: search,
        decoration: InputDecoration(
          prefixIcon: const Icon(Symbols.search, size: 20),
          hintText: c.tr('搜索', 'Search'),
        ),
        onChanged: (_) {
          debounce?.cancel();
          category = null;
          debounce = Timer(
            const Duration(milliseconds: 250),
            () => unawaited(load()),
          );
        },
      ),
      actions: [
        IconAction(
          icon: Symbols.refresh,
          tooltip: c.tr('刷新', 'Refresh'),
          onPressed: loading ? null : () => load(refresh: true),
        ),
      ],
      filters: Align(
        alignment: Alignment.centerLeft,
        child: ActionMenu<String>(
          key: const ValueKey('connector-category-menu'),
          tooltip: c.tr('可连接服务', 'Available services'),
          items: [
            for (final entry in filters.entries)
              MenuAction(
                key: ValueKey(
                  'connector-category-${entry.key.isEmpty ? 'all' : entry.key}',
                ),
                value: entry.key,
                label: entry.value,
                selected: (category ?? '') == entry.key,
              ),
          ],
          onSelected: (value) => select(value.isEmpty ? null : value),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: tone.glass ? 48 : 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      filters[category ?? '']!,
                      style: text.titleSmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Symbols.expand_more, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
      notice: error == null
          ? null
          : ErrorNotice(
              error!,
              action: TextButton(
                onPressed: () => load(refresh: true),
                child: Text(c.tr('重试', 'Retry')),
              ),
            ),
      empty: error == null
          ? Text(
              c.tr('未找到服务', 'No services found'),
              style: text.bodyMedium?.copyWith(color: tone.ink2),
            )
          : null,
      itemBuilder: (index, wide) {
        final service = entries[index];
        final linked = connections
            .where(
              (row) =>
                  row['service']['serviceId'] == service['serviceId'] &&
                  row['status'] == 'active',
            )
            .length;
        final pending = connections.any(
          (row) =>
              row['service']['serviceId'] == service['serviceId'] &&
              row['status'] == 'pending',
        );
        return PluginTile(
          key: ValueKey('connector-service-${service['serviceId']}'),
          wide: wide,
          icon: ConnectorIcon(url: service['icon'] as String?, size: 32),
          name: '${service['name']}',
          description: '${service['description'] ?? ''}',
          onTap: () => open(service),
          status: linked > 0 || pending
              ? Row(
                  children: [
                    Icon(
                      linked > 0 ? Symbols.check_circle : Symbols.schedule,
                      size: 16,
                      color: tone.ink2,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        linked > 0
                            ? '${c.tr('已连接', 'Connected')} $linked'
                            : c.tr('等待授权', 'Awaiting authorization'),
                        style: text.bodySmall,
                      ),
                    ),
                  ],
                )
              : null,
        );
      },
      footer: !loading && cursor != null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
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
            )
          : null,
    );
  }
}
