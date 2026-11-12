import 'dart:async';

import 'package:flutter/material.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../ui/design.dart';
import 'connector_icon.dart';
import 'connector_service.dart';

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
    unawaited(load());
  }

  Future<void> open(Json service) async {
    await pushPage(context, ConnectorServicePage(client: c, service: service));
    if (mounted) await accounts();
  }

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final query = search.text.trim();
    // Include the user's services even when they are not on the first catalog page.
    // Only service summaries live here; individual accounts belong to the detail.
    final entries = <String, Json>{
      if (category == null && query.isEmpty)
        for (final row in connections)
          '${row['service']['serviceId']}': object(row['service']),
      for (final service in services) '${service['serviceId']}': service,
    }.values;
    final groups = <String, List<Json>>{};
    for (final service in entries) {
      final tags = objects(service['categories']);
      final heading = category != null
          ? categories[category]!
          : query.isNotEmpty
          ? c.tr('可连接服务', 'Available services')
          : tags.isNotEmpty
          ? '${tags.first['name']}'
          : c.tr('可连接服务', 'Available services');
      (groups[heading] ??= []).add(service);
    }

    Widget tile(Json service) {
      final linked = connections.any(
        (row) =>
            row['service']['serviceId'] == service['serviceId'] &&
            row['status'] == 'active',
      );
      final pending = connections.any(
        (row) =>
            row['service']['serviceId'] == service['serviceId'] &&
            row['status'] == 'pending',
      );
      return ListTile(
        key: ValueKey('connector-service-${service['serviceId']}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        leading: ConnectorIcon(url: service['icon'] as String?, size: 40),
        title: Text(
          '${service['name']}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: pending ? Text(c.tr('等待授权', 'Awaiting authorization')) : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (linked) ...[
              Tooltip(
                message: c.tr('已连接', 'Connected'),
                child: const Icon(Icons.check, size: 16),
              ),
              const SizedBox(width: 8),
            ],
            Icon(Icons.chevron_right, size: 18, color: tone.ink3),
          ],
        ),
        onTap: () => open(service),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 680;
        final visible = categories.entries.take(wide ? 4 : 1).toList();
        final extra = categories.entries.skip(visible.length).toList();
        Widget filter(String label, String? value) => TextButton(
          key: ValueKey('connector-category-${value ?? 'all'}'),
          style: TextButton.styleFrom(
            backgroundColor: category == value ? tone.ink : tone.raised,
            foregroundColor: category == value ? tone.base : tone.ink2,
          ),
          onPressed: () => select(value),
          child: Text(label),
        );
        return PageList(
          key: const PageStorageKey('connector-catalog'),
          maxWidth: 880,
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
                      debounce?.cancel();
                      category = null;
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
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                filter(c.tr('全部', 'All'), null),
                for (final entry in visible) filter(entry.value, entry.key),
                if (extra.isNotEmpty)
                  ActionMenu<String>(
                    tooltip: c.tr('更多', 'More'),
                    items: [
                      for (final entry in extra)
                        MenuAction(
                          value: entry.key,
                          label: entry.value,
                          selected: category == entry.key,
                        ),
                    ],
                    onSelected: select,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: tone.glass ? 14 : 7,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            extra.any((entry) => entry.key == category)
                                ? categories[category]!
                                : c.tr('更多', 'More'),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.expand_more, size: 16),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            if (error != null)
              ErrorNotice(
                error!,
                action: TextButton(
                  onPressed: () => load(refresh: true),
                  child: Text(c.tr('重试', 'Retry')),
                ),
              ),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (entries.isEmpty && error == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    c.tr('未找到服务', 'No services found'),
                    style: TextStyle(color: tone.ink2),
                  ),
                ),
              for (final group in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
                  child: Text(
                    group.key,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                for (var i = 0; i < group.value.length; i += wide ? 2 : 1)
                  if (wide)
                    Row(
                      children: [
                        Expanded(child: tile(group.value[i])),
                        const SizedBox(width: 16),
                        Expanded(
                          child: i + 1 < group.value.length
                              ? tile(group.value[i + 1])
                              : const SizedBox.shrink(),
                        ),
                      ],
                    )
                  else
                    tile(group.value[i]),
              ],
              if (cursor != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
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
                ),
            ],
          ],
        );
      },
    );
  }
}
