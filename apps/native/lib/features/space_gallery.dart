import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../data/client.dart';
import '../data/spaces.dart';
import '../platform/desktop.dart';
import '../ui/design.dart';
import 'files.dart';
import 'space_mark.dart';
import 'space_webview.dart';
import 'time_labels.dart';

/// Spaces as a gallery, one tile each, in the order given. A tile shows what
/// its space last looked like and opens it; with none yet, the one thing to
/// do is make the first.
class SpaceGallery extends StatefulWidget {
  final NekodotClient client;
  final List<Space> spaces;

  /// Opens a space; the rectangle is where its tile's picture is in the
  /// window, for the page to grow out of.
  final void Function(Space space, Rect from) onOpen;
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
  State<SpaceGallery> createState() => _SpaceGalleryState();
}

class _SpaceGalleryState extends State<SpaceGallery> {
  NekodotClient get c => widget.client;

  /// The versions of spaces whose picture did not come out here; they are
  /// not tried again.
  final failed = <String>{};
  bool taking = false;

  /// Whether the gallery is what is looked at. Under an open space or
  /// another page no picture is taken.
  bool current = true;

  /// The room a space has when it is open: its picture is taken at this size.
  Size room = Size.zero;

  @override
  void initState() {
    super.initState();
    c.spaces.thumbs.addListener(due);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    current = ModalRoute.of(context)?.isCurrent ?? true;
    WidgetsBinding.instance.addPostFrameCallback((_) => due());
  }

  @override
  void didUpdateWidget(SpaceGallery old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => due());
  }

  @override
  void dispose() {
    c.spaces.thumbs.removeListener(due);
    super.dispose();
  }

  void due() => unawaited(take());

  /// Takes the pictures that are missing, older than their space, or due
  /// again because the space has been open, one after another and out of
  /// sight. A space loaded for its picture reaches nothing but its own
  /// files, and only reads its records.
  Future<void> take() async {
    if (taking ||
        !mounted ||
        !current ||
        !(Platform.isWindows || Platform.isAndroid)) {
      return;
    }
    taking = true;
    WebViewEnvironment? environment;
    try {
      while (mounted && current && !room.isEmpty) {
        final storage = c.store, nodeId = c.selectedNodeId;
        if (storage == null ||
            nodeId == null ||
            !c.connection.ready ||
            c.nodes[nodeId]?.online != true) {
          break;
        }
        final space = widget.spaces
            .where(
              (s) =>
                  s.fileId != null &&
                  c.spaces.thumbs.version(nodeId, s.spaceId) != s.version &&
                  !failed.contains('${s.spaceId}:${s.version}'),
            )
            .firstOrNull;
        if (space == null) break;
        try {
          if (Platform.isWindows && environment == null) {
            if (await WebViewEnvironment.getAvailableVersion() == null) break;
            environment = await createSpaceEnvironment(
              storage.file('spaces/browser').path,
            );
          }
          final bundle = SpaceBundle(
            await downloadFile(c, space.fileId!, targetNode: nodeId),
          );
          await c.spaces.sync(nodeId, space.spaceId);
          final picture = await pictureOf(
            SpaceSite(
              client: c,
              nodeId: nodeId,
              space: Space.fromJson({
                ...space.toJson(),
                'allowedOrigins': const <String>[],
              }),
              bundle: bundle,
              writes: false,
            ),
            room,
            environment,
          );
          if (picture == null) {
            failed.add('${space.spaceId}:${space.version}');
          } else {
            await c.spaces.thumbs.keep(
              nodeId,
              space.spaceId,
              space.version,
              picture,
            );
          }
        } catch (_) {
          // What the tile showed stays: the last picture, or the Dot's face.
          failed.add('${space.spaceId}:${space.version}');
        }
      }
    } finally {
      await environment?.dispose();
      taking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tone = context.tone, text = Theme.of(context).textTheme;
    final spaces = widget.spaces, titled = widget.titled;
    final grid = spaces.isEmpty
        ? Center(
            child: OutlinedButton(
              key: const ValueKey('space-create-first'),
              onPressed: widget.onCreate,
              child: Text(c.tr('新建空间', 'New space')),
            ),
          )
        : LayoutBuilder(
            builder: (context, box) {
              room = box.biggest;
              final side = titled ? 24.0 : 16.0,
                  gap = titled ? 20.0 : 16.0,
                  columns = titled
                      ? ((box.maxWidth - side * 2 + gap) / (260 + gap))
                            .floor()
                            .clamp(2, 6)
                      : 2,
                  width =
                      (box.maxWidth - side * 2 - gap * (columns - 1)) / columns;
              return ListenableBuilder(
                listenable: c.spaces.thumbs,
                builder: (context, _) => GridView.builder(
                  padding: EdgeInsets.fromLTRB(side, 8, side, 28),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: gap,
                    mainAxisSpacing: gap,
                    mainAxisExtent: width * 10 / 16 + _Tile.foot,
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
                        space: space,
                        time: rowTime(
                          c,
                          DateTime.parse(space.updatedAt).toLocal(),
                        ),
                        bot: bot,
                        picture: c.spaces.thumbs.picture(
                          c.selectedNodeId!,
                          space.spaceId,
                        ),
                        onOpen: (from) => widget.onOpen(space, from),
                      ),
                    );
                  },
                ),
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
                        onPressed: widget.onCreate,
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
  /// The line under the picture: the space's mark and whose space it is,
  /// its name and when it last changed.
  static const foot = 40.0;
  final Space space;
  final String time;
  final Map<String, dynamic>? bot;

  /// What the space last looked like; its mark stands in until there is a
  /// picture.
  final Uint8List? picture;
  final ValueChanged<Rect> onOpen;
  const _Tile({
    required this.space,
    required this.time,
    required this.bot,
    required this.picture,
    required this.onOpen,
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
    final picture = widget.picture;
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final box = context.findRenderObject()! as RenderBox;
          widget.onOpen(
            box.localToGlobal(Offset.zero) &
                Size(box.size.width, box.size.height - _Tile.foot),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: Motion.still(context) ? Duration.zero : Motion.tint,
                clipBehavior: Clip.antiAlias,
                // The line sits over the picture, so its edge stays crisp.
                foregroundDecoration: ShapeDecoration(
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(Tone.r12),
                    side: BorderSide(
                      color: hovered ? tone.ink3 : tone.line,
                      width: Tone.hair,
                    ),
                  ),
                ),
                decoration: ShapeDecoration(
                  color: hovered ? tone.raised : tone.bubble,
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(Tone.r12),
                  ),
                ),
                child: AnimatedSwitcher(
                  duration: Motion.span(context, Motion.swap),
                  child: picture == null
                      ? Center(child: SpaceMark(space: widget.space, size: 44))
                      : LayoutBuilder(
                          key: const ValueKey('space-tile-picture'),
                          builder: (context, box) => Image.memory(
                            picture,
                            width: box.maxWidth,
                            height: box.maxHeight,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            cacheWidth:
                                (box.maxWidth *
                                        MediaQuery.devicePixelRatioOf(context))
                                    .round(),
                            filterQuality: FilterQuality.medium,
                            gaplessPlayback: true,
                          ),
                        ),
                ),
              ),
            ),
            SizedBox(
              height: _Tile.foot,
              child: Row(
                children: [
                  SpaceMark(space: widget.space, size: 20),
                  Container(
                    width: 1,
                    height: 12,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    color: tone.line,
                  ),
                  CatAvatar.of(bot, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.space.name,
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
