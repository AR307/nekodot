import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../platform/desktop.dart';
import '../ui/design.dart';
import 'bot_details.dart';
import 'chat.dart';
import 'bot_editor.dart';
import 'extensions.dart';
import 'files.dart';
import 'settings.dart';
import 'pairing.dart';
import 'local_setup.dart';
import '../local/runtime.dart';
import 'node_update.dart';
import 'flowchart.dart';
import 'search_palette.dart';
import 'time_labels.dart';

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
  FlowMessageFocus? flowFocus;
  String search = '';
  String? hovered;
  Json? creatingBot;
  final searchField = TextEditingController();
  final folded = <String>{};

  /// The sidebar's width while it is being dragged; saved when let go.
  double? dragging;
  NekodotClient get c => widget.client;
  @override
  void initState() {
    super.initState();
    conversation = c.workspace['conversation:${c.selectedNodeId}'] as String?;
    final savedDetails = c.workspace['details:${c.selectedNodeId}'];
    if (savedDetails is Map) details = object(savedDetails);
    destinations = c.destinations.stream.listen(openDestination);
    HardwareKeyboard.instance.addHandler(searchKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (c.pendingDestination != null) {
        openDestination(c.pendingDestination!);
      } else if (conversation != null &&
          MediaQuery.sizeOf(context).width < 840 &&
          c.node.conversations.any(
            (v) => v['conversationId'] == conversation,
          )) {
        unawaited(
          pushPage(context, ChatPage(client: c, conversationId: conversation!)),
        );
      }
    });
  }

  Future<void> openDestination(Json target) async {
    c.pendingDestination = null;
    final nodeId = target['nodeId'] as String;
    if (!objects(c.account.me?['nodes']).any((n) => n['nodeId'] == nodeId)) {
      return;
    }
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
    HardwareKeyboard.instance.removeHandler(searchKey);
    searchField.dispose();
    destinations?.cancel();
    super.dispose();
  }

  /// Ctrl+K (Cmd+K) opens the search panel wherever focus is on the desktop.
  bool searchKey(KeyEvent event) {
    final keys = HardwareKeyboard.instance;
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.keyK ||
        !(keys.isControlPressed || keys.isMetaPressed) ||
        !mounted ||
        context.tone.glass ||
        ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    unawaited(openSearch());
    return true;
  }

  Future<void> openSearch() {
    final narrow = MediaQuery.sizeOf(context).width < 840;
    final active = c.node.conversations.where(
      (x) => x['kind'] == 'dm'
          ? c.node.bots.any(
              (b) => b['botId'] == x['botId'] && b['archived'] != true,
            )
          : c.node.groups.any(
              (g) => g['groupId'] == x['groupId'] && g['archived'] != true,
            ),
    );
    final ordered = [
      for (final x in active)
        if (x['kind'] == 'group') x,
      for (final x in active)
        if (x['kind'] == 'dm') x,
    ];
    final actions = c.tr('操作', 'Actions');
    Widget icon(IconData value) =>
        Icon(value, size: 20, color: context.tone.ink2);
    return showSearchPalette(context, c, [
      for (final x in ordered)
        conversationEntry(
          c,
          x,
          preview: preview(x, x['kind'] == 'group'),
          open: () => open(x, narrow),
        ),
      SearchEntry(
        section: actions,
        title: c.tr('新建 Bot', 'New Bot'),
        leading: icon(Icons.smart_toy_outlined),
        open: () => create('bot'),
      ),
      SearchEntry(
        section: actions,
        title: c.tr('新建群组', 'New group'),
        leading: icon(Icons.groups_outlined),
        open: () => create('group'),
      ),
      SearchEntry(
        section: actions,
        title: c.tr('添加插件', 'Add plugins'),
        leading: icon(Icons.extension_outlined),
        open: () => create('plugins'),
      ),
      SearchEntry(
        section: actions,
        title: c.tr('设置', 'Settings'),
        leading: icon(Icons.settings_outlined),
        open: () => openPage(context, SettingsPage(client: c)),
      ),
    ]);
  }

  Future<void> open(Json value, bool narrow) async {
    final id = value['conversationId'] as String;
    c.workspace['conversation:${c.selectedNodeId}'] = id;
    c.workspace.remove('details:${c.selectedNodeId}');
    c.saveContent();
    if (narrow) {
      await pushPage(context, ChatPage(client: c, conversationId: id));
    } else {
      setState(() {
        conversation = id;
        details = null;
        flowFocus = null;
      });
    }
  }

  /// Desktops can run Bots here or connect a server; phones only connect.
  Widget _addComputer() => localRuntime == null
      ? PairingPage(client: c)
      : RunLocationPage(client: c);

  Widget nodePicker() {
    final nodes = objects(c.account.me?['nodes']);
    final current = nodes
        .where((n) => n['nodeId'] == c.selectedNodeId)
        .firstOrNull;
    return PopupMenuButton<String>(
      tooltip: c.tr('电脑', 'Computer'),
      position: PopupMenuPosition.under,
      constraints: menuConstraints,
      onSelected: (id) {
        if (id == '') {
          openPage(context, _addComputer());
        } else {
          setState(() {
            conversation = null;
            details = null;
            flowFocus = null;
          });
          c.selectNode(id);
        }
      },
      itemBuilder: (context) => [
        for (final node in nodes)
          menuItem(
            context,
            value: node['nodeId'] as String,
            leading: StatusDot(on: node['online'] == true, size: 7),
            label: '${node['name']}',
            trailing: node['nodeId'] == c.selectedNodeId
                ? const Icon(Icons.check)
                : null,
          ),
        if (nodes.isNotEmpty) menuDivider,
        menuItem(
          context,
          value: '',
          icon: Icons.add_to_queue_outlined,
          label: c.tr('添加电脑', 'Add computer'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (current != null) ...[
              c.online || c.connection.ready
                  ? StatusDot(on: c.online)
                  : ShiningText(
                      text: c.tr('连接中…', 'Connecting…'),
                      style: const TextStyle(fontSize: 12),
                    ),
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
                tooltip: c.tr('搜索 (Ctrl+K)', 'Search (Ctrl+K)'),
                icon: Icons.search,
                onPressed: openSearch,
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
    constraints: menuConstraints,
    icon: const Icon(Icons.add),
    onSelected: create,
    itemBuilder: createItems,
  );

  /// New Bot, new group, and the skills and plugins a Bot can be given.
  List<PopupMenuEntry<String>> createItems(BuildContext context) => [
    menuItem(
      context,
      value: 'bot',
      icon: Icons.smart_toy_outlined,
      label: c.tr('新建 Bot', 'New Bot'),
    ),
    menuItem(
      context,
      value: 'group',
      icon: Icons.groups_outlined,
      label: c.tr('新建群组', 'New group'),
    ),
    menuDivider,
    menuItem(
      context,
      value: 'plugins',
      icon: Icons.extension_outlined,
      label: c.tr('添加插件', 'Add plugins'),
    ),
  ];

  Future<void> create(String value) async {
    if (value != 'plugins') {
      final nodeId = c.selectedNodeId;
      final created = await openPage<Json>(
        context,
        BotEditor(
          client: c,
          group: value == 'group',
          onCreating: (bot) {
            if (mounted) setState(() => creatingBot = bot);
          },
        ),
        form: true,
      );
      if (created != null && mounted && c.selectedNodeId == nodeId) {
        await open(created, MediaQuery.sizeOf(context).width < 840);
      }
    } else if (MediaQuery.sizeOf(context).width < 840) {
      pushPage(context, ExtensionsPage(client: c, kind: 'skills'));
    } else {
      showExtensionsDialog(context, c);
    }
  }

  /// Your initial in a round mark: you, and the way to your settings.
  Widget accountMark(double size) {
    final tone = context.tone;
    final name = '${c.account.me?['user']['email'] ?? ''}'.split('@').first;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: tone.ink),
      child: Text(
        name.isEmpty ? '' : name.characters.first.toUpperCase(),
        style: TextStyle(
          color: tone.base,
          fontSize: size * .4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// A round control floating on the ground with a soft shadow.
  Widget floatingRound({required Widget child}) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.tone.surface,
      shape: BoxShape.circle,
      boxShadow: context.tone.rest,
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );

  /// Phone header: you on the left, the computer in the middle, new on the
  /// right. Search lives at the bottom, under the thumb.
  Widget glassTop() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
    child: Row(
      children: [
        IconButton(
          tooltip: c.tr('设置', 'Settings'),
          padding: const EdgeInsets.all(4),
          onPressed: () => pushPage(context, SettingsPage(client: c)),
          icon: accountMark(34),
        ),
        Expanded(child: Center(child: nodePicker())),
        floatingRound(
          child: PopupMenuButton<String>(
            tooltip: c.tr('新建', 'Create'),
            position: PopupMenuPosition.under,
            constraints: menuConstraints,
            icon: const Icon(Icons.add),
            onSelected: create,
            itemBuilder: createItems,
          ),
        ),
      ],
    ),
  );

  /// Phone bottom: plugins, and a search field the thumb reaches.
  Widget dock() {
    final tone = context.tone;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        child: Row(
          children: [
            floatingRound(
              child: IconButton(
                tooltip: c.tr('Skills 与插件', 'Skills & plugins'),
                onPressed: () => pushPage(
                  context,
                  ExtensionsPage(client: c, kind: 'skills'),
                ),
                icon: const Icon(Icons.grid_view_rounded),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: tone.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: tone.lift,
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Icon(Icons.search, size: 20, color: tone.ink2),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('home-search'),
                        controller: searchField,
                        style: text.bodyLarge,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: c.tr('搜索', 'Search'),
                          isDense: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (value) =>
                            setState(() => search = value.toLowerCase()),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      child: search.isEmpty
                          ? const SizedBox(width: 12)
                          : IconButton(
                              tooltip: c.tr('清除', 'Clear'),
                              onPressed: () {
                                searchField.clear();
                                FocusManager.instance.primaryFocus?.unfocus();
                                setState(() => search = '');
                              },
                              icon: const Icon(Icons.close, size: 20),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// When anything was last said there.
  DateTime? lastActivity(String id) {
    final loaded = c.node.messages[id]?.lastOrNull;
    final reported = c.node.latest[id];
    final last =
        loaded == null || (reported != null && reported.seq > loaded.seq)
        ? reported
        : loaded;
    return last == null ? null : DateTime.parse(last.createdAt).toLocal();
  }

  /// The latest thing said there, as one line; a group names who said it.
  String? preview(Json value, bool isGroup) {
    final id = value['conversationId'];
    final loaded = (c.node.messages[id] ?? [])
        .where(
          (x) =>
              (x.kind == 'text' || x.kind == 'commentary') &&
              '${x.content['text'] ?? ''}'.trim().isNotEmpty,
        )
        .lastOrNull;
    // Loaded messages are newer than the node's first report once they pass it.
    final reported = c.node.latest[id];
    final last =
        loaded == null || (reported != null && reported.seq > loaded.seq)
        ? reported
        : loaded;
    if (last == null) return null;
    final words = '${last.content['text']}';
    final files = last.content['files'];
    final text =
        (files is List && files.isNotEmpty ? withoutDeliveries(words) : words)
            .replaceAll(RegExp(r'[*_`#>]+'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    if (!isGroup) return text;
    final author = last.author;
    final bot = c.node.bots.where((b) => b['botId'] == author.id).firstOrNull;
    final speaker = author.type == 'bot'
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
    final state = c.node.activities[id]?.state;
    final working = state != null && state != 'idle';
    final selected = !narrow && conversation == id;
    // The selected row lifts off the list; hovering a row only raises it.
    final raised = selected || (!glass && hovered == id);
    // A phone shows when it last spoke; a desktop, what the Bot is for.
    final note = glass || isGroup
        ? ''
        : '${entity['role'] ?? ''}'.split('\n').first.trim();
    final last = preview(value, isGroup);
    final lastAt = glass ? lastActivity(id) : null;
    // Something in there is waiting for your answer.
    final waiting = c.node.flows[id]?.state == 'waiting';
    final size = glass ? 44.0 : 40.0;
    final corners = BorderRadius.circular(12);
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = id),
      onExit: (_) => setState(() => hovered = null),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Container(
          decoration: ShapeDecoration(
            color: raised ? tone.surface : tone.surface.withValues(alpha: 0),
            shadows: raised ? (selected ? tone.lift : tone.rest) : const [],
            shape: RoundedSuperellipseBorder(borderRadius: corners),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: ValueKey('conversation-$id'),
              customBorder: RoundedSuperellipseBorder(borderRadius: corners),
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
                                flex: 2,
                                fit: FlexFit.tight,
                                child: Text(
                                  '${entity[isGroup ? 'name' : 'displayName']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.titleMedium?.copyWith(
                                    fontSize: glass ? 16 : 15,
                                  ),
                                ),
                              ),
                              if (lastAt != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  rowTime(c, lastAt),
                                  style: text.bodySmall?.copyWith(
                                    fontSize: 12,
                                    color: tone.ink3,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
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
                          if (last != null || waiting) ...[
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    last ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodySmall?.copyWith(
                                      fontSize: glass ? 14 : 13.5,
                                      color: tone.ink2,
                                    ),
                                  ),
                                ),
                                if (waiting)
                                  Semantics(
                                    label: c.tr('等你确认', 'Needs your OK'),
                                    child: Container(
                                      key: ValueKey('waiting-$id'),
                                      width: 8,
                                      height: 8,
                                      margin: const EdgeInsets.only(left: 8),
                                      decoration: BoxDecoration(
                                        color: tone.ink,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                              ],
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
        customBorder: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(10),
        ),
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
      SizeMotion(
        duration: const Duration(milliseconds: 200),
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
    final email = '${c.account.me?['user']['email'] ?? ''}';
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
                constraints: menuConstraints,
                onSelected: (value) {
                  if (value == 'settings') {
                    openPage(context, SettingsPage(client: c));
                  } else {
                    signOut();
                  }
                },
                itemBuilder: (context) => [
                  for (final (value, icon, label) in [
                    (
                      'settings',
                      Icons.settings_outlined,
                      c.tr('设置', 'Settings'),
                    ),
                    ('logout', Icons.logout, c.tr('退出账号', 'Sign out')),
                  ]) ...[
                    if (value == 'logout') menuDivider,
                    menuItem(context, value: value, icon: icon, label: label),
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
              onPressed: () => openPage(context, SettingsPage(client: c)),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([c, c.node]),
    builder: (context, child) => LayoutBuilder(
      builder: (context, constraints) {
        final tone = context.tone;
        final narrow = constraints.maxWidth < 840;
        final roomy = constraints.maxWidth >= 1000;
        final updateCommand =
            objects(c.account.me?['nodes'])
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
        final conversations = ListenableBuilder(
          listenable: c.node.summaries,
          builder: (context, _) => active.isEmpty && creatingBot == null
              ? Center(
                  child: IconButton(
                    tooltip: c.selectedNodeId == null
                        ? c.tr('添加电脑', 'Add computer')
                        : c.tr('新建 Bot', 'New Bot'),
                    onPressed: () => c.selectedNodeId == null
                        ? openPage(context, _addComputer(), form: true)
                        : create('bot'),
                    icon: const CatAvatar(size: 56),
                  ),
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(8, 0, 8, tone.glass ? 92 : 8),
                  children: [
                    if (creatingBot?['nodeId'] == c.selectedNodeId &&
                        creatingBot != null)
                      ListTile(
                        key: const ValueKey('bot-creating'),
                        leading: CatAvatar.of(creatingBot!),
                        title: Text(
                          '${creatingBot!['displayName']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: ShiningText(text: c.tr('创建中…', 'Creating…')),
                      ),
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
                ),
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
            active.any((x) => x['conversationId'] == conversation);
        final panel = roomy && hasChat ? details : null;
        final widest = (constraints.maxWidth - 420).clamp(240.0, 560.0);
        final sidebar =
            (dragging ?? c.prefs.sidebarWidth ?? constraints.maxWidth * .34)
                .clamp(240.0, widest);
        final flowShown = hasChat && flowFocus != null;
        final inlineFlow = flowShown && constraints.maxWidth - sidebar >= 760;
        Widget flowPanel() => FlowchartPanel(
          key: ValueKey('flow:${c.selectedNodeId}:$conversation'),
          client: c,
          conversationId: conversation!,
          reserveControls: true,
          onClose: () => setState(() => flowFocus = null),
          onMessage: (id) async {
            final focus = flowFocus!;
            setState(() => flowFocus = null);
            await focus(id);
          },
        );
        return PopScope(
          canPop: !Platform.isAndroid,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && Platform.isAndroid) {
              if (flowShown) {
                setState(() => flowFocus = null);
              } else if (panel != null) {
                setState(() => details = null);
              } else {
                const MethodChannel('app.nekodot/lifecycle')
                    .invokeMethod('background');
              }
            }
          },
          child: Scaffold(
            body: narrow
                ? SafeArea(child: list)
                : Stack(
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: sidebar,
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
                                    reserveControls:
                                        panel == null && !flowShown,
                                    onDetails: roomy
                                        ? (bot) => setState(() {
                                            details = bot;
                                            c.workspace['details:${c.selectedNodeId}'] =
                                                bot;
                                            c.saveContent();
                                            flowFocus = null;
                                          })
                                        : null,
                                    flowOpen: flowShown,
                                    onFlow: (focus) => setState(() {
                                      details = null;
                                      c.workspace.remove('details:${c.selectedNodeId}');
                                      c.saveContent();
                                      flowFocus = flowFocus == null
                                          ? focus
                                          : null;
                                    }),
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
                            child: inlineFlow
                                ? flowPanel()
                                : panel == null
                                ? null
                                : BotDetails(
                                    key: ValueKey(panel['botId']),
                                    client: c,
                                    bot: panel,
                                    onClose: () {
                                      setState(() => details = null);
                                      c.workspace.remove('details:${c.selectedNodeId}');
                                      c.saveContent();
                                    },
                                  ),
                          ),
                        ],
                      ),
                      if (flowShown && !inlineFlow)
                        Positioned.fill(
                          child: GestureDetector(
                            onTap: () => setState(() => flowFocus = null),
                            child: const ColoredBox(color: Colors.black26),
                          ),
                        ),
                      Positioned(
                        top: 0,
                        bottom: 0,
                        right: 0,
                        child: SidePanel(
                          child: flowShown && !inlineFlow ? flowPanel() : null,
                        ),
                      ),
                      Positioned(
                        left: sidebar - 4,
                        top: 0,
                        bottom: 0,
                        width: 9,
                        child: SplitHandle(
                          onDrag: (dx) => setState(
                            () =>
                                dragging = (sidebar + dx).clamp(240.0, widest),
                          ),
                          onEnd: () {
                            final width = dragging;
                            setState(() => dragging = null);
                            if (width != null) c.prefs.setSidebarWidth(width);
                          },
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

/// The line between the sidebar and the chat: drag it to resize.
class SplitHandle extends StatefulWidget {
  final ValueChanged<double> onDrag;
  final VoidCallback onEnd;
  const SplitHandle({super.key, required this.onDrag, required this.onEnd});
  @override
  State<SplitHandle> createState() => _SplitHandleState();
}

class _SplitHandleState extends State<SplitHandle> {
  bool hovered = false, held = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    onEnter: (_) => setState(() => hovered = true),
    onExit: (_) => setState(() => hovered = false),
    child: GestureDetector(
      key: const ValueKey('sidebar-split'),
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => setState(() => held = true),
      onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
      onHorizontalDragEnd: (_) {
        setState(() => held = false);
        widget.onEnd();
      },
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: held || hovered ? 2 : 0,
          color: context.tone.ink3,
        ),
      ),
    ),
  );
}
