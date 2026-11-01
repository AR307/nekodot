import 'package:flutter/material.dart';

import '../data/client.dart';
import '../ui/design.dart';

class CommandPalette extends StatelessWidget {
  final NekodotClient client;
  final List<Json> entries, members;
  final String query, botId;
  final bool loading;
  final ValueChanged<String> onBot;
  final ValueChanged<String> onSelect;
  const CommandPalette({
    super.key,
    required this.client,
    required this.entries,
    required this.members,
    required this.query,
    required this.botId,
    required this.loading,
    required this.onBot,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final filtered = entries
        .where(
          (entry) => '${entry['name']} ${entry['description']}'
              .toLowerCase()
              .contains(query.toLowerCase()),
        )
        .toList();
    return Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (members.length > 1)
            DropdownButtonFormField<String>(
              key: ValueKey(botId),
              initialValue: botId,
              items: [
                for (final bot in members)
                  DropdownMenuItem(
                    value: '${bot['botId']}',
                    child: Text('${bot['displayName']}'),
                  ),
              ],
              onChanged: (value) {
                if (value != null) onBot(value);
              },
              decoration: InputDecoration(
                labelText: client.tr('执行指令的 Bot', 'Run command as'),
              ),
            ),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 230),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final entry in filtered)
                  ListTile(
                    dense: true,
                    title: Text('${entry['name']}'),
                    subtitle: Text(
                      '${entry['description']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: entry['availability'] == 'terminal'
                        ? Text(client.tr('仅终端', 'Terminal only'))
                        : entry['availability'] == 'native-ui'
                        ? Text(client.tr('需原生会话界面', 'Hermes session UI'))
                        : null,
                    enabled: ![
                      'terminal',
                      'native-ui',
                    ].contains(entry['availability']),
                    onTap: () => onSelect('${entry['name']}'),
                  ),
                if (!loading && filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      client.tr('没有匹配的原生命令', 'No matching native commands'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
