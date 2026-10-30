import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/client.dart';
import '../platform/desktop.dart';
import '../ui/design.dart';
import 'bot_details.dart';
import 'chat.dart';
import 'bot_editor.dart';
import 'extensions.dart';
import 'settings.dart';
import 'pairing.dart';

class HomePage extends StatefulWidget {
  final NekodotClient client;
  const HomePage({super.key, required this.client});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  StreamSubscription<Json>? destinations;
  String? conversation;
  Json? details;
  String search = '';
  bool searching = false;
  NekodotClient get c => widget.client;
  @override
  void initState() {
    super.initState();
    destinations = c.destinations.stream.listen(openDestination);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (c.pendingDestination != null) openDestination(c.pendingDestination!);
    });
  }

  Future<void> openDestination(Json target) async {
    c.pendingDestination = null;
    final nodeId = target['nodeId'] as String;
    if (!objects(c.me?['nodes']).any((n) => n['nodeId'] == nodeId)) return;
    await c.selectNode(nodeId);
    final value = c.node.conversations
        .where((v) => v['conversationId'] == target['conversationId'])
        .firstOrNull;
    if (value == null || !mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    await open(value, MediaQuery.sizeOf(context).width < 840);
  }

  @override
  void dispose() {
    destinations?.cancel();
    super.dispose();
  }

  Future<void> open(Json value, bool narrow) async {
    final id = value['conversationId'] as String;
    if (narrow) {
      await pushPage(context, ChatPage(client: c, conversationId: id));
    } else {
      setState(() {
        conversation = id;
        details = null;
      });
    }
  }

  Widget nodePicker() {
    final nodes = objects(c.me?['nodes']);
    final current = nodes
        .where((n) => n['nodeId'] == c.selectedNodeId)
        .firstOrNull;
    return PopupMenuButton<String>(
      tooltip: c.tr('电脑', 'Computer'),
      position: PopupMenuPosition.under,
      onSelected: (id) {
        if (id == '') {
          pushPage(context, PairingPage(client: c));
        } else {
          setState(() {
            conversation = null;
            details = null;
          });
          c.selectNode(id);
        }
      },
      itemBuilder: (_) => [
        for (final node in nodes)
          PopupMenuItem(
            value: node['nodeId'] as String,
            child: Row(
              children: [
                StatusDot(on: node['online'] == true),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${node['name']}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (node['nodeId'] == c.selectedNodeId)
                  const Icon(Icons.check_rounded, size: 18),
              ],
            ),
          ),
        if (nodes.isNotEmpty) const PopupMenuDivider(),
        PopupMenuItem(value: '', child: Text(c.tr('添加电脑', 'Add computer'))),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (current != null) ...[
              c.online || c.ready
                  ? StatusDot(on: c.online)
                  : const Breathing(size: 8),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                current == null
                    ? c.tr('添加电脑', 'Add computer')
                    : '${current['name']}',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 18, color: context.tone.ink3),
          ],
        ),
      ),
    );
  }

  Widget top() => Stack(
    children: [
      const Positioned.fill(child: WindowDrag()),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: nodePicker(),
              ),
            ),
            const SizedBox(width: 8),
            RoundButton(
              tooltip: c.tr('搜索', 'Search'),
              icon: searching ? Icons.close_rounded : Icons.search_rounded,
              onPressed: () => setState(() {
                searching = !searching;
                search = '';
              }),
            ),
            const SizedBox(width: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: floating(context),
              ),
              child: PopupMenuButton<String>(
                tooltip: c.tr('新建', 'Create'),
                position: PopupMenuPosition.under,
                icon: const Icon(Icons.add_rounded),
                style: roundStyle(context),
                onSelected: (value) => pushPage(
                  context,
                  BotEditor(client: c, group: value == 'group'),
                ),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'bot',
                    child: Text(c.tr('新建 Bot', 'New Bot')),
                  ),
                  PopupMenuItem(
                    value: 'group',
                    child: Text(c.tr('新建群组', 'New group')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );

  /// Phone header: the mark, the computer, search.
  Widget glassTop() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
    child: Row(
      children: [
        const CatAvatar(size: 34),
        const SizedBox(width: 6),
        Expanded(
          child: Align(alignment: Alignment.centerLeft, child: nodePicker()),
        ),
        IconButton(
          tooltip: c.tr('搜索', 'Search'),
          isSelected: searching,
          onPressed: () => setState(() {
            searching = !searching;
            search = '';
          }),
          icon: const Icon(Icons.search_rounded),
        ),
      ],
    ),
  );

  /// Phone dock floating over the list: extensions, settings, create.
  Widget dock() {
    final tone = context.tone;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          Panel(
            radius: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Skills',
                  onPressed: () => pushPage(
                    context,
                    ExtensionsPage(client: c, kind: 'skills'),
                  ),
                  icon: const Icon(Icons.auto_awesome_rounded),
                ),
                IconButton(
                  tooltip: c.tr('插件', 'Plugins'),
                  onPressed: () => pushPage(
                    context,
                    ExtensionsPage(client: c, kind: 'plugins'),
                  ),
                  icon: const Icon(Icons.extension_rounded),
                ),
                IconButton(
                  tooltip: c.tr('设置', 'Settings'),
                  onPressed: () => pushPage(context, SettingsPage(client: c)),
                  icon: const Icon(Icons.tune_rounded),
                ),
              ],
            ),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            tooltip: c.tr('新建', 'Create'),
            position: PopupMenuPosition.over,
            icon: const Icon(Icons.add_rounded),
            iconColor: tone.base,
            style: IconButton.styleFrom(
              backgroundColor: tone.ink,
              fixedSize: const Size.square(50),
            ),
            onSelected: (value) => pushPage(
              context,
              BotEditor(client: c, group: value == 'group'),
            ),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'bot',
                child: Text(c.tr('新建 Bot', 'New Bot')),
              ),
              PopupMenuItem(
                value: 'group',
                child: Text(c.tr('新建群组', 'New group')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget row(Json value, bool narrow) {
    final glass = context.tone.glass;
    final isGroup = value['kind'] == 'group';
    final entity = isGroup
        ? c.node.groups.firstWhere((x) => x['groupId'] == value['groupId'])
        : c.node.bots.firstWhere((x) => x['botId'] == value['botId']);
    final id = value['conversationId'] as String;
    final state = c.node.activities[id]?['state'];
    final working = state != null && state != 'idle';
    final last = (c.node.messages[id] ?? [])
        .where((x) => x['kind'] == 'text')
        .lastOrNull;
    final preview = last?['content']['text'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: ListTile(
        key: ValueKey('conversation-$id'),
        selected: !narrow && conversation == id,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(glass ? 20 : 14),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        minVerticalPadding: 8,
        horizontalTitleGap: 10,
        leading: isGroup
            ? GroupAvatar(
                size: glass ? 38 : 42,
                working: working,
                colors: [
                  for (final bot in c.node.bots)
                    if ((entity['botIds'] as List).contains(bot['botId']))
                      '${bot['avatar']['color']}',
                ],
              )
            : CatAvatar(
                size: glass ? 38 : 42,
                color: '${entity['avatar']['color']}',
                working: working,
              ),
        title: Text(
          '${entity[isGroup ? 'name' : 'displayName']}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: preview == null
            ? null
            : Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () => open(value, narrow),
      ),
    );
  }

  Future<void> signOut() async {
    try {
      await c.logout();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Widget bottom(bool narrow) {
    final tone = context.tone;
    final email = '${c.me?['user']['email'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: PopupMenuButton<String>(
                tooltip: c.tr('账户', 'Account'),
                position: PopupMenuPosition.over,
                onSelected: (value) {
                  if (value == 'settings') {
                    pushPage(context, SettingsPage(client: c));
                  } else {
                    signOut();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'settings',
                    child: Row(
                      children: [
                        const Icon(Icons.settings_outlined, size: 18),
                        const SizedBox(width: 12),
                        Text(c.tr('设置', 'Settings')),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'logout',
                    child: Row(
                      children: [
                        const Icon(Icons.logout_rounded, size: 18),
                        const SizedBox(width: 12),
                        Text(c.tr('退出账号', 'Sign out')),
                      ],
                    ),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: tone.raised,
                        ),
                        child: Text(
                          email.isEmpty ? '' : email[0].toUpperCase(),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          email.split('@').first,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          RoundButton(
            tooltip: c.tr('Skills 与插件', 'Skills & plugins'),
            icon: Icons.grid_view_rounded,
            onPressed: () => narrow
                ? pushPage(context, ExtensionsPage(client: c, kind: 'skills'))
                : showExtensionsDialog(context, c),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, child) => LayoutBuilder(
      builder: (context, constraints) {
        final tone = context.tone;
        final narrow = constraints.maxWidth < 840;
        final roomy = constraints.maxWidth >= 1000;
        final active = c.node.conversations.where(
          (x) => x['kind'] == 'dm'
              ? c.node.bots.any(
                  (b) => b['botId'] == x['botId'] && b['archived'] != true,
                )
              : c.node.groups.any(
                  (g) => g['groupId'] == x['groupId'] && g['archived'] != true,
                ),
        );
        final shown = active.where((value) {
          final entity = value['kind'] == 'group'
              ? c.node.groups.firstWhere(
                  (x) => x['groupId'] == value['groupId'],
                )
              : c.node.bots.firstWhere((x) => x['botId'] == value['botId']);
          return '${entity['name'] ?? entity['displayName']}'
              .toLowerCase()
              .contains(search);
        }).toList();
        final conversations = active.isEmpty
            ? Center(
                child: IconButton(
                  tooltip: c.selectedNodeId == null
                      ? c.tr('添加电脑', 'Add computer')
                      : c.tr('新建 Bot', 'New Bot'),
                  onPressed: () => pushPage(
                    context,
                    c.selectedNodeId == null
                        ? PairingPage(client: c)
                        : BotEditor(client: c),
                  ),
                  icon: const CatAvatar(size: 72),
                ),
              )
            : ListView(
                padding: EdgeInsets.only(bottom: tone.glass ? 84 : 8),
                children: [for (final value in shown) row(value, narrow)],
              );
        final list = Column(
          children: [
            tone.glass ? glassTop() : top(),
            if (searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  autofocus: true,
                  decoration: InputDecoration(hintText: c.tr('搜索', 'Search')),
                  onChanged: (value) =>
                      setState(() => search = value.toLowerCase()),
                ),
              ),
            if (c.error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                child: Row(
                  children: [
                    Expanded(child: ErrorNotice(c.error)),
                    IconButton(
                      tooltip: c.tr('重新连接', 'Reconnect'),
                      onPressed: () => c.bootstrap(),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: tone.glass
                  ? Stack(
                      children: [
                        Positioned.fill(child: conversations),
                        Positioned(left: 0, right: 0, bottom: 0, child: dock()),
                      ],
                    )
                  : conversations,
            ),
            if (!tone.glass) bottom(narrow),
          ],
        );
        final hasChat =
            conversation != null &&
            c.node.conversations.any(
              (x) => x['conversationId'] == conversation,
            );
        final panel = roomy && hasChat ? details : null;
        return PopScope(
          canPop: !Platform.isAndroid,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && Platform.isAndroid) {
              const MethodChannel('app.nekodot/lifecycle')
                  .invokeMethod('background');
            }
          },
          child: Scaffold(
            body: narrow
                ? SafeArea(child: list)
                : Row(
                    children: [
                      SizedBox(
                        width: 280,
                        child: Material(color: tone.sidebar, child: list),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: hasChat
                            ? ChatPage(
                                key: ValueKey(
                                  '${c.selectedNodeId}:$conversation',
                                ),
                                client: c,
                                conversationId: conversation!,
                                embedded: true,
                                reserveControls: panel == null,
                                onDetails: roomy
                                    ? (bot) => setState(() => details = bot)
                                    : null,
                              )
                            : Stack(
                                children: const [
                                  Positioned.fill(child: WindowDrag()),
                                  Center(
                                    child: Opacity(
                                      opacity: .08,
                                      child: CatAvatar(size: 96),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      if (panel != null) ...[
                        const VerticalDivider(width: 1),
                        SizedBox(
                          width: 340,
                          child: BotDetails(
                            key: ValueKey(panel['botId']),
                            client: c,
                            bot: panel,
                            onClose: () => setState(() => details = null),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        );
      },
    ),
  );
}
