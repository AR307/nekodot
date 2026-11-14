import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../platform/desktop.dart';
import '../ui/design.dart';
import 'account_menu.dart';
import 'bot_details.dart';
import 'chat.dart';
import 'bot_editor.dart';
import 'plugin_center.dart';
import 'files.dart';
import 'settings.dart';
import 'pairing.dart';
import 'local_setup.dart';
import '../local/runtime.dart';
import 'node_update.dart';
import 'flowchart.dart';
import 'search_palette.dart';
import 'time_labels.dart';
import '../data/spaces.dart';
import 'space_gallery.dart';
import 'spaces.dart';
import 'statistics.dart';
import 'home_rail.dart';

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

  /// The part of settings shown beside the rail, when settings are open there.
  String? settingsPart;

  /// Files open as tabs beside the conversation, and the one in front.
  final previewFiles = <Json>[];
  int previewAt = 0;
  Json? get previewFile =>
      previewFiles.isEmpty ? null : previewFiles[previewAt];
  set previewFile(Json? file) {
    if (file == null) {
      previewFiles.clear();
      previewAt = 0;
      return;
    }
    final at = previewFiles.indexWhere((f) => f['fileId'] == file['fileId']);
    if (at < 0) previewFiles.add(file);
    previewAt = at < 0 ? previewFiles.length - 1 : at;
  }

  bool expandedFile = false;
  FlowMessageFocus? flowFocus;
  String search = '';
  String? hovered;
  Json? creatingBot;
  final searchField = TextEditingController();
  bool searching = false;

  /// The section the rail or the bottom bar shows.
  String get category =>
      c.workspace['category:${c.selectedNodeId}'] as String? ?? 'recent';

  /// The conversation a section was left on: Dot and groups remember their
  /// own, everything else the last one opened.
  String? savedConversation(String section, String? node) =>
      c.workspace[section == 'dot' || section == 'group'
              ? 'conversation:$section:$node'
              : 'conversation:$node']
          as String?;
  String? selectedSpace;

  /// Where the tile that opened the space is, for the page to grow out of.
  Rect? spaceFrom;

  /// The sidebar's width while it is being dragged; saved when let go.
  double? dragging;
  NekodotClient get c => widget.client;
  @override
  void initState() {
    super.initState();
    conversation = savedConversation(category, c.selectedNodeId);
    selectedSpace = c.workspace['space:${c.selectedNodeId}'] as String?;
    final savedDetails = c.workspace['details:${c.selectedNodeId}'];
    if (savedDetails is Map) details = object(savedDetails);
    destinations = c.destinations.stream.listen(openDestination);
    HardwareKeyboard.instance.addHandler(searchKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (c.pendingDestination != null) {
        openDestination(c.pendingDestination!);
      } else if (category == 'space' &&
          selectedSpace != null &&
          c.node.spaces[selectedSpace]?.archived == false &&
          MediaQuery.sizeOf(context).width < 840) {
        unawaited(
          pushPage(
            context,
            SpacePage(
              client: c,
              nodeId: c.selectedNodeId!,
              spaceId: selectedSpace!,
            ),
          ),
        );
      } else if (category != 'space' &&
          conversation != null &&
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
        leading: icon(Symbols.smart_toy),
        open: () => create('bot'),
      ),
      SearchEntry(
        section: actions,
        title: c.tr('新建群组', 'New group'),
        leading: icon(Symbols.groups),
        open: () => create('group'),
      ),
      SearchEntry(
        section: actions,
        title: c.tr('插件中心', 'Plugin center'),
        leading: icon(Symbols.extension),
        open: () => create('plugins'),
      ),
      SearchEntry(
        section: actions,
        title: c.tr('设置', 'Settings'),
        leading: icon(Symbols.settings),
        open: openSettings,
      ),
    ]);
  }

  Future<void> open(Json value, bool narrow) async {
    final id = value['conversationId'] as String;
    final kind = value['kind'] == 'group' ? 'group' : 'dot';
    // Recent holds everything, so opening from it stays there; from a section
    // of another kind, Recent is where the conversation is found.
    c.workspace['category:${c.selectedNodeId}'] =
        category == 'recent' || category == kind ? category : 'recent';
    c.workspace['conversation:$kind:${c.selectedNodeId}'] = id;
    c.workspace['conversation:${c.selectedNodeId}'] = id;
    c.workspace.remove('details:${c.selectedNodeId}');
    c.saveContent();
    setState(() {
      conversation = id;
    });
    if (narrow) {
      await pushPage(context, ChatPage(client: c, conversationId: id));
    } else {
      setState(() {
        conversation = id;
        details = null;
        flowFocus = null;
        previewFile = null;
        settingsPart = null;
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
    return ActionMenu<String>(
      tooltip: c.tr('电脑', 'Computer'),
      onSelected: (id) {
        if (id == '') {
          openPage(context, _addComputer());
        } else {
          setState(() {
            conversation = savedConversation(
              c.workspace['category:$id'] as String? ?? 'recent',
              id,
            );
            selectedSpace = c.workspace['space:$id'] as String?;
            details = null;
            flowFocus = null;
            previewFile = null;
          });
          c.selectNode(id);
        }
      },
      items: [
        for (final node in nodes)
          MenuAction(
            value: node['nodeId'] as String,
            leading: StatusDot(on: node['online'] == true, size: 7),
            label: '${node['name']}',
            selected: node['nodeId'] == c.selectedNodeId,
          ),
        if (nodes.isNotEmpty) null,
        MenuAction(
          value: '',
          icon: Symbols.add_to_queue,
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
            Icon(Symbols.expand_more, size: 16, color: context.tone.ink3),
          ],
        ),
      ),
    );
  }

  Widget top() => Stack(
    children: [
      const Positioned.fill(child: WindowDrag()),
      SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
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
                icon: Symbols.search,
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

  Widget createMenu() => category == 'space'
      ? IconButton(
          tooltip: c.tr('新建空间', 'New space'),
          icon: const Icon(Symbols.add),
          onPressed: () => create('space'),
        )
      : ActionMenu<String>(
          tooltip: c.tr('新建', 'Create'),
          alignEnd: true,
          icon: const Icon(Symbols.add),
          onSelected: create,
          items: createItems(),
        );

  /// New Bot, new group, and the skills and plugins a Bot can be given.
  List<MenuAction<String>?> createItems() => [
    MenuAction(
      value: 'space',
      icon: Symbols.web_asset,
      label: c.tr('新建空间', 'New space'),
    ),
    MenuAction(
      value: 'bot',
      icon: Symbols.smart_toy,
      label: c.tr('新建 Bot', 'New Bot'),
    ),
    MenuAction(
      value: 'group',
      icon: Symbols.groups,
      label: c.tr('新建群组', 'New group'),
    ),
    null,
    MenuAction(
      value: 'plugins',
      icon: Symbols.extension,
      label: c.tr('插件中心', 'Plugin center'),
    ),
  ];

  Future<void> create(String value) async {
    if (value == 'space') {
      final created = sheetsOpen(context)
          ? await showDialog<Json>(
              context: context,
              barrierDismissible: false,
              builder: (_) => CreateSpacePage(client: c, compact: true),
            )
          : await openPage<Json>(
              context,
              CreateSpacePage(client: c),
              form: true,
            );
      if (created != null && mounted) {
        await open(created, MediaQuery.sizeOf(context).width < 840);
      }
      return;
    }
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
      pushPage(context, PluginCenterPage(client: c, kind: 'skills'));
    } else {
      showPluginCenter(context, c);
    }
  }

  /// Your initial in a round mark: you, and the way to your settings. On the
  /// rail it is white on black whatever the theme.
  Widget accountMark(double size, {bool onRail = false}) =>
      AccountMark(client: c, size: size, onRail: onRail);

  /// Settings take the window beside the rail when there is room for their
  /// list, and open as a page otherwise.
  void openSettings() {
    if (!context.tone.glass && MediaQuery.sizeOf(context).width >= 840) {
      setState(() => settingsPart = settingsParts(c).first.$1);
    } else {
      openPage(context, SettingsPage(client: c));
    }
  }

  /// You, and what belongs to you rather than to a conversation: a menu on a
  /// desktop, a sheet on a phone.
  Widget account(double size, {bool onRail = false}) {
    Widget quick(VoidCallback close) => AccountQuick(
      client: c,
      close: close,
      onSettings: openSettings,
      onStatistics: () => openPage(context, StatisticsPage(client: c)),
      onSignOut: signOut,
    );
    final mark = Padding(
      padding: const EdgeInsets.all(8),
      child: accountMark(size, onRail: onRail),
    );
    final label = c.tr('账户', 'Account');
    if (context.tone.glass) {
      return Tooltip(
        message: label,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => openBottomSheet<void>(
            context,
            Builder(
              builder: (sheet) => SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: quick(() => Navigator.pop(sheet)),
              ),
            ),
            height: .56,
          ),
          child: mark,
        ),
      );
    }
    return MenuPopover(
      width: 300,
      menuBuilder: (context, close) => quick(close),
      builder: (context, toggle, focus) => Tooltip(
        message: label,
        child: InkWell(
          focusNode: focus,
          onTap: toggle,
          customBorder: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: mark,
        ),
      ),
    );
  }

  /// The header of a narrow window: you, the computer, search.
  Widget narrowTop() {
    final tone = context.tone;
    return SizedBox(
      height: 56,
      child: Stack(
        children: [
          if (!tone.glass) const Positioned.fill(child: WindowDrag()),
          Padding(
            padding: EdgeInsets.only(
              left: 4,
              right: 4 + (tone.glass ? 0 : WindowChrome.reserved(context)),
            ),
            child: Row(
              children: [
                account(32),
                Expanded(
                  child: searching
                      ? TextField(
                          key: const ValueKey('home-search'),
                          controller: searchField,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: c.tr('搜索', 'Search'),
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (value) =>
                              setState(() => search = value.toLowerCase()),
                        )
                      : Align(
                          alignment: Alignment.centerLeft,
                          child: nodePicker(),
                        ),
                ),
                IconButton(
                  tooltip: searching
                      ? c.tr('清除', 'Clear')
                      : c.tr('搜索', 'Search'),
                  onPressed: tone.glass
                      ? () => setState(() {
                          searching = !searching;
                          if (!searching) {
                            searchField.clear();
                            search = '';
                          }
                        })
                      : openSearch,
                  icon: Icon(searching ? Symbols.close : Symbols.search),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The one thing to start from a narrow window, under the thumb.
  Widget createButton() {
    final tone = context.tone;
    final face = Container(
      width: 56,
      height: 56,
      decoration: ShapeDecoration(
        color: tone.ink,
        shape: const RoundedSuperellipseBorder(
          borderRadius: BorderRadius.all(Radius.circular(Tone.r16)),
        ),
        shadows: tone.lift,
      ),
      child: Icon(Symbols.add, size: 28, color: tone.base),
    );
    return category == 'space'
        ? Tooltip(
            message: c.tr('新建空间', 'New space'),
            child: GestureDetector(onTap: () => create('space'), child: face),
          )
        : ActionMenu<String>(
            tooltip: c.tr('新建', 'Create'),
            alignEnd: true,
            onSelected: create,
            items: createItems(),
            child: face,
          );
  }

  /// When anything was last said there.
  DateTime? lastActivity(String id) {
    final last = c.node.latestText(id);
    return last == null ? null : DateTime.parse(last.createdAt).toLocal();
  }

  /// The latest thing said there, as one line; a group names who said it.
  String? preview(Json value, bool isGroup) {
    final last = c.node.latestText(value['conversationId'] as String);
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

  static const _rowDesktop = 64.0, _rowPhone = 72.0;

  /// One row of the list: who, when, and what follows from [second].
  Widget rowFrame({
    required Key key,
    required String id,
    required Widget avatar,
    required String name,
    required String time,
    required List<Widget> second,
    required VoidCallback onTap,
    String kind = '',
    bool selected = false,
  }) {
    final tone = context.tone;
    final glass = tone.glass;
    final text = Theme.of(context).textTheme;
    const corners = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.all(Radius.circular(Tone.r8)),
    );
    final small = text.labelSmall?.copyWith(height: 16 / 12);
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = id),
      onExit: (_) => setState(() => hovered = null),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: AnimatedContainer(
          duration: Motion.tint,
          decoration: ShapeDecoration(
            // Hover is flat and immediate; the chosen row is marked behind.
            color: !glass && !selected && hovered == id
                ? tone.raised.withValues(alpha: .6)
                : Colors.transparent,
            shape: corners,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: key,
              customBorder: corners,
              hoverColor: Colors.transparent,
              highlightColor: tone.raised.withValues(alpha: .6),
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: glass ? 20 : 8),
                child: Row(
                  children: [
                    avatar,
                    SizedBox(width: glass ? 14 : 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.titleMedium,
                                ),
                              ),
                              if (kind.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(kind, style: small),
                              ],
                              if (time.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(time, style: small),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          SizedBox(
                            height: 20,
                            child: DefaultTextStyle.merge(
                              style: TextStyle(
                                fontSize: 14,
                                height: 20 / 14,
                                color: tone.ink2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              child: Row(children: second),
                            ),
                          ),
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

  /// A conversation: the last thing said in it. A ring while its Dot works,
  /// the words 等你确认 and a dot when it waits for you, a dot when unread.
  Widget row(Json value, bool narrow) {
    final tone = context.tone;
    final isGroup = value['kind'] == 'group';
    final entity = isGroup
        ? c.node.groups.firstWhere((x) => x['groupId'] == value['groupId'])
        : c.node.bots.firstWhere((x) => x['botId'] == value['botId']);
    final id = value['conversationId'] as String;
    final state = c.node.activities[id]?.state;
    final working = state != null && state != 'idle';
    final last = preview(value, isGroup);
    final lastAt = lastActivity(id);
    // Something in there is waiting for your answer.
    final waiting = c.node.flows[id]?.state == 'waiting';
    final unread = c.reading.unread(
      c.selectedNodeId!,
      id,
      c.incomingSequence(id),
    );
    final size = tone.glass ? 44.0 : 36.0;
    Widget dot(String key) => Container(
      key: ValueKey('$key-$id'),
      width: 8,
      height: 8,
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(color: tone.ink, shape: BoxShape.circle),
    );
    return rowFrame(
      key: ValueKey('conversation-$id'),
      id: id,
      selected: !narrow && conversation == id,
      avatar: isGroup
          ? GroupAvatar(
              size: size,
              working: working,
              avatars: [
                for (final bot in c.node.bots)
                  if ((entity['botIds'] as List).contains(bot['botId']))
                    object(bot['avatar']),
              ],
            )
          : CatAvatar.of(
              entity,
              size: size,
              working: working,
              twitch: hovered == id,
            ),
      name: '${entity[isGroup ? 'name' : 'displayName']}',
      time: lastAt == null ? '' : rowTime(c, lastAt),
      onTap: () => open(value, narrow),
      second: [
        if (waiting) ...[
          Text(
            c.tr('等你确认', 'Needs your OK'),
            style: TextStyle(
              color: tone.ink,
              fontWeight: Theme.of(context).textTheme.titleMedium?.fontWeight,
            ),
          ),
          const SizedBox(width: 8),
        ] else if (working) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: tone.ink, width: 1.5),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(child: Text(last ?? '')),
        if (unread && !waiting) dot('unread'),
        if (waiting)
          Semantics(
            label: c.tr('等你确认', 'Needs your OK'),
            child: dot('waiting'),
          ),
      ],
    );
  }

  void selectCategory(String value) {
    if (value == 'plugins' && MediaQuery.sizeOf(context).width < 840) {
      // A narrow window has no room to keep the list beside it.
      pushPage(context, PluginCenterPage(client: c, kind: 'skills'));
      return;
    }
    setState(() {
      c.workspace['category:${c.selectedNodeId}'] = value;
      conversation = savedConversation(value, c.selectedNodeId);
      details = null;
      flowFocus = null;
      previewFile = null;
      settingsPart = null;
    });
    c.saveContent();
  }

  void showSpace(Space space, [Rect? from]) {
    c.workspace['category:${c.selectedNodeId}'] = 'space';
    c.workspace['space:${c.selectedNodeId}'] = space.spaceId;
    c.saveContent();
    setState(() {
      selectedSpace = space.spaceId;
      spaceFrom = from;
      details = null;
      flowFocus = null;
      previewFile = null;
      settingsPart = null;
    });
    if (MediaQuery.sizeOf(context).width < 840) {
      final page = SpacePage(
        client: c,
        nodeId: c.selectedNodeId!,
        spaceId: space.spaceId,
      );
      if (from == null) {
        pushPage(context, page);
      } else {
        Navigator.of(context).push(GrowRoute<void>(page, from: from));
      }
    }
  }

  void closeSpace() => setState(() {
    selectedSpace = null;
    c.workspace.remove('space:${c.selectedNodeId}');
    c.saveContent();
  });

  /// A space: what it is called and whose it is.
  Widget spaceRow(Space space, bool narrow, {bool mixed = false}) {
    final bot = c.node.bots.where((b) => b['botId'] == space.botId).firstOrNull;
    return rowFrame(
      key: ValueKey('space-${space.spaceId}'),
      id: 'space:${space.spaceId}',
      selected:
          !narrow && category == 'space' && selectedSpace == space.spaceId,
      avatar: CatAvatar.of(
        bot ??
            const {
              'avatar': {'color': '#8C8376', 'shape': 'dot'},
            },
        size: context.tone.glass ? 44 : 36,
      ),
      name: space.name,
      kind: mixed ? c.tr('空间', 'Space') : '',
      time: rowTime(c, DateTime.parse(space.updatedAt).toLocal()),
      onTap: () => showSpace(space),
      second: [Expanded(child: Text('${bot?['displayName'] ?? ''}'))],
    );
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([c, c.node, c.reading]),
    builder: (context, child) => LayoutBuilder(
      builder: (context, constraints) {
        final tone = context.tone;
        final narrow = constraints.maxWidth < 840;
        final section = category;
        final updateCommand =
            objects(c.account.me?['nodes'])
                    .where((n) => n['nodeId'] == c.selectedNodeId)
                    .firstOrNull?['updateCommand']
                as String?;
        final active = c.node.conversations
            .where(
              (x) => x['kind'] == 'dm'
                  ? c.node.bots.any(
                      (b) => b['botId'] == x['botId'] && b['archived'] != true,
                    )
                  : c.node.groups.any(
                      (g) =>
                          g['groupId'] == x['groupId'] && g['archived'] != true,
                    ),
            )
            .toList();
        String nameOf(Json value) {
          final entity = value['kind'] == 'group'
              ? c.node.groups.firstWhere(
                  (x) => x['groupId'] == value['groupId'],
                )
              : c.node.bots.firstWhere((x) => x['botId'] == value['botId']);
          return '${entity['name'] ?? entity['displayName']}'.toLowerCase();
        }

        final spaces = c.node.spaces.values
            .where(
              (s) =>
                  s.version > 0 &&
                  !s.archived &&
                  s.name.toLowerCase().contains(search),
            )
            .toList();
        // What the section lists, by id: conversations, spaces, or both by
        // when they last moved.
        Map<String, Widget Function()> rowsNow() {
          final rows = <String, Widget Function()>{};
          if (section == 'recent') {
            final mixed =
                <({String id, DateTime? at, Widget Function() build})>[
                  for (final x in active)
                    if (nameOf(x).contains(search))
                      (
                        id: x['conversationId'] as String,
                        at: lastActivity(x['conversationId'] as String),
                        build: () => row(x, narrow),
                      ),
                  for (final s in spaces)
                    (
                      id: 'space:${s.spaceId}',
                      at: DateTime.parse(s.updatedAt).toLocal(),
                      build: () => spaceRow(s, narrow, mixed: true),
                    ),
                ]..sort(
                  (a, b) =>
                      (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)),
                );
            for (final item in mixed) {
              rows[item.id] = item.build;
            }
          } else if (section == 'space') {
            for (final s in spaces) {
              rows['space:${s.spaceId}'] = () => spaceRow(s, narrow);
            }
          } else {
            for (final x in active) {
              if ((x['kind'] == 'group' ? 'group' : 'dot') == section &&
                  nameOf(x).contains(search)) {
                rows[x['conversationId'] as String] = () => row(x, narrow);
              }
            }
          }
          return rows;
        }

        final creating =
            (section == 'dot' || section == 'recent') &&
            creatingBot != null &&
            creatingBot?['nodeId'] == c.selectedNodeId;
        final conversations = ListenableBuilder(
          listenable: c.node.summaries,
          builder: (context, _) {
            // A new message changes the order, so it is read here.
            final rows = rowsNow();
            return active.isEmpty &&
                    creatingBot == null &&
                    (section != 'space' || spaces.isEmpty) &&
                    (section != 'recent' || spaces.isEmpty)
                ? Center(
                    child: IconButton(
                      tooltip: c.selectedNodeId == null
                          ? c.tr('添加电脑', 'Add computer')
                          : section == 'space'
                          ? c.tr('新建空间', 'New space')
                          : c.tr('新建 Bot', 'New Bot'),
                      onPressed: () => c.selectedNodeId == null
                          ? openPage(context, _addComputer(), form: true)
                          : create(section == 'space' ? 'space' : 'bot'),
                      icon: const CatAvatar(size: 56),
                    ),
                  )
                : GlideList(
                    key: PageStorageKey(
                      '${c.account.me?['user']?['userId']}:${c.selectedNodeId}:$section',
                    ),
                    padding: EdgeInsets.fromLTRB(
                      tone.glass ? 0 : 8,
                      tone.glass ? 2 : 0,
                      tone.glass ? 0 : 8,
                      narrow ? 88 : 8,
                    ),
                    extent: tone.glass ? _rowPhone : _rowDesktop,
                    selected: narrow
                        ? null
                        : section == 'space'
                        ? (selectedSpace == null
                              ? null
                              : 'space:$selectedSpace')
                        : conversation,
                    ids: [if (creating) 'creating', ...rows.keys],
                    builder: (context, id) => id == 'creating'
                        ? ListTile(
                            key: const ValueKey('bot-creating'),
                            leading: CatAvatar.of(creatingBot!),
                            title: Text(
                              '${creatingBot!['displayName']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: ShiningText(
                              text: c.tr('创建中…', 'Creating…'),
                            ),
                          )
                        : rows[id]!(),
                  );
          },
        );
        final notices = [
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
                    icon: const Icon(Symbols.refresh),
                  ),
                ],
              ),
            ),
        ];
        // What waits for you: a count on Recent, a dot on the kind it is in.
        bool needs(Json x) {
          final id = x['conversationId'] as String;
          return c.node.flows[id]?.state == 'waiting' ||
              (c.selectedNodeId != null &&
                  c.reading.unread(
                    c.selectedNodeId!,
                    id,
                    c.incomingSequence(id),
                  ));
        }

        final waitingCount = active.where(needs).length;
        final marked = {
          if (active.any((x) => x['kind'] != 'group' && needs(x))) 'dot',
          if (active.any((x) => x['kind'] == 'group' && needs(x))) 'group',
        };
        // Settings stand in for the section while they are open and there is
        // room for their list.
        final inSettings = settingsPart != null && !narrow;
        final hasChat =
            !inSettings &&
            section != 'space' &&
            section != 'plugins' &&
            conversation != null &&
            active.any((x) => x['conversationId'] == conversation);
        final panel = hasChat ? details : null;
        // Spaces and plugins fill the window; the rest have a list beside them.
        final listed =
            inSettings || (section != 'plugins' && section != 'space');
        final widest = (constraints.maxWidth - HomeRail.width - 420).clamp(
          240.0,
          560.0,
        );
        final sidebar = !listed
            ? 0.0
            : (dragging ?? c.prefs.sidebarWidth ?? 292.0).clamp(240.0, widest);
        final flowShown = hasChat && flowFocus != null;
        final fileShown = hasChat && previewFile != null;
        final panelShown = fileShown || flowShown || panel != null;
        // Bot details lie over the window as a drawer; Flow and files stand
        // beside the conversation when there is room.
        final drawer = !fileShown && !flowShown && panel != null;
        final panelWidth = fileShown
            ? (expandedFile
                  ? constraints.maxWidth
                  : 500.0.clamp(0.0, constraints.maxWidth))
            : drawer
            ? 600.0.clamp(0.0, constraints.maxWidth - HomeRail.width)
            : 340.0;
        final inlinePanel =
            panelShown &&
            !drawer &&
            constraints.maxWidth - HomeRail.width - sidebar - panelWidth >= 400;
        void closePanel() => setState(() {
          details = null;
          c.workspace.remove('details:${c.selectedNodeId}');
          c.saveContent();
          flowFocus = null;
          previewFile = null;
          expandedFile = false;
        });
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
        // What fills the window beside the list. A new one rises into place.
        final spaceShown =
            section == 'space' &&
            selectedSpace != null &&
            c.node.spaces[selectedSpace]?.archived == false;
        final main = inSettings
            // Its own navigator, so that what a setting opens stays in this
            // part of the window with a way back.
            ? Navigator(
                key: ValueKey('settings:${c.selectedNodeId}:$settingsPart'),
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) =>
                      SettingsPage(client: c, sectionId: settingsPart),
                ),
              )
            : section == 'plugins'
            ? PluginCenterPage(
                key: ValueKey('plugins:${c.selectedNodeId}'),
                client: c,
                kind: 'skills',
                embedded: true,
              )
            : section == 'space'
            // The gallery, and over it the space that is open: it grows out
            // of its tile and goes back into it.
            ? Navigator(
                key: ValueKey('spaces:${c.selectedNodeId}'),
                pages: [
                  GrowPage<void>(
                    key: const ValueKey('gallery'),
                    child: SpaceGallery(
                      client: c,
                      spaces: spaces,
                      titled: true,
                      onOpen: showSpace,
                      onCreate: () => create('space'),
                    ),
                  ),
                  if (spaceShown)
                    GrowPage<void>(
                      key: ValueKey('space:$selectedSpace'),
                      from: spaceFrom,
                      child: SpacePage(
                        key: ValueKey('${c.selectedNodeId}:$selectedSpace'),
                        client: c,
                        nodeId: c.selectedNodeId!,
                        spaceId: selectedSpace!,
                        embedded: true,
                        onBack: closeSpace,
                      ),
                    ),
                ],
                onDidRemovePage: (page) {
                  if (page.key == ValueKey('space:$selectedSpace')) {
                    closeSpace();
                  }
                },
              )
            : hasChat
            ? ChatPage(
                key: ValueKey('${c.selectedNodeId}:$conversation'),
                client: c,
                conversationId: conversation!,
                embedded: true,
                readingVisible: !panelShown || inlinePanel,
                reserveControls: !panelShown,
                onDetails: (bot) => setState(() {
                  details = bot;
                  c.workspace['details:${c.selectedNodeId}'] = bot;
                  c.saveContent();
                  flowFocus = null;
                  previewFile = null;
                }),
                flowOpen: flowShown,
                onFlow: (focus) => setState(() {
                  details = null;
                  c.workspace.remove('details:${c.selectedNodeId}');
                  c.saveContent();
                  previewFile = null;
                  flowFocus = flowFocus == null ? focus : null;
                }),
              )
            : Stack(
                children: const [
                  Positioned.fill(child: WindowDrag()),
                  Center(
                    child: Opacity(opacity: .08, child: CatAvatar(size: 72)),
                  ),
                ],
              );
        final mainKey = inSettings
            ? 'settings:$settingsPart'
            : section == 'plugins'
            ? 'plugins'
            : section == 'space'
            ? 'spaces'
            : hasChat
            ? 'chat:$conversation'
            : 'empty';
        return PopScope(
          canPop:
              !Platform.isAndroid ||
              ModalRoute.of(context)!.willHandlePopInternally,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && Platform.isAndroid) {
              if (panelShown) {
                closePanel();
              } else {
                const MethodChannel('app.nekodot/lifecycle')
                    .invokeMethod('background');
              }
            }
          },
          child: SpaceScope(
            open: showSpace,
            child: Scaffold(
              body: narrow
                  ? SafeArea(
                      bottom: false,
                      child: Column(
                        children: [
                          narrowTop(),
                          ...notices,
                          Expanded(
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: KeyedSubtree(
                                    key: ValueKey('list:$section'),
                                    child: section == 'space'
                                        ? SpaceGallery(
                                            client: c,
                                            spaces: spaces,
                                            onOpen: showSpace,
                                            onCreate: () => create('space'),
                                          )
                                        : conversations,
                                  ),
                                ),
                                Positioned(
                                  right: 16,
                                  bottom: 16,
                                  child: createButton(),
                                ),
                              ],
                            ),
                          ),
                          HomeNav(
                            section: section,
                            onSelect: selectCategory,
                            waiting: waitingCount,
                            marked: marked,
                            tr: c.tr,
                          ),
                        ],
                      ),
                    )
                  : FilePreviewScope(
                      open: (file) => setState(() {
                        previewFile = file;
                        expandedFile = false;
                        details = null;
                        c.workspace.remove('details:${c.selectedNodeId}');
                        c.saveContent();
                        flowFocus = null;
                      }),
                      child: Stack(
                        children: [
                          Row(
                            children: [
                              HomeRail(
                                section: inSettings ? '' : section,
                                onSelect: selectCategory,
                                waiting: waitingCount,
                                marked: marked,
                                account: account(30, onRail: true),
                                tr: c.tr,
                              ),
                              if (sidebar > 0)
                                SizedBox(
                                  width: sidebar,
                                  child: Material(
                                    color: tone.sidebar,
                                    child: Column(
                                      children: inSettings
                                          ? [
                                              SizedBox(
                                                height: 48,
                                                child: Stack(
                                                  children: [
                                                    const Positioned.fill(
                                                      child: WindowDrag(),
                                                    ),
                                                    Align(
                                                      alignment:
                                                          Alignment.centerLeft,
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              left: 20,
                                                            ),
                                                        child: Text(
                                                          c.tr(
                                                            '设置',
                                                            'Settings',
                                                          ),
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .titleLarge,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Expanded(
                                                child: SettingsNav(
                                                  sections: settingsParts(c),
                                                  current: settingsPart!,
                                                  padding:
                                                      const EdgeInsets.fromLTRB(
                                                        8,
                                                        4,
                                                        8,
                                                        12,
                                                      ),
                                                  onPick: (id) => setState(
                                                    () => settingsPart = id,
                                                  ),
                                                ),
                                              ),
                                            ]
                                          : [
                                              top(),
                                              ...notices,
                                              Expanded(
                                                child: KeyedSubtree(
                                                  key: ValueKey(
                                                    'list:$section',
                                                  ),
                                                  child: conversations,
                                                ),
                                              ),
                                            ],
                                    ),
                                  ),
                                ),
                              if (sidebar > 0)
                                VerticalDivider(
                                  width: Tone.hair,
                                  thickness: Tone.hair,
                                  color: tone.line,
                                ),
                              Expanded(
                                child: AnimatedPadding(
                                  duration: Motion.still(context)
                                      ? Duration.zero
                                      : panelShown
                                      ? Motion.side.duration
                                      : Motion.sideLeave,
                                  curve: panelShown
                                      ? Motion.leave
                                      : Motion.leave,
                                  padding: EdgeInsets.only(
                                    right: inlinePanel ? panelWidth : 0,
                                  ),
                                  child: Appear(
                                    key: ValueKey(
                                      'main:${c.selectedNodeId}:$mainKey',
                                    ),
                                    child: main,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (panelShown && !inlinePanel)
                            Positioned.fill(
                              child: GestureDetector(
                                onTap: closePanel,
                                child: ColoredBox(
                                  color: drawer
                                      ? tone.dim.withValues(alpha: 0)
                                      : tone.dim,
                                ),
                              ),
                            ),
                          Positioned(
                            key: const ValueKey('workspace-side-panel'),
                            top: 0,
                            bottom: 0,
                            right: 0,
                            child: SidePanel(
                              width: panelWidth,
                              floating: drawer,
                              child: fileShown
                                  ? SafeArea(
                                      child: Column(
                                        children: [
                                          FileTabs(
                                            files: previewFiles,
                                            at: previewAt,
                                            closeLabel: c.tr(
                                              '关闭标签',
                                              'Close tab',
                                            ),
                                            onSelect: (index) => setState(
                                              () => previewAt = index,
                                            ),
                                            onClose: (index) => setState(() {
                                              previewFiles.removeAt(index);
                                              if (previewAt > index ||
                                                  previewAt ==
                                                      previewFiles.length) {
                                                previewAt = (previewAt - 1)
                                                    .clamp(0, previewAt);
                                              }
                                              if (previewFiles.isEmpty) {
                                                expandedFile = false;
                                              }
                                            }),
                                          ),
                                          Expanded(
                                            // Its bar is under the tabs, clear
                                            // of the window's own controls.
                                            child: WindowSheetScope(
                                              child: FileViewer(
                                                key: ValueKey(
                                                  '${c.selectedNodeId}:${previewFile!['fileId']}',
                                                ),
                                                client: c,
                                                file: previewFile!,
                                                tabbed: true,
                                                onClose: closePanel,
                                                expanded: expandedFile,
                                                onExpand: () => setState(
                                                  () => expandedFile =
                                                      !expandedFile,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : flowShown
                                  ? flowPanel()
                                  : panel == null
                                  ? null
                                  : BotDetails(
                                      key: ValueKey(panel['botId']),
                                      client: c,
                                      bot: panel,
                                      onClose: closePanel,
                                    ),
                            ),
                          ),
                          if (sidebar > 0)
                            Positioned(
                              left: HomeRail.width + sidebar - 4,
                              top: 0,
                              bottom: 0,
                              width: 9,
                              child: SplitHandle(
                                onDrag: (dx) => setState(
                                  () => dragging = (sidebar + dx).clamp(
                                    240.0,
                                    widest,
                                  ),
                                ),
                                onEnd: () {
                                  final width = dragging;
                                  setState(() => dragging = null);
                                  if (width != null) {
                                    c.prefs.setSidebarWidth(width);
                                  }
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
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
