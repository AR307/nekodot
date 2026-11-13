import 'package:flutter/material.dart';

import '../data/client.dart';
import '../data/spaces.dart';
import '../platform/desktop.dart';
import '../ui/design.dart';
import 'time_labels.dart';

/// Spaces as a gallery, one tile each, in the order given. A tile opens its
/// space; with none yet, the one thing to do is make the first.
class SpaceGallery extends StatelessWidget {
  final NekodotClient client;
  final List<Space> spaces;
  final ValueChanged<Space> onOpen;
  final VoidCallback onCreate;

  /// Whether it fills the window beside the rail, with a bar of its own.
  final bool titled;
  const SpaceGallery({
    super.key,
    required this.client,
    required this.spaces,
    required this.onOpen,
    required this.onCreate,
    this.titled = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = client, tone = context.tone, text = Theme.of(context).textTheme;
    final grid = spaces.isEmpty
        ? Center(
            child: OutlinedButton(
              key: const ValueKey('space-create-first'),
              onPressed: onCreate,
              child: Text(c.tr('新建空间', 'New space')),
            ),
          )
        : LayoutBuilder(
            builder: (context, box) {
              final side = titled ? 24.0 : 16.0,
                  gap = titled ? 20.0 : 16.0,
                  columns = titled
                      ? ((box.maxWidth - side * 2 + gap) / (260 + gap))
                            .floor()
                            .clamp(2, 6)
                      : 2,
                  width =
                      (box.maxWidth - side * 2 - gap * (columns - 1)) / columns;
              return GridView.builder(
                padding: EdgeInsets.fromLTRB(side, 8, side, 28),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: gap,
                  mainAxisSpacing: gap,
                  mainAxisExtent: width * 10 / 16 + 40,
                ),
                itemCount: spaces.length,
                itemBuilder: (context, index) {
                  final space = spaces[index];
                  final bot = c.node.bots
                      .where((b) => b['botId'] == space.botId)
                      .firstOrNull;
                  return Appear(
                    key: ValueKey('space-tile-${space.spaceId}'),
                    delay: Motion.delay(index),
                    child: _Tile(
                      name: space.name,
                      time: rowTime(
                        c,
                        DateTime.parse(space.updatedAt).toLocal(),
                      ),
                      bot: bot,
                      onTap: () => onOpen(space),
                    ),
                  );
                },
              );
            },
          );
    if (!titled) return grid;
    return ColoredBox(
      color: tone.base,
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const Positioned.fill(child: WindowDrag()),
                Padding(
                  padding: const EdgeInsets.only(left: 24, right: 8),
                  child: Row(
                    children: [
                      Text(c.tr('空间', 'Spaces'), style: text.titleLarge),
                      const Spacer(),
                      OutlinedButton(
                        key: const ValueKey('space-create'),
                        onPressed: onCreate,
                        child: Text(c.tr('新建空间', 'New space')),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(width: WindowChrome.reserved(context)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: grid),
        ],
      ),
    );
  }
}

class _Tile extends StatefulWidget {
  final String name, time;
  final Map<String, dynamic>? bot;
  final VoidCallback onTap;
  const _Tile({
    required this.name,
    required this.time,
    required this.bot,
    required this.onTap,
  });
  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) {
    final tone = context.tone, text = Theme.of(context).textTheme;
    final bot =
        widget.bot ??
        const {
          'avatar': {'color': '#8C8376', 'shape': 'dot'},
        };
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: Motion.still(context) ? Duration.zero : Motion.tint,
                decoration: ShapeDecoration(
                  color: hovered ? tone.raised : tone.bubble,
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(Tone.r12),
                    side: BorderSide(color: tone.line, width: Tone.hair),
                  ),
                ),
                child: Center(child: CatAvatar.of(bot, size: 44)),
              ),
            ),
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  CatAvatar.of(bot, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.time,
                    style: TextStyle(
                      fontSize: 12,
                      color: tone.ink3,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
