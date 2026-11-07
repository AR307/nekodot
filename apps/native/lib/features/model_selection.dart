import 'package:flutter/material.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../ui/design.dart';

/// One catalog-backed picker for creating a Bot and changing its model.
class ModelSelection extends StatefulWidget {
  final NekodotClient client;
  final String? sourceId;
  final String model;
  final bool enabled;
  final void Function(String sourceId, String model) onChanged;
  const ModelSelection({
    super.key,
    required this.client,
    required this.sourceId,
    required this.model,
    required this.onChanged,
    this.enabled = true,
  });
  @override
  State<ModelSelection> createState() => _ModelSelectionState();
}

class _ModelSelectionState extends State<ModelSelection> {
  List<Json> sources = [];
  List<String> models = [];
  String? source;
  String model = '', error = '';
  bool loading = true;
  NekodotClient get c => widget.client;

  @override
  void initState() {
    super.initState();
    source = widget.sourceId;
    model = widget.model;
    loadSources();
  }

  Future<void> loadSources() async {
    try {
      final rows = objects((await c.rpc('providers.list'))['sources'])
          .where((row) => row['ready'] == true)
          .toList();
      if (!mounted) return;
      setState(() {
        sources = rows;
        if (!rows.any((row) => row['sourceId'] == source)) {
          source = rows.firstOrNull?['sourceId'] as String?;
          model = '';
        }
      });
      if (source != null) {
        await loadModels();
      } else {
        setState(() {
          loading = false;
          error = c.tr('暂无模型来源', 'No model sources');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  Future<void> loadModels({bool refresh = true}) async {
    final selected = source!;
    setState(() {
      loading = true;
      error = '';
      models = [];
    });
    try {
      final result = await c.rpc('models.options', {
        'sourceId': selected,
        'refresh': refresh,
      });
      if (!mounted || selected != source) return;
      setState(() {
        models = (result['models'] as List).cast<String>();
        loading = false;
        if (!models.contains(model)) model = '';
        if (models.isEmpty) {
          error =
              '${result['warning'] ?? c.tr('暂无可用模型', 'No available models')}';
        }
      });
      widget.onChanged(selected, model);
    } catch (e) {
      if (mounted && selected == source) {
        setState(() {
          error = '$e';
          loading = false;
          model = '';
        });
        widget.onChanged(selected, '');
      }
    }
  }

  Future<void> chooseModel() async {
    var query = '';
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(c.tr('选择模型', 'Choose model')),
          content: SizedBox(
            width: 440,
            height: 360,
            child: Column(
              children: [
                TextField(
                  key: const ValueKey('model-search'),
                  autofocus: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: c.tr('搜索模型', 'Search models'),
                  ),
                  onChanged: (value) =>
                      update(() => query = value.toLowerCase()),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      for (final value in models.where(
                        (m) => m.toLowerCase().contains(query),
                      ))
                        ListTile(
                          key: ValueKey('model-option-$value'),
                          title: Text(value),
                          trailing: value == model
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () => Navigator.pop(context, value),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(c.tr('取消', 'Cancel')),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => model = selected);
    widget.onChanged(source!, selected);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LabeledField(
        label: c.tr('模型来源', 'Model source'),
        child: MenuSelect<String>(
          key: const ValueKey('model-source'),
          value: source,
          options: [
            for (final row in sources) ('${row['sourceId']}', '${row['name']}'),
          ],
          onChanged: !widget.enabled
              ? null
              : (value) {
                  setState(() {
                    source = value;
                    model = '';
                  });
                  widget.onChanged(value, '');
                  loadModels();
                },
        ),
      ),
      const SizedBox(height: 10),
      LabeledField(
        label: c.tr('模型', 'Model'),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('model-choice'),
                onPressed: widget.enabled && !loading && models.isNotEmpty
                    ? chooseModel
                    : null,
                child: Text(
                  loading
                      ? c.tr('读取模型…', 'Loading models…')
                      : model.isEmpty
                      ? c.tr('请选择模型', 'Choose a model')
                      : model,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            IconButton(
              tooltip: c.tr('刷新模型', 'Refresh models'),
              onPressed: widget.enabled && !loading
                  ? () => source == null
                        ? loadSources()
                        : loadModels(refresh: true)
                  : null,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
      ErrorNotice(error),
    ],
  );
}
