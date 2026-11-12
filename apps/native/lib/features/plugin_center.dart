import 'package:flutter/material.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../local/runtime.dart';
import '../ui/design.dart';
import 'connectors.dart';
import 'extensions.dart';
import 'mcp.dart';
import 'local_setup.dart';
import 'pairing.dart';

Future<void> showPluginCenter(BuildContext context, NekodotClient client) =>
    openPage(context, PluginCenterPage(client: client));

class PluginCenterPage extends StatefulWidget {
  final NekodotClient client;
  final String kind;
  const PluginCenterPage({
    super.key,
    required this.client,
    this.kind = 'skills',
  });
  @override
  State<PluginCenterPage> createState() => _PluginCenterPageState();
}

class _PluginCenterPageState extends State<PluginCenterPage> {
  late String kind = widget.client.selectedNodeId == null
      ? 'connectors'
      : widget.kind;
  late final visited = <String>{kind};
  static const icons = {
    'skills': Icons.auto_awesome_outlined,
    'plugins': Icons.extension_outlined,
    'mcp': Icons.hub_outlined,
    'connectors': Icons.link,
  };
  void select(String value) => setState(() {
    kind = value;
    visited.add(value);
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.client,
    builder: (context, _) {
      final c = widget.client;
      final tone = context.tone;
      final labels = {
        'skills': 'Skills',
        'plugins': c.tr('插件', 'Plugins'),
        'mcp': 'MCP',
        'connectors': c.tr('连接器', 'Connectors'),
      };
      final nodes = objects(c.account.me?['nodes']);
      final selected = nodes
          .where((n) => n['nodeId'] == c.selectedNodeId)
          .firstOrNull;
      void addComputer() => openPage(
        context,
        localRuntime == null
            ? PairingPage(client: c)
            : RunLocationPage(client: c),
      );
      final scope = kind == 'connectors'
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_outline, size: 16, color: tone.ink2),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${c.account.me?['user']?['email'] ?? c.tr('账户', 'Account')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            )
          : ActionMenu<String>(
              key: const ValueKey('plugin-center-computer'),
              tooltip: c.tr('电脑', 'Computer'),
              items: [
                for (final node in nodes)
                  MenuAction(
                    value: '${node['nodeId']}',
                    label: '${node['name']}',
                    leading: StatusDot(
                      on: c.nodes[node['nodeId']]?.online == true,
                      size: 7,
                    ),
                    selected: node['nodeId'] == c.selectedNodeId,
                  ),
                if (nodes.isNotEmpty) null,
                MenuAction(
                  value: '',
                  label: c.tr('添加电脑', 'Add computer'),
                  icon: Icons.add_to_queue_outlined,
                ),
              ],
              onSelected: (id) {
                if (id.isEmpty) {
                  addComputer();
                } else {
                  c.selectNode(id);
                }
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusDot(on: c.online, size: 7),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '${selected?['name'] ?? c.tr('电脑', 'Computer')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.expand_more, size: 16),
                    ],
                  ),
                ),
              ),
            );
      return AppPage(
        title: c.tr('插件中心', 'Plugin center'),
        body: ColoredBox(
          color: tone.base,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide =
                  !tone.glass &&
                  constraints.maxWidth >= 720 &&
                  MediaQuery.textScalerOf(context).scale(14) <= 20;
              final content = Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Row(
                      children: [
                        if (!wide) ...[
                          ActionMenu<String>(
                            key: const ValueKey('plugin-kind-menu'),
                            tooltip: c.tr('插件中心', 'Plugin center'),
                            items: [
                              for (final entry in labels.entries)
                                MenuAction(
                                  key: ValueKey('plugin-kind-${entry.key}'),
                                  value: entry.key,
                                  label: entry.value,
                                  icon: icons[entry.key],
                                  selected: kind == entry.key,
                                ),
                            ],
                            onSelected: select,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(icons[kind], size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    labels[kind]!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.expand_more, size: 16),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                        ],
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: scope,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: IndexedStack(
                      index: icons.keys.toList().indexOf(kind),
                      children: [
                        for (final item in icons.keys)
                          TickerMode(
                            enabled: item == kind,
                            child: !visited.contains(item)
                                ? const SizedBox.shrink()
                                : item == 'connectors'
                                ? ConnectorsBody(
                                    key: ValueKey(
                                      c.account.me?['user']?['userId'],
                                    ),
                                    client: c,
                                  )
                                : c.selectedNodeId == null
                                ? Center(
                                    child: TextButton.icon(
                                      onPressed: addComputer,
                                      icon: const Icon(
                                        Icons.add_to_queue_outlined,
                                      ),
                                      label: Text(c.tr('添加电脑', 'Add computer')),
                                    ),
                                  )
                                : item == 'mcp'
                                ? McpBody(
                                    key: ValueKey(c.selectedNodeId),
                                    client: c,
                                  )
                                : ExtensionsBody(
                                    key: ValueKey('$item:${c.selectedNodeId}'),
                                    client: c,
                                    kind: item,
                                  ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide)
                    SizedBox(
                      width: 176,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                        child: Column(
                          children: [
                            for (final entry in labels.entries)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: TextButton(
                                  key: ValueKey('plugin-kind-${entry.key}'),
                                  onPressed: () => select(entry.key),
                                  style: TextButton.styleFrom(
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                    foregroundColor: kind == entry.key
                                        ? tone.ink
                                        : tone.ink2,
                                    backgroundColor: kind == entry.key
                                        ? tone.hover
                                        : Colors.transparent,
                                    shape: RoundedSuperellipseBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(icons[entry.key], size: 18),
                                      const SizedBox(width: 12),
                                      Text(entry.value),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(child: content),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}
