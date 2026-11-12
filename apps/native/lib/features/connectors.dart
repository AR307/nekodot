import 'dart:async';
import 'dart:math' as math;

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

    Widget tile(Json service, {required bool wide}) {
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
      return Material(
        key: ValueKey('connector-service-${service['serviceId']}'),
        color: wide ? tone.sidebar : Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          onTap: () => open(service),
          child: Padding(
            padding: EdgeInsets.all(wide ? 16 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ConnectorIcon(url: service['icon'] as String?, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${service['name']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (linked)
                      Tooltip(
                        message: c.tr('已连接', 'Connected'),
                        child: Icon(
                          Icons.check_circle_outline,
                          size: 16,
                          color: tone.ink2,
                        ),
                      )
                    else
                      Icon(Icons.chevron_right, size: 18, color: tone.ink3),
                  ],
                ),
                if ((service['description'] as String? ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${service['description']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(fontSize: 13, height: 1.5),
                  ),
                ],
                if (pending) ...[
                  const SizedBox(height: 8),
                  Text(
                    c.tr('等待授权', 'Awaiting authorization'),
                    style: text.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            !tone.glass &&
            constraints.maxWidth >= 800 &&
            MediaQuery.textScalerOf(context).scale(14) <= 20;
        final side = math.max(16.0, (constraints.maxWidth - 1080) / 2);
        final columns = wide ? 2 : 1;
        final rows = (entries.length / columns).ceil();
        final inset = MediaQuery.paddingOf(context);
        final catalog = CustomScrollView(
          key: const PageStorageKey('connector-catalog'),
          controller: scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: search,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search, size: 20),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: wide
                        ? Text(
                            category == null
                                ? c.tr('可连接服务', 'Available services')
                                : categories[category]!,
                            style: text.titleMedium,
                          )
                        : Align(
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
                              onSelected: (value) =>
                                  select(value.isEmpty ? null : value),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: tone.glass ? 48 : 36,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          filters[category ?? '']!,
                                          style: text.titleMedium,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.expand_more, size: 18),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                  if (error != null)
                    ErrorNotice(
                      error!,
                      action: TextButton(
                        onPressed: () => load(refresh: true),
                        child: Text(c.tr('重试', 'Retry')),
                      ),
                    ),
                ],
              ),
            ),
            if (loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (entries.isEmpty && error == null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      c.tr('未找到服务', 'No services found'),
                      style: text.bodyMedium?.copyWith(color: tone.ink2),
                    ),
                  ),
                ),
              )
            else
              SliverList.builder(
                itemCount: rows,
                itemBuilder: (context, row) {
                  final at = row * columns;
                  return Padding(
                    padding: EdgeInsets.only(bottom: wide ? 12 : 8),
                    child: wide
                        ? IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: tile(entries[at], wide: true)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: at + 1 < entries.length
                                      ? tile(entries[at + 1], wide: true)
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          )
                        : tile(entries[at], wide: false),
                  );
                },
              ),
            if (!loading && cursor != null)
              SliverToBoxAdapter(
                child: Padding(
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
              ),
            SliverToBoxAdapter(child: SizedBox(height: inset.bottom + 28)),
          ],
        );
        return Padding(
          padding: EdgeInsets.fromLTRB(side, inset.top + 12, side, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (wide) ...[
                SizedBox(
                  width: 184,
                  child: ListView(
                    primary: false,
                    padding: EdgeInsets.only(bottom: inset.bottom + 28),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                        child: Text(
                          c.tr('可连接服务', 'Available services'),
                          style: text.bodySmall?.copyWith(fontSize: 13),
                        ),
                      ),
                      for (final entry in filters.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: TextButton(
                            key: ValueKey(
                              'connector-category-${entry.key.isEmpty ? 'all' : entry.key}',
                            ),
                            style: TextButton.styleFrom(
                              alignment: Alignment.centerLeft,
                              minimumSize: const Size.fromHeight(36),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              foregroundColor: (category ?? '') == entry.key
                                  ? tone.ink
                                  : tone.ink2,
                              backgroundColor: (category ?? '') == entry.key
                                  ? tone.hover
                                  : Colors.transparent,
                              textStyle: text.bodyMedium?.copyWith(
                                fontSize: 13,
                                fontWeight: (category ?? '') == entry.key
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                              shape: RoundedSuperellipseBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () =>
                                select(entry.key.isEmpty ? null : entry.key),
                            child: Text(entry.value),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
              ],
              Expanded(child: catalog),
            ],
          ),
        );
      },
    );
  }
}
