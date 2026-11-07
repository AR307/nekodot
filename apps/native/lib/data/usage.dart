import 'dart:convert';
import 'dart:typed_data';

import 'json.dart';

class UsageAmount {
  final Map<String, int> tokens;
  final int total, unavailable;
  UsageAmount(Json json)
    : tokens = {
        for (final key in ['input', 'output', 'cacheRead', 'cacheWrite'])
          key: (json['tokens'][key] as num).toInt(),
      },
      total = (json['total'] as num).toInt(),
      unavailable = (json['unavailable'] as num).toInt();
}

class UsageEntry {
  final Json entity;
  final String nodeId, nodeName, date;
  final double percent;
  final UsageAmount amount;
  UsageEntry(Json json)
    : entity = object(json['entity']),
      nodeId = json['nodeId'] as String,
      nodeName = json['nodeName'] as String,
      date = json['date'] as String? ?? '',
      percent = (json['percent'] as num?)?.toDouble() ?? 0,
      amount = UsageAmount(json);
  String get title => entity['kind'] == 'routine'
      ? '${entity['ownerName']} · ${entity['name']}'
      : '${entity['name']}';
}

class UsageSummary {
  final DateTime from, to;
  final UsageAmount totals;
  final Map<String, UsageAmount> days;
  final List<UsageEntry> conversations, routines, rows;
  final List<Json> nodes;
  UsageSummary(Json json)
    : from = DateTime.parse(json['from'] as String),
      to = DateTime.parse(json['to'] as String),
      totals = UsageAmount(json['totals']),
      days = {
        for (final d in objects(json['days']))
          d['date'] as String: UsageAmount(d),
      },
      conversations = objects(json['conversations'])
          .map(UsageEntry.new)
          .toList(),
      routines = objects(json['routines']).map(UsageEntry.new).toList(),
      rows = objects(json['rows']).map(UsageEntry.new).toList(),
      nodes = objects(json['nodes']);
}

String usageDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
String usageNumber(int value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);

Uint8List usageCsv(UsageSummary summary) {
  String cell(Object? value) {
    var text = '$value';
    // CSV names are user-authored; opening in a spreadsheet must not run a formula.
    if (RegExp(r'^[=+@\-\t\r]').hasMatch(text)) text = "'$text";
    return '"${text.replaceAll('"', '""')}"';
  }

  final rows = <List<Object?>>[
    [
      'date',
      'node_id',
      'node',
      'kind',
      'entity_id',
      'owner',
      'name',
      'input',
      'output',
      'cache_read',
      'cache_write',
      'total',
      'unavailable',
    ],
    for (final row in summary.rows)
      [
        row.date,
        row.nodeId,
        row.nodeName,
        row.entity['kind'],
        row.entity['id'],
        row.entity['ownerName'],
        row.entity['name'],
        row.amount.tokens['input'],
        row.amount.tokens['output'],
        row.amount.tokens['cacheRead'],
        row.amount.tokens['cacheWrite'],
        row.amount.total,
        row.amount.unavailable,
      ],
  ];
  return Uint8List.fromList(
    utf8.encode(
      '\uFEFF${rows.map((row) => row.map(cell).join(',')).join('\r\n')}\r\n',
    ),
  );
}
