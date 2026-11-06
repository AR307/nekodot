import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../data/client.dart';
import '../data/usage.dart';
import '../ui/design.dart';

const _colors = [
  Color(0xff347bdd),
  Color(0xffee6b38),
  Color(0xff18ac7d),
  Color(0xffdfa100),
];

class StatisticsPage extends StatefulWidget {
  final NekodotClient client;
  const StatisticsPage({super.key, required this.client});
  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  UsageSummary? data;
  int span = 30, year = DateTime.now().year;
  String? nodeId;
  String error = '';
  bool busy = false;
  int request = 0;
  NekodotClient get c => widget.client;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool refresh = false}) async {
    final ticket = ++request;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedSpan = span, selectedNode = nodeId;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      if (refresh) {
        final result = await c.request(
          '/usage/refresh',
          method: 'POST',
          body: {'nodeId': ?selectedNode},
        );
        if (objects(result['nodes']).any((n) => n['synced'] != true) &&
            mounted &&
            request == ticket) {
          setState(
            () => error = c.tr('部分电脑未同步', 'Some computers have not synced'),
          );
        }
      }
      final timezone = await FlutterTimezone.getLocalTimezone();
      final result = await c.request(
        '/usage/query',
        method: 'POST',
        body: {
          'from': selectedSpan == 0
              ? null
              : usageDate(
                  DateTime(
                    today.year,
                    today.month,
                    today.day - selectedSpan + 1,
                  ),
                ),
          'to': usageDate(today),
          'timezone': timezone.identifier,
          'nodeId': ?selectedNode,
        },
      );
      if (mounted && request == ticket) {
        setState(() {
          data = UsageSummary(result);
          year = year.clamp(data!.from.year, data!.to.year);
        });
      }
    } catch (_) {
      if (mounted && request == ticket) {
        setState(() => error = c.tr('统计加载失败', 'Could not load statistics'));
      }
    } finally {
      if (mounted && request == ticket) setState(() => busy = false);
    }
  }

  Future<void> export() async {
    final snapshot = data;
    if (snapshot == null) return;
    try {
      await FilePicker.saveFile(
        fileName:
            'nekodot-${usageDate(snapshot.from)}-${usageDate(snapshot.to)}.csv',
        mimeType: 'text/csv',
        bytes: usageCsv(snapshot),
      );
    } catch (_) {
      if (mounted) {
        setState(() => error = c.tr('CSV 导出失败', 'CSV export failed'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = data;
    final ranges = {
      7: c.tr('近 7 天', '7 days'),
      30: c.tr('近 30 天', '30 days'),
      90: c.tr('近 90 天', '90 days'),
      365: c.tr('近一年', '1 year'),
      0: c.tr('全部', 'All'),
    };
    return AppPage(
      title: c.tr('统计', 'Statistics'),
      body: PageList(
        maxWidth: 1180,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final filters = Wrap(
                spacing: 2,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final range in ranges.entries)
                    TextButton(
                      key: ValueKey('usage-span-${range.key}'),
                      style: TextButton.styleFrom(
                        backgroundColor: span == range.key
                            ? context.tone.raised
                            : null,
                      ),
                      onPressed: () {
                        setState(() => span = range.key);
                        load();
                      },
                      child: Text(range.value),
                    ),
                  const SizedBox(width: 8),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: nodeId ?? '',
                      borderRadius: BorderRadius.circular(12),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(c.tr('全部电脑', 'All computers')),
                        ),
                        for (final n in objects(c.me?['nodes'] ?? []))
                          DropdownMenuItem(
                            value: '${n['nodeId']}',
                            child: Text(
                              '${n['name']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() => nodeId = value == '' ? null : value);
                        load();
                      },
                    ),
                  ),
                ],
              );
              final actions = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const ValueKey('usage-refresh'),
                    tooltip: c.tr('刷新', 'Refresh'),
                    onPressed: busy ? null : () => load(refresh: true),
                    icon: const Icon(Icons.refresh),
                  ),
                  TextButton.icon(
                    key: const ValueKey('usage-export'),
                    onPressed: busy || data == null ? null : export,
                    icon: const Icon(Icons.file_download_outlined),
                    label: Text(c.tr('导出 CSV', 'Export CSV')),
                  ),
                ],
              );
              return constraints.maxWidth < 850
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        filters,
                        Align(alignment: Alignment.centerRight, child: actions),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: filters),
                        actions,
                      ],
                    );
            },
          ),
          if (busy) const LinearProgressIndicator(minHeight: 2),
          ErrorNotice(error),
          if (selected != null) ...[
            _UsageCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.tr('使用日历', 'Usage calendar'),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      if (span == 0) ...[
                        IconButton(
                          tooltip: c.tr('上一年', 'Previous year'),
                          onPressed: year > selected.from.year
                              ? () => setState(() => year--)
                              : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text('$year'),
                        IconButton(
                          tooltip: c.tr('下一年', 'Next year'),
                          onPressed: year < selected.to.year
                              ? () => setState(() => year++)
                              : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  UsageCalendar(
                    data: selected,
                    year: span == 0 ? year : null,
                    unavailableLabel: c.tr(
                      '部分调用未返回用量',
                      'Some calls did not report usage',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _UsageCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        c.tr('总消耗 Token', 'Total tokens'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (selected.totals.unavailable > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Tooltip(
                            message: c.tr(
                              '部分调用未返回用量',
                              'Some calls did not report usage',
                            ),
                            child: const Icon(Icons.info_outline, size: 16),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    usageNumber(selected.totals.total),
                    style: Theme.of(context).textTheme.headlineLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      height: 12,
                      child: selected.totals.total == 0
                          ? ColoredBox(color: context.tone.raised)
                          : Row(
                              children: [
                                for (final (index, value)
                                    in selected.totals.tokens.values.indexed)
                                  if (value > 0)
                                    Expanded(
                                      flex: value,
                                      child: ColoredBox(
                                        color: _colors[index],
                                        child: const SizedBox.expand(),
                                      ),
                                    ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 24,
                    runSpacing: 10,
                    children: [
                      for (final (index, item)
                          in selected.totals.tokens.entries.indexed)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _colors[index],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${[c.tr('输入', 'Input'), c.tr('输出', 'Output'), c.tr('缓存命中', 'Cache read'), c.tr('缓存写入', 'Cache write')][index]}  ${usageNumber(item.value)}',
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final left = _Breakdown(
                  key: const ValueKey('usage-conversations'),
                  unavailableLabel: c.tr(
                    '部分调用未返回用量',
                    'Some calls did not report usage',
                  ),
                  title: c.tr('Dot 与群聊', 'Dots & groups'),
                  entries: selected.conversations,
                );
                final right = _Breakdown(
                  key: const ValueKey('usage-routines'),
                  unavailableLabel: c.tr(
                    '部分调用未返回用量',
                    'Some calls did not report usage',
                  ),
                  title: c.tr('定时任务与 Webhook', 'Cron & Webhook'),
                  entries: selected.routines,
                );
                return constraints.maxWidth < 720
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [left, const SizedBox(height: 16), right],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: left),
                          const SizedBox(width: 16),
                          Expanded(child: right),
                        ],
                      );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  final Widget child;
  const _UsageCard({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: context.tone.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: context.tone.line),
    ),
    child: child,
  );
}

class _Breakdown extends StatelessWidget {
  final String title;
  final String unavailableLabel;
  final List<UsageEntry> entries;
  const _Breakdown({
    super.key,
    required this.title,
    required this.entries,
    required this.unavailableLabel,
  });
  @override
  Widget build(BuildContext context) => _UsageCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 20),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('—'),
          ),
        for (final row in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: _UsageRow(row: row, unavailableLabel: unavailableLabel),
          ),
      ],
    ),
  );
}

class _UsageRow extends StatelessWidget {
  final UsageEntry row;
  final String unavailableLabel;
  const _UsageRow({required this.row, required this.unavailableLabel});
  @override
  Widget build(BuildContext context) {
    final avatars = objects(row.entity['avatars']);
    final tooltip = GlobalKey<TooltipState>();
    final color = avatars.isEmpty
        ? _colors[0]
        : Color(
            int.parse('${avatars.first['color']}'.substring(1), radix: 16) |
                0xff000000,
          );
    return Tooltip(
      key: tooltip,
      message:
          '${row.nodeName}\n${row.title}\n${usageNumber(row.amount.total)} Token${row.amount.unavailable > 0 ? '\n$unavailableLabel' : ''}',
      child: InkWell(
        key: ValueKey('usage-row-${row.nodeId}-${row.entity['id']}'),
        onTap: () => tooltip.currentState?.ensureTooltipVisible(),
        child: Row(
          children: [
            if (row.entity['group'] == true)
              GroupAvatar(avatars: avatars, size: 42)
            else if (avatars.isNotEmpty)
              CatAvatar(
                color: '${avatars.first['color']}',
                shape: '${avatars.first['shape']}',
                size: 42,
              ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${row.percent.toStringAsFixed(1)}%',
                    style: TextStyle(color: context.tone.ink2),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: row.percent / 100,
                      minHeight: 5,
                      color: color,
                      backgroundColor: context.tone.raised,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UsageCalendar extends StatelessWidget {
  final UsageSummary data;
  final int? year;
  final String unavailableLabel;
  const UsageCalendar({
    super.key,
    required this.data,
    this.year,
    required this.unavailableLabel,
  });
  @override
  Widget build(BuildContext context) {
    final first = year == null ? data.from : DateTime(year!, 1, 1);
    final last = year == null
        ? data.to
        : (year == data.to.year ? data.to : DateTime(year!, 12, 31));
    final start = DateTime.utc(
      first.year,
      first.month,
      first.day - first.weekday + 1,
    );
    final end = DateTime.utc(last.year, last.month, last.day);
    final weeks = (end.difference(start).inDays + 1) / 7;
    final max = data.days.values.fold(
      0,
      (value, day) => math.max(value, day.total),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int week = 0; week < weeks.ceil(); week++)
            Column(
              children: [
                SizedBox(
                  height: 23,
                  width: 23,
                  child: Text(
                    start.add(Duration(days: week * 7)).day <= 7
                        ? '${start.add(Duration(days: week * 7)).month}'
                        : '',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                for (int day = 0; day < 7; day++)
                  Builder(
                    builder: (context) {
                      final date = start.add(Duration(days: week * 7 + day));
                      final key = usageDate(date);
                      final available =
                          key.compareTo(usageDate(first)) >= 0 &&
                          !date.isAfter(end);
                      final value = data.days[key]?.total ?? 0;
                      final unknown = data.days[key]?.unavailable ?? 0;
                      final tooltip = GlobalKey<TooltipState>();
                      return Tooltip(
                        key: tooltip,
                        message:
                            '$key\n${usageNumber(value)} Token${unknown > 0 ? '\n$unavailableLabel' : ''}',
                        child: GestureDetector(
                          key: ValueKey('usage-day-$key'),
                          onTap: available
                              ? () =>
                                    tooltip.currentState?.ensureTooltipVisible()
                              : null,
                          child: Container(
                            width: 19,
                            height: 19,
                            margin: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(3),
                              color: !available
                                  ? Colors.transparent
                                  : value == 0
                                  ? context.tone.raised
                                  : Color.lerp(
                                      _colors[0].withValues(alpha: .2),
                                      _colors[0],
                                      max == 0 ? 0 : math.sqrt(value / max),
                                    ),
                            ),
                            child: unknown > 0
                                ? Center(
                                    child: Text(
                                      '·',
                                      style: TextStyle(color: context.tone.ink),
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
