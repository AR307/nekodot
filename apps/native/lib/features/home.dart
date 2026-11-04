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
import 'local_setup.dart';
import '../local/runtime.dart';
import 'node_update.dart';

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
  String? hovered;
  bool searching = false;
  final folded = <String>{};
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

  /// Desktops can run Bots here or connect a server; phones only connect.
  Widget _addComputer() => localRuntime == null
      ? PairingPage(client: c)
      : RunLocationPage(client: c);

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
          pushPage(context, _addComputer());
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
                  const Icon(Icons.check, size: 18),
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
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: context.tone.glass ? 16 : 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more, size: 16, color: context.tone.ink3),
          ],
        ),
      ),
    );
  }

  Widget top() => Stack(
    children: [
      const Positioned.fill(child: WindowDrag()),
      SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: nodePicker(),
                ),
              ),
              IconAction(
                tooltip: c.tr('搜索', 'Search'),
                icon: searching ? Icons.close : Icons.search,
                onPressed: () => setState(() {
                  searching = !searching;
                  search = '';
                }),
              ),
              const SizedBox(width: 4),
              createMenu(),
            ],
          ),
        ),
      ),
    ],
  );

  Widget createMenu() => PopupMenuButton<String>(
    tooltip: c.tr('新建', 'Create'),
    position: PopupMenuPosition.under,
    icon: const Icon(Icons.add),
    onSelected: (value) =>
        pushPage(context, BotEditor(client: c, group: value == 'group')),
    itemBuilder: (_) => [
      PopupMenuItem(value: 'bot', child: Text(c.tr('新建 Bot', 'New Bot'))),
      PopupMenuItem(value: 'group', child: Text(c.tr('新建群组', 'New group'))),
    ],
  );

  /// Phone header: the mark, the computer, search.
  Widget glassTop() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
    child: Row(
      children: [
        const CatAvatar(size: 28),
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
          icon: const Icon(Icons.search),
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Skills',
                  onPressed: () => pushPage(
                    context,
                    ExtensionsPage(client: c, kind: 'skills'),
                  ),
                  icon: const Icon(Icons.auto_awesome_outlined),
                ),
                IconButton(
                  tooltip: c.tr('插件', 'Plugins'),
                  onPressed: () => pushPage(
                    context,
                    ExtensionsPage(client: c, kind: 'plugins'),
                  ),
                  icon: const Icon(Icons.extension_outlined),
                ),
                IconButton(
                  tooltip: c.tr('设置', 'Settings'),
                  onPressed: () => pushPage(context, SettingsPage(client: c)),
                  icon: const Icon(Icons.tune),
                ),
              ],
            ),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            tooltip: c.tr('新建', 'Create'),
            position: PopupMenuPosition.over,
            icon: const Icon(Icons.add),
            iconColor: tone.base,
            style: IconButton.styleFrom(
              backgroundColor: tone.ink,
              fixedSize: const Size.square(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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

  /// The latest thing said there, as one line; a group names who said it.
  String? preview(Json value, bool isGroup) {
    final last = (c.node.messages[value['conversationId']] ?? [])
        .where(
          (x) =>
              (x['kind'] == 'text' || x['kind'] == 'commentary') &&
              '${x['content']?['text'] ?? ''}'.trim().isNotEmpty,
        )
        .lastOrNull;
    if (last == null) return null;
    final text = '${last['content']['text']}'
        .replaceAll(RegExp(r'[*_`#>]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (!isGroup) return text;
    final author = object(last['author']);
    final bot = c.node.bots
        .where((b) => b['botId'] == author['id'])
        .firstOrNull;
    final speaker = author['type'] == 'bot'
        ? (bot?['displayName'])
        : c.tr('你', 'You');
    return speaker == null ? text : c.tr('$speaker：$text', '$speaker: $text');
  }

  Widget row(Json value, bool narrow) {
    final tone = context.tone;
    final glass = tone.glass;
    final text = Theme.of(context).textTheme;
    final isGroup = value['kind'] == 'group';
    final entity = isGroup
        ? c.node.groups.firstWhere((x) => x['groupId'] == value['groupId'])
        : c.node.bots.firstWhere((x) => x['botId'] == value['botId']);
    final id = value['conversationId'] as String;
    final state = c.node.activities[id]?['state'];
    final working = state != null && state != 'idle';
    final selected = !narrow && conversation == id;
    // The selected row lifts off the list; hovering a row only raises it.
    final raised = selected || (!glass && hovered == id);
    final note = isGroup
        ? ''
        : '${entity['role'] ?? ''}'.split('\n').first.trim();
    final last = preview(value, isGroup);
    final size = glass ? 44.0 : 40.0;
    final still = MediaQuery.disableAnimationsOf(context);
    final corners = BorderRadius.circular(12);
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = id),
      onExit: (_) => setState(() => hovered = null),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: AnimatedContainer(
          duration: still ? Duration.zero : const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: raised ? tone.surface : tone.surface.withValues(alpha: 0),
            borderRadius: corners,
            boxShadow: raised ? (selected ? tone.lift : tone.rest) : const [],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: ValueKey('conversation-$id'),
              borderRadius: corners,
              hoverColor: Colors.transparent,
              highlightColor: tone.hover,
              onTap: () => open(value, narrow),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    if (isGroup)
                      GroupAvatar(
                        size: size,
                        working: working,
                        avatars: [
                          for (final bot in c.node.bots)
                            if ((entity['botIds'] as List).contains(
                              bot['botId'],
                            ))
                              object(bot['avatar']),
                        ],
                      )
                    else
                      CatAvatar.of(
                        entity,
                        size: size,
                        working: working,
                        twitch: hovered == id,
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                flex: 0,
                                child: Text(
                                  '${entity[isGroup ? 'name' : 'displayName']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.titleMedium?.copyWith(
                                    fontSize: glass ? 16 : 15,
                                  ),
                                ),
                              ),
                              if (note.isNotEmpty) ...[
                                Container(
                                  width: 1,
                                  height: 12,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  color: tone.line,
                                ),
                                Expanded(
                                  child: Text(
                                    note,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodySmall?.copyWith(
                                      fontSize: 13,
                                      color: tone.ink3,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (last != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              last,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall?.copyWith(
                                fontSize: glass ? 14 : 13.5,
                                color: tone.ink2,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A titled, foldable run of rows. Searching opens every section.
  List<Widget> section(
    String key,
    String label,
    List<Json> items,
    bool narrow,
  ) {
    if (items.isEmpty) return const [];
    final tone = context.tone;
    final text = Theme.of(context).textTheme;
    final still = MediaQuery.disableAnimationsOf(context);
    final open = !folded.contains(key) || search.isNotEmpty;
    return [
      InkWell(
        key: ValueKey('section-$key'),
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() {
          if (!folded.remove(key)) folded.add(key);
        }),
        child: SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
            child: Row(
              children: [
                Text(
                  label,
                  style: text.titleMedium?.copyWith(
                    fontSize: tone.glass ? 15 : 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${items.length}',
                  style: text.bodySmall?.copyWith(
                    fontSize: 13,
                    color: tone.ink3,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: open ? 0 : .5,
                  duration: still
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  child: Icon(Icons.expand_less, size: 16, color: tone.ink3),
                ),
              ],
            ),
          ),
        ),
      ),
      AnimatedSize(
        duration: still ? Duration.zero : const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: open
            ? Column(children: [for (final value in items) row(value, narrow)])
            : const SizedBox(width: double.infinity),
      ),
    ];
  }

  Future<void> signOut() async {
    try {
      await localRuntime?.stop();
      await c.logout();
    } catch (e) {
      if (mounted) {
        showNotice(context, '$e');
      }
    }
  }

  Widget bottom(bool narrow) {
    final tone = context.tone;
    final email = '${c.me?['user']['email'] ?? ''}';
    final name = email.split('@').first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            Expanded(
              child: PopupMenuButton<String>(
                tooltip: c.tr('账户', 'Account'),
                position: PopupMenuPosition.over,
                onSelected: (value) {
                  if (value == 'extensions') {
                    narrow
                        ? pushPage(
                            context,
                            ExtensionsPage(client: c, kind: 'skills'),
                          )
                        : showExtensionsDialog(context, c);
                  } else if (value == 'settings') {
                    pushPage(context, SettingsPage(client: c));
                  } else {
                    signOut();
                  }
                },
                itemBuilder: (_) => [
                  for (final (value, icon, label) in [
                    (
                      'extensions',
                      Icons.extension_outlined,
                      c.tr('Skills 与插件', 'Skills & plugins'),
                    ),
                    (
                      'settings',
                      Icons.settings_outlined,
                      c.tr('设置', 'Settings'),
                    ),
                    ('logout', Icons.logout, c.tr('退出账号', 'Sign out')),
                  ]) ...[
                    if (value == 'logout') const PopupMenuDivider(),
                    PopupMenuItem(
                      value: value,
                      child: Row(
                        children: [
                          Icon(icon, size: 18),
                          const SizedBox(width: 12),
                          Text(label),
                        ],
                      ),
                    ),
                  ],
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: tone.ink,
                        ),
                        child: Text(
                          name.isEmpty
                              ? ''
                              : name.characters.first.toUpperCase(),
                          style: TextStyle(
                            color: tone.base,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconAction(
              tooltip: c.tr('设置', 'Settings'),
              icon: Icons.settings_outlined,
              onPressed: () => pushPage(context, SettingsPage(client: c)),
            ),
            const SizedBox(width: 8),
          ],
        ),
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
        final updateCommand =
            objects(c.me?['nodes'])
                    .where((n) => n['nodeId'] == c.selectedNodeId)
                    .firstOrNull?['updateCommand']
                as String?;
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
                        ? _addComputer()
                        : BotEditor(client: c),
                  ),
                  icon: const CatAvatar(size: 56),
                ),
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(8, 0, 8, tone.glass ? 92 : 8),
                children: [
                  ...section('groups', c.tr('群聊', 'Groups'), [
                    for (final x in shown)
                      if (x['kind'] == 'group') x,
                  ], narrow),
                  const SizedBox(height: 16),
                  ...section('bots', 'Bot', [
                    for (final x in shown)
                      if (x['kind'] == 'dm') x,
                  ], narrow),
                ],
              );
        final list = Column(
          children: [
            tone.glass ? glassTop() : top(),
            if (c.online && updateCommand != null)
              NodeUpdateNotice(
                key: ValueKey('${c.selectedNodeId}:$updateCommand'),
                client: c,
                command: updateCommand,
              ),
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
                      icon: const Icon(Icons.refresh),
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
                        width: (constraints.maxWidth * .34).clamp(272, 500),
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
                                      child: CatAvatar(size: 72),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      SidePanel(
                        child: panel == null
                            ? null
                            : BotDetails(
                                key: ValueKey(panel['botId']),
                                client: c,
                                bot: panel,
                                onClose: () => setState(() => details = null),
                              ),
                      ),
                    ],
                  ),
          ),
        );
      },
    ),
  );
}
