import 'package:flutter/material.dart';

import '../data/client.dart';
import '../ui/design.dart';

class ModelInformation extends StatelessWidget {
  final NekodotClient client;
  final String botId;
  const ModelInformation({
    super.key,
    required this.client,
    required this.botId,
  });
  @override
  Widget build(BuildContext context) => AsyncPane(
    load: () => client.rpc('models.info', {'botId': botId}),
    builder: (context, data, reload) {
      final compression = data['compression'] as Map;
      String number(Object? value) =>
          value == null ? client.tr('未知', 'Unknown') : '$value';
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      client.tr('模型与压缩', 'Model & compression'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: client.tr('刷新', 'Refresh'),
                    onPressed: reload,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              SelectableText('${data['provider']} · ${data['model']}'),
              const SizedBox(height: 12),
              Text(
                '${client.tr('原生识别上下文', 'Native detected context')}: ${number(data['detectedContext'])}',
              ),
              Text(
                '${client.tr('配置上下文', 'Configured context')}: ${number(data['configuredContext'])}',
              ),
              Text(
                '${client.tr('有效上下文', 'Effective context')}: ${number(data['effectiveContext'])}',
              ),
              Text(
                '${client.tr('最大输出', 'Maximum output')}: ${number(data['detectedMaxOutput'])}',
              ),
              const SizedBox(height: 8),
              Text(
                client.tr(
                  '容量来自 Hermes 原生解析与模型元数据，不代表已实测极限。当前版本没有通用最大输出覆盖。',
                  'Limits come from the native Hermes resolver and metadata, not measured stress tests. This version has no generic output override.',
                ),
              ),
              const Divider(height: 24),
              Text(
                '${client.tr('原生压缩', 'Native compression')}: ${compression['enabled'] == true ? client.tr('已开启', 'Enabled') : client.tr('已关闭', 'Disabled')}',
              ),
              Text(
                '${client.tr('配置触发阈值', 'Configured trigger')}: ${compression['threshold'] == null ? client.tr('未知', 'Unknown') : '${((compression['threshold'] as num) * 100).round()}%'}${compression['thresholdTokens'] != null ? ' / ${compression['thresholdTokens']} tokens' : ''}',
              ),
              Text(
                '${client.tr('原生实际触发量', 'Native effective trigger')}: ${number(compression['effectiveThresholdTokens'])} tokens',
              ),
              Text(
                '${client.tr('原生观测次数', 'Native observed count')}: ${number(compression['count'])}',
              ),
              const SizedBox(height: 8),
              Text(
                client.tr(
                  '仅统计最近最多 500 行原生压缩日志，不是历史总数。没有记录时显示未知；实际触发量来自当前模型与上下文的原生记录，并非客户端估算。',
                  'Shows up to 500 recent native log lines, not a lifetime total. No records means unknown. The effective trigger comes from a native record for this model and context, not a client estimate.',
                ),
              ),
              for (final record in objects(compression['records']))
                SelectableText('$record'),
            ],
          ),
        ),
      );
    },
  );
}
