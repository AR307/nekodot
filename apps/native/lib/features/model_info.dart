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
      final text = Theme.of(context).textTheme;
      String number(Object? value) => value == null ? '—' : '$value';
      Widget fact(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: text.bodySmall)),
            Text(
              value,
              style: const TextStyle(fontFamily: monoFont, fontSize: 13),
            ),
          ],
        ),
      );
      return Panel(
        child: ExpansionTile(
          title: Text(client.tr('模型与压缩', 'Model & compression')),
          subtitle: SelectableText(
            '${data['provider']} · ${data['model']}',
            style: text.bodySmall,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            fact(
              client.tr('有效上下文', 'Effective context'),
              number(data['effectiveContext']),
            ),
            fact(
              client.tr('检测上下文', 'Detected context'),
              number(data['detectedContext']),
            ),
            fact(
              client.tr('配置上下文', 'Configured context'),
              number(data['configuredContext']),
            ),
            fact(
              client.tr('最大输出', 'Maximum output'),
              number(data['detectedMaxOutput']),
            ),
            const Divider(height: 20),
            fact(
              client.tr('压缩', 'Compression'),
              compression['enabled'] == true
                  ? client.tr('开', 'On')
                  : client.tr('关', 'Off'),
            ),
            fact(
              client.tr('配置阈值', 'Configured trigger'),
              '${compression['threshold'] == null ? '—' : '${((compression['threshold'] as num) * 100).round()}%'}${compression['thresholdTokens'] != null ? ' / ${compression['thresholdTokens']}' : ''}',
            ),
            fact(
              client.tr('实际阈值', 'Effective trigger'),
              number(compression['effectiveThresholdTokens']),
            ),
            fact(
              client.tr('近期次数', 'Recent count'),
              number(compression['count']),
            ),
            for (final record in objects(compression['records']))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SelectableText('$record', style: text.bodySmall),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: client.tr('刷新', 'Refresh'),
                onPressed: reload,
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
            ),
          ],
        ),
      );
    },
  );
}
