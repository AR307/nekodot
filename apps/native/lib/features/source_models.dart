import 'dart:async';

import 'package:flutter/material.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../ui/design.dart';

/// Both OAuth and custom sources use the native provider inventory.
class SourceModels extends StatefulWidget {
  final NekodotClient client;
  final String sourceId;
  const SourceModels({super.key, required this.client, required this.sourceId});
  @override
  State<SourceModels> createState() => _SourceModelsState();
}

class _SourceModelsState extends State<SourceModels> {
  final scroll = ScrollController();
  List<String> models = [];
  String query = '', error = '', selected = '';
  bool loading = true, testing = false;
  Json? detail;
  NekodotClient get c => widget.client;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final result = await c.rpc('models.options', {
        'sourceId': widget.sourceId,
        'refresh': true,
      });
      if (!mounted) return;
      setState(() {
        models = (result['models'] as List).cast<String>();
        error = '${result['warning'] ?? ''}';
        if (!models.contains(selected)) {
          selected = '';
          detail = null;
        }
      });
      if (selected.isNotEmpty) await choose(selected, refresh: true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> choose(String model, {bool refresh = false}) async {
    setState(() {
      selected = model;
      detail = null;
      error = '';
    });
    try {
      final result = await c.rpc('models.describe', {
        'sourceId': widget.sourceId,
        'model': model,
        'refresh': refresh,
      });
      if (mounted && selected == model) setState(() => detail = result);
    } catch (_) {
      if (mounted && selected == model) {
        setState(() => error = c.tr('目录获取失败', 'Catalog unavailable'));
      }
    }
  }

  Future<void> test() async {
    setState(() {
      testing = true;
      error = '';
    });
    try {
      var op = await c.rpc('providers.test', {
        'sourceId': widget.sourceId,
        'model': selected,
      });
      while (op['status'] == 'running' && mounted) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        op = await c.rpc('operations.get', {'operationId': op['operationId']});
      }
      if (!mounted) return;
      if (op['status'] == 'done') {
        final actual = objects(op['results'])
            .firstOrNull?['native']?['apiMode'];
        if (detail != null && actual is String && actual.isNotEmpty) {
          setState(() => detail = {...detail!, 'apiMode': actual});
        }
        showNotice(context, c.tr('连通性测试通过', 'Connection test passed'));
      } else {
        setState(() => error = '${op['detail']}');
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = models
        .where((m) => m.toLowerCase().contains(query.toLowerCase()))
        .toList();
    final rowHeight = context.tone.glass ? 52.0 : 40.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                c.tr('${models.length} 个模型', '${models.length} models'),
                key: const ValueKey('source-model-count'),
              ),
            ),
            IconButton(
              tooltip: c.tr('刷新', 'Refresh'),
              onPressed: loading || testing ? null : load,
              icon: const Icon(Symbols.refresh),
            ),
          ],
        ),
        if (loading) const LinearProgressIndicator(minHeight: 2),
        TextField(
          key: const ValueKey('source-model-search'),
          decoration: InputDecoration(
            prefixIcon: const Icon(Symbols.search),
            hintText: c.tr('搜索模型', 'Search models'),
          ),
          onChanged: (v) {
            setState(() => query = v);
            if (scroll.hasClients) scroll.jumpTo(0);
          },
        ),
        SizedBox(
          height: (filtered.length * rowHeight).clamp(0, 260),
          child: ListView.builder(
            controller: scroll,
            itemExtent: rowHeight,
            itemCount: filtered.length,
            itemBuilder: (context, i) => ListTile(
              key: ValueKey('source-model-${filtered[i]}'),
              dense: !context.tone.glass,
              title: Text(
                filtered[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              selected: selected == filtered[i],
              trailing: selected == filtered[i]
                  ? const Icon(Symbols.check, size: 18)
                  : null,
              onTap: testing ? null : () => choose(filtered[i]),
            ),
          ),
        ),
        if (selected.isNotEmpty) ...[
          if (detail != null) ModelCapabilities(client: c, data: detail!),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('source-test'),
              onPressed: testing || loading ? null : test,
              icon: testing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Symbols.network_check, size: 18),
              label: Text(c.tr('测试连通性', 'Test connection')),
            ),
          ),
        ],
        ErrorNotice(error),
      ],
    );
  }
}

class ModelCapabilities extends StatelessWidget {
  final NekodotClient client;
  final Json data;
  const ModelCapabilities({
    super.key,
    required this.client,
    required this.data,
  });
  @override
  Widget build(BuildContext context) {
    final c = client;
    if (data['catalogProvider'] == null) {
      return Text(c.tr('目录未收录', 'Not in catalog'));
    }
    final parameters = (data['parameters'] as List).join(' · ');
    final levels = (data['reasoningLevels'] as List).join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'models.dev · ${data['catalogProvider']}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        SelectableText(
          '${c.tr('接口', 'API')}: ${data['apiMode'] == null || data['apiMode'] == '' ? c.tr('自动', 'Automatic') : data['apiMode']}',
        ),
        if (data['sdk'] != null) SelectableText('SDK: ${data['sdk']}'),
        if (data['api'] != null) SelectableText('${data['api']}'),
        if (parameters.isNotEmpty)
          Text('${c.tr('支持参数', 'Supported parameters')}: $parameters'),
        if (levels.isNotEmpty)
          Text('${c.tr('思考等级', 'Reasoning effort')}: $levels'),
        if (data['context'] != null)
          Text('${c.tr('最大上下文', 'Maximum context')}: ${data['context']}'),
      ],
    );
  }
}
