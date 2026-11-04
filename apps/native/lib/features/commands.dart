import 'package:flutter/material.dart';

import '../data/client.dart';
import '../ui/design.dart';
import 'bot_editor.dart';
import 'extensions.dart';
import 'hermes_settings.dart';
import 'sessions.dart';
import 'settings.dart';
import 'learning.dart';
import 'pets.dart';
import 'subscription.dart';
import 'voice.dart';

Future<void> openCommandPage(
  BuildContext context,
  NekodotClient client,
  String page,
  String botId, [
  String argument = '',
]) async {
  final bot = client.node.bots
      .where((bot) => bot['botId'] == botId)
      .firstOrNull;
  if (bot == null) return;
  final Widget? destination = switch (page) {
    'settings' => AppPage(
      title: client.tr('Hermes 设置', 'Hermes settings'),
      body: HermesSettings(client: client, botId: botId),
    ),
    'model' => BotEditor(client: client, existing: bot),
    'profile-import' => BotEditor(client: client, importProfile: true),
    'plugins' => ExtensionsPage(client: client, kind: 'plugins'),
    'sessions' => BotSessionsPage(client: client, botId: botId),
    'sources' => SourcesPage(client: client),
    'journey' =>
      argument.isEmpty
          ? LearningPage(client: client, botId: botId)
          : LearningEntryPage(client: client, botId: botId, entryId: argument),
    'pets' => PetsPage(client: client, botId: botId),
    'hatch' => PetsPage(client: client, botId: botId, hatchPrompt: argument),
    'subscription' => SubscriptionPage(client: client, botId: botId),
    'voice' => VoicePage(client: client, botId: botId),
    _ => null,
  };
  if (destination != null) await pushPage(context, destination);
}

class CommandPalette extends StatelessWidget {
  final NekodotClient client;
  final List<Json> entries, members;
  final String query, botId;
  final bool loading;
  final ValueChanged<String> onBot;
  final ValueChanged<String> onSelect;
  final VoidCallback onRefresh;
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
    required this.onRefresh,
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
    final usable = filtered
        .where((entry) => ['available', 'app'].contains(entry['availability']))
        .toList();
    final other = filtered
        .where((entry) => !['available', 'app'].contains(entry['availability']))
        .toList();
    Widget commandRow(Json entry) => ListTile(
      dense: true,
      title: Text('${entry['name']}'),
      subtitle: Text(
        '${entry['unavailableReason'] ?? entry['description']}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: switch (entry['availability']) {
        'app' => Text(client.tr('App 适配', 'App action')),
        'terminal' => Text(client.tr('服务器终端', 'Server terminal')),
        'not-integrated' => Text(client.tr('待接入', 'Not connected')),
        _ => null,
      },
      enabled: ['available', 'app'].contains(entry['availability']),
      onTap: () => onSelect('${entry['name']}'),
    );
    return Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const SizedBox(width: 12),
              const Expanded(child: Text('Hermes')),
              IconButton(
                tooltip: client.tr('刷新指令', 'Refresh commands'),
                onPressed: loading ? null : onRefresh,
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ],
          ),
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
          if (loading) const ShiningText(),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 230),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final entry in usable) commandRow(entry),
                if (other.isNotEmpty)
                  ExpansionTile(
                    title: Text(
                      client.tr(
                        '其它指令 (${other.length})',
                        'Other commands (${other.length})',
                      ),
                    ),
                    subtitle: Text(
                      client.tr(
                        '仅适用于服务器终端，或仍需客户端适配。',
                        'Server-terminal commands or client adapters not yet connected.',
                      ),
                    ),
                    children: [for (final entry in other) commandRow(entry)],
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
