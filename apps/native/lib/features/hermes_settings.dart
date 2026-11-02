import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/client.dart';
import '../ui/design.dart';

class HermesSettings extends StatefulWidget {
  final NekodotClient client;
  final String botId;
  const HermesSettings({super.key, required this.client, required this.botId});

  @override
  State<HermesSettings> createState() => _HermesSettingsState();
}

class _HermesSettingsState extends State<HermesSettings> {
  final search = TextEditingController();
  String query = '';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AsyncPane(
    load: () =>
        widget.client.rpc('hermes.settings.get', {'botId': widget.botId}),
    builder: (context, data, reload) {
      final all = objects(data['fields']);
      final filtered = all.where((field) {
        final text = '${field['key']} ${field['description']}'.toLowerCase();
        return text.contains(query.toLowerCase());
      }).toList();
      final categories = <String>[
        ...strings(data['categories']),
        ...filtered
            .map((field) => '${field['category']}')
            .where(
              (category) => !strings(data['categories']).contains(category),
            )
            .toSet(),
      ];
      return PageList(
        children: [
          TextField(
            controller: search,
            onChanged: (value) => setState(() => query = value),
            decoration: InputDecoration(
              hintText: widget.client.tr(
                '搜索 Hermes 设置',
                'Search Hermes settings',
              ),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: widget.client.tr('清除搜索', 'Clear search'),
                      onPressed: () {
                        search.clear();
                        setState(() => query = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.client.tr(
              '由 Hermes 提供 · 作用范围：此 Bot 的 profile',
              'Provided by Hermes · Scope: this Bot profile',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final category in categories)
            if (filtered.any((field) => field['category'] == category)) ...[
              SectionLabel(_categoryName(widget.client, category)),
              PanelGroup(
                children: [
                  for (final field in filtered.where(
                    (field) => field['category'] == category,
                  ))
                    if (field['type'] == 'boolean' &&
                        field['sensitive'] != true)
                      SwitchListTile.adaptive(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                        ),
                        title: Text('${field['key']}'),
                        subtitle: Text(
                          '${field['description']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        value: field['value'] == true,
                        onChanged: field['editable'] == true
                            ? (value) => _save(field, value, reload)
                            : null,
                      )
                    else
                      ListTile(
                        title: Text('${field['key']}'),
                        subtitle: Text(
                          [
                            '${field['description']}',
                            _valueLabel(widget.client, field),
                            if (field['editable'] != true &&
                                field['sensitive'] != true)
                              widget.client.tr(
                                '修改请前往 Bot 模型设置',
                                'Change this in Bot model settings',
                              ),
                          ].join('\n'),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: field['sensitive'] == true
                            ? const Icon(Icons.lock_outline, size: 18)
                            : field['editable'] == true
                            ? const Icon(Icons.chevron_right)
                            : null,
                        onTap: field['editable'] != true
                            ? null
                            : () => _edit(field, reload),
                      ),
                ],
              ),
            ],
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  widget.client.tr('没有匹配的设置', 'No matching settings'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
        ],
      );
    },
  );

  Future<void> _save(Json field, Object? value, VoidCallback reload) async {
    try {
      await widget.client.rpc('hermes.settings.set', {
        'botId': widget.botId,
        'key': field['key'],
        'value': value,
      });
      if (!mounted) return;
      reload();
      showNotice(
        context,
        widget.client.tr('已保存到 Hermes profile', 'Saved to Hermes profile'),
      );
    } catch (error) {
      if (mounted) showNotice(context, '$error');
    }
  }

  Future<void> _edit(Json field, VoidCallback reload) async {
    final type = '${field['type']}';
    final initial = field['value'];
    final controller = TextEditingController(
      text: type == 'list' || type == 'object'
          ? const JsonEncoder.withIndent('  ').convert(initial)
          : initial is String
          ? initial
          : initial == null
          ? ''
          : '$initial',
    );
    final options = (field['options'] as List? ?? const []).toList();
    final selected = <String, Object?>{
      for (final (index, option) in options.indexed) 'option:$index': option,
    };
    if (initial != null && !selected.values.contains(initial)) {
      selected['current'] = initial;
    }
    if (field['clearable'] == true) selected['clear'] = null;
    final initialSelection = selected.entries
        .where((entry) => entry.value == initial)
        .firstOrNull
        ?.key;
    String? selectedKey = initialSelection;
    String? error;
    final result = await showDialog<({Object? value})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: Text('${field['key']}'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: type == 'select'
                      ? DropdownButtonFormField<String>(
                          initialValue: selectedKey,
                          items: [
                            for (final entry in selected.entries)
                              DropdownMenuItem(
                                value: entry.key,
                                child: Text(
                                  entry.key == 'clear' ? '—' : '${entry.value}',
                                ),
                              ),
                          ],
                          onChanged: (key) =>
                              updateDialog(() => selectedKey = key),
                        )
                      : TextField(
                          controller: controller,
                          autofocus: true,
                          keyboardType: type == 'number'
                              ? const TextInputType.numberWithOptions(
                                  decimal: true,
                                )
                              : null,
                          minLines: type == 'list' || type == 'object' ? 8 : 1,
                          maxLines: type == 'list' || type == 'object' ? 16 : 3,
                          decoration: InputDecoration(
                            helperText: type == 'list' || type == 'object'
                                ? 'JSON'
                                : '${field['description']}',
                          ),
                        ),
                ),
                if (error != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: TextStyle(color: context.tone.danger),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(widget.client.tr('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final Object? edited = switch (type) {
                    'select' => selected[selectedKey],
                    'number' => num.parse(controller.text.trim()),
                    'list' || 'object' => jsonDecode(controller.text),
                    _ => controller.text,
                  };
                  if (type == 'list' && edited is! List) {
                    throw const FormatException('Expected a JSON array');
                  }
                  if (type == 'object' && (edited is! Map || edited is List)) {
                    throw const FormatException('Expected a JSON object');
                  }
                  Navigator.pop(dialogContext, (value: edited));
                } on FormatException catch (exception) {
                  updateDialog(() => error = exception.message);
                }
              },
              child: Text(widget.client.tr('保存', 'Save')),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result != null) await _save(field, result.value, reload);
  }
}

List<String> strings(Object? value) =>
    (value as List? ?? const []).whereType<String>().toList();

String _valueLabel(NekodotClient client, Json field) {
  if (field['sensitive'] == true) {
    return client.tr(
      field['configured'] == true ? '已配置 · 凭据由 Hermes 保管' : '未配置',
      field['configured'] == true
          ? 'Configured · credential held by Hermes'
          : 'Not configured',
    );
  }
  final value = field['value'];
  final display = value is String ? value : jsonEncode(value);
  return display.isEmpty || display == 'null'
      ? client.tr('未设置', 'Not set')
      : display;
}

String _categoryName(NekodotClient client, String category) =>
    switch (category) {
      'general' => client.tr('常规', 'General'),
      'agent' => 'Agent',
      'terminal' => client.tr('终端', 'Terminal'),
      'display' => client.tr('显示', 'Display'),
      'delegation' => client.tr('委派', 'Delegation'),
      'memory' => client.tr('记忆', 'Memory'),
      'compression' => client.tr('上下文压缩', 'Context compression'),
      'security' => client.tr('安全', 'Security'),
      'browser' => client.tr('浏览器', 'Browser'),
      'voice' || 'tts' || 'stt' => client.tr('语音', 'Voice'),
      'logging' => client.tr('日志', 'Logging'),
      _ => category,
    };
