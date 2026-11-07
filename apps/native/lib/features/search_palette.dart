import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../ui/design.dart';

/// One thing the search panel can open: a conversation, or something to do.
class SearchEntry {
  final String section, title;
  final String? detail;
  final Widget leading;
  final VoidCallback open;
  const SearchEntry({
    required this.section,
    required this.title,
    required this.leading,
    required this.open,
    this.detail,
  });
}

/// The desktop's search: a panel over the window that finds a group, a Bot or
/// something to do, opened with the search button or Ctrl+K.
Future<void> showSearchPalette(
  BuildContext context,
  NekodotClient c,
  List<SearchEntry> entries,
) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: c.tr('关闭', 'Close'),
  barrierColor: Colors.black.withValues(alpha: .18),
  transitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 160),
  pageBuilder: (context, _, _) => SearchPalette(client: c, entries: entries),
  transitionBuilder: (context, animation, _, child) {
    final curve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curve,
      child: ScaleTransition(
        scale: Tween(begin: .98, end: 1.0).animate(curve),
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
  },
);

class SearchPalette extends StatefulWidget {
  final NekodotClient client;
  final List<SearchEntry> entries;
  const SearchPalette({super.key, required this.client, required this.entries});
  @override
  State<SearchPalette> createState() => _SearchPaletteState();
}

class _SearchPaletteState extends State<SearchPalette> {
  final query = TextEditingController();
  final list = ScrollController();
  int chosen = 0;

  List<SearchEntry> get found {
    final words = query.text.trim().toLowerCase();
    return [
      for (final entry in widget.entries)
        if (words.isEmpty ||
            entry.title.toLowerCase().contains(words) ||
            (entry.detail ?? '').toLowerCase().contains(words))
          entry,
    ];
  }

  @override
  void dispose() {
    query.dispose();
    list.dispose();
    super.dispose();
  }

  void pick(SearchEntry entry) {
    Navigator.pop(context);
    entry.open();
  }

  void move(int by, int count) {
    if (count == 0) return;
    setState(() => chosen = (chosen + by) % count);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client, tone = context.tone;
    final text = Theme.of(context).textTheme;
    final results = found;
    if (chosen >= results.length) chosen = 0;
    final rows = <Widget>[];
    String? section;
    for (final (index, entry) in results.indexed) {
      if (entry.section != section) {
        section = entry.section;
        rows.add(
          Padding(
            padding: EdgeInsets.fromLTRB(16, rows.isEmpty ? 4 : 14, 16, 6),
            child: Text(
              section,
              style: text.bodySmall?.copyWith(fontSize: 12, color: tone.ink3),
            ),
          ),
        );
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Material(
            color: index == chosen ? tone.hover : Colors.transparent,
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('search-entry-$index'),
              customBorder: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onTap: () => pick(entry),
              onHover: (inside) {
                if (inside && chosen != index) setState(() => chosen = index);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    SizedBox(width: 32, child: Center(child: entry.leading)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium?.copyWith(fontSize: 14),
                          ),
                          if (entry.detail != null && entry.detail!.isNotEmpty)
                            Text(
                              entry.detail!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall?.copyWith(
                                fontSize: 13,
                                color: tone.ink2,
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
      );
    }
    final height = MediaQuery.sizeOf(context).height;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(top: height * .12, left: 24, right: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 620, maxHeight: height * .7),
          child: Panel(
            lifted: true,
            radius: 16,
            child: Material(
              type: MaterialType.transparency,
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                      move(1, results.length),
                  const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                      move(-1, results.length),
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
                      child: TextField(
                        key: const ValueKey('search-palette-input'),
                        controller: query,
                        autofocus: true,
                        style: text.titleLarge?.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w400,
                        ),
                        decoration: InputDecoration(
                          hintText: c.tr(
                            '搜索 Bot、群聊、操作',
                            'Search Bots, groups, actions',
                          ),
                          prefixIcon: const Icon(Icons.search),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                        ),
                        onChanged: (_) => setState(() => chosen = 0),
                        onSubmitted: (_) {
                          if (results.isNotEmpty) pick(results[chosen]);
                        },
                      ),
                    ),
                    if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                        child: Text(
                          c.tr('没有找到', 'Nothing found'),
                          style: text.bodyMedium?.copyWith(color: tone.ink3),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView(
                          controller: list,
                          shrinkWrap: true,
                          padding: const EdgeInsets.only(bottom: 10),
                          children: rows,
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
}

/// What a conversation is called and its avatar, for the search panel.
SearchEntry conversationEntry(
  NekodotClient c,
  Json conversation, {
  required String? preview,
  required VoidCallback open,
}) {
  final group = conversation['kind'] == 'group';
  final entity = group
      ? c.node.groups.firstWhere((x) => x['groupId'] == conversation['groupId'])
      : c.node.bots.firstWhere((x) => x['botId'] == conversation['botId']);
  return SearchEntry(
    section: group ? c.tr('群聊', 'Groups') : 'Bot',
    title: '${entity[group ? 'name' : 'displayName']}',
    detail: preview,
    leading: group
        ? GroupAvatar(
            size: 28,
            avatars: [
              for (final bot in c.node.bots)
                if ((entity['botIds'] as List).contains(bot['botId']))
                  object(bot['avatar']),
            ],
          )
        : CatAvatar.of(entity, size: 28),
    open: open,
  );
}
