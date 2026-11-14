import 'package:flutter/material.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../ui/design.dart';
import 'bot_model.dart';

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
      final compression = object(data['compression']);
      Future<void> edit() async {
        await pushPage(context, BotModelPage(client: client, botId: botId));
        reload();
      }

      return Column(
        children: [
          ListTile(
            key: const ValueKey('bot-model-settings'),
            title: Text(client.tr('模型', 'Model')),
            subtitle: Text('${data['model']}'),
            trailing: const Icon(Symbols.chevron_right),
            onTap: edit,
          ),
          ExpansionTile(
            title: Text(client.tr('模型与压缩', 'Model & compression')),
            children: [
              ListTile(
                key: const ValueKey('edit-context-length'),
                title: Text(client.tr('最大上下文', 'Maximum context')),
                subtitle: Text('${data['effectiveContext'] ?? '—'}'),
                trailing: const Icon(Symbols.edit, size: 18),
                onTap: edit,
              ),
              ListTile(
                title: Text(client.tr('最大输出', 'Maximum output')),
                trailing: Text('${data['detectedMaxOutput'] ?? '—'}'),
              ),
              ListTile(
                title: Text(client.tr('自动压缩', 'Auto compression')),
                trailing: Text(
                  compression['enabled'] == true
                      ? client.tr('开', 'On')
                      : client.tr('关', 'Off'),
                ),
              ),
              ListTile(
                title: Text(client.tr('近期次数', 'Recent count')),
                trailing: Text('${compression['count'] ?? '—'}'),
              ),
            ],
          ),
        ],
      );
    },
  );
}
