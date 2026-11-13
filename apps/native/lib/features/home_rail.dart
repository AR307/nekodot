import 'package:flutter/material.dart';

import '../platform/desktop.dart';
import '../ui/design.dart';

/// Where home can go. `recent` mixes every conversation and space by when it
/// last moved; the rest show one kind each.
const homeSections = [
  (id: 'recent', icon: Icons.schedule, zh: '最近', en: 'Recent'),
  (id: 'dot', icon: Icons.chat_bubble_outline, zh: 'Dot', en: 'Dot'),
  (id: 'group', icon: Icons.forum_outlined, zh: '群聊', en: 'Groups'),
  (id: 'space', icon: Icons.space_dashboard_outlined, zh: '空间', en: 'Spaces'),
  (id: 'plugins', icon: Icons.extension_outlined, zh: '插件', en: 'Plugins'),
];

/// What needs you, drawn on a destination: a count on Recent, a dot elsewhere.
class _Mark extends StatelessWidget {
  final int? count;
  final Color ground, ink;
  const _Mark({this.count, required this.ground, required this.ink});
  @override
  Widget build(BuildContext context) => count == null
      ? Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: ground, shape: BoxShape.circle),
        )
      : Container(
          constraints: const BoxConstraints(minWidth: 16),
          height: 16,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: ground,
            shape: const StadiumBorder(),
          ),
          child: Text(
            count! > 99 ? '99+' : '$count',
            style: TextStyle(
              color: ink,
              fontSize: 12,
              height: 1,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
}

/// The desktop's navigation: a black rail with the destinations and, at its
/// foot, you. One marker glides behind the chosen destination.
class HomeRail extends StatelessWidget {
  final String section;
  final ValueChanged<String> onSelect;

  /// How many conversations wait for you, and which other sections hold one.
  final int waiting;
  final Set<String> marked;
  final Widget account;
  final String Function(String zh, String en) tr;
  const HomeRail({
    super.key,
    required this.section,
    required this.onSelect,
    required this.waiting,
    required this.marked,
    required this.account,
    required this.tr,
  });
  static const width = 64.0;
  static const _step = 60.0;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final index = homeSections.indexWhere((s) => s.id == section);
    return Container(
      width: width,
      color: tone.rail,
      child: Stack(
        children: [
          const Positioned.fill(child: WindowDrag()),
          Column(
            children: [
              const SizedBox(height: 12),
              const SizedBox(
                height: 34,
                child: Center(child: CatAvatar(color: '#ffffff', size: 26)),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: homeSections.length * _step,
                child: Stack(
                  children: [
                    if (index >= 0)
                      AnimatedPositioned(
                        duration: Motion.span(context, Motion.move),
                        curve: Motion.move,
                        top: index * _step,
                        left: 4,
                        width: 56,
                        height: 56,
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            color: tone.railMark,
                            shape: const RoundedSuperellipseBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ),
                    for (final (at, s) in homeSections.indexed)
                      Positioned(
                        top: at * _step,
                        left: 4,
                        width: 56,
                        height: 56,
                        child: _RailItem(
                          key: ValueKey('home-section-${s.id}'),
                          icon: s.icon,
                          label: tr(s.zh, s.en),
                          selected: s.id == section,
                          mark: s.id == 'recent'
                              ? (waiting > 0
                                    ? _Mark(
                                        count: waiting,
                                        ground: Colors.white,
                                        ink: Colors.black,
                                      )
                                    : null)
                              : marked.contains(s.id)
                              ? const _Mark(
                                  ground: Colors.white,
                                  ink: Colors.black,
                                )
                              : null,
                          onTap: () => onSelect(s.id),
                        ),
                      ),
                  ],
                ),
              ),
              const Spacer(),
              account,
              const SizedBox(height: 10),
            ],
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Widget? mark;
  final VoidCallback onTap;
  const _RailItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.mark,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : Colors.white.withValues(alpha: .64);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const RoundedSuperellipseBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          hoverColor: Colors.white.withValues(alpha: .08),
          highlightColor: Colors.white.withValues(alpha: .12),
          onTap: onTap,
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 22, color: color),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        height: 16 / 12,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (mark != null)
                Positioned(
                  top: mark is _Mark && (mark as _Mark).count != null ? 2 : 7,
                  right: mark is _Mark && (mark as _Mark).count != null
                      ? 5
                      : 13,
                  child: mark!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The phone's navigation: the same destinations along the bottom, under the
/// thumb. One pill glides behind the chosen icon.
class HomeNav extends StatelessWidget {
  final String section;
  final ValueChanged<String> onSelect;
  final int waiting;
  final Set<String> marked;
  final String Function(String zh, String en) tr;
  const HomeNav({
    super.key,
    required this.section,
    required this.onSelect,
    required this.waiting,
    required this.marked,
    required this.tr,
  });

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final index = homeSections.indexWhere((s) => s.id == section);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.base,
        border: Border(
          top: BorderSide(color: tone.line, width: Tone.hair),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
          child: SizedBox(
            height: 54,
            child: LayoutBuilder(
              builder: (context, box) {
                final slot = box.maxWidth / homeSections.length;
                return Stack(
                  children: [
                    if (index >= 0)
                      AnimatedPositioned(
                        duration: Motion.span(context, Motion.move),
                        curve: Motion.move,
                        left: index * slot + (slot - 56) / 2,
                        top: 0,
                        width: 56,
                        height: 30,
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            color: tone.raised,
                            shape: const StadiumBorder(),
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        for (final s in homeSections)
                          Expanded(
                            child: Semantics(
                              button: true,
                              selected: s.id == section,
                              child: InkWell(
                                key: ValueKey('home-section-${s.id}'),
                                highlightColor: Colors.transparent,
                                onTap: () => onSelect(s.id),
                                child: Column(
                                  children: [
                                    SizedBox(
                                      width: 56,
                                      height: 30,
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Center(
                                            child: Icon(
                                              s.icon,
                                              size: 24,
                                              color: s.id == section
                                                  ? tone.ink
                                                  : tone.ink3,
                                            ),
                                          ),
                                          if (s.id == 'recent' && waiting > 0)
                                            Positioned(
                                              top: -3,
                                              right: 4,
                                              child: _Mark(
                                                count: waiting,
                                                ground: tone.ink,
                                                ink: tone.base,
                                              ),
                                            )
                                          else if (marked.contains(s.id))
                                            Positioned(
                                              top: 3,
                                              right: 12,
                                              child: _Mark(
                                                ground: tone.ink,
                                                ink: tone.base,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      tr(s.zh, s.en),
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 16 / 12,
                                        color: s.id == section
                                            ? tone.ink
                                            : tone.ink3,
                                        fontWeight: s.id == section
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Rows of one height that glide to their new places when their order
/// changes. One marker glides behind the chosen row, so the choice is seen to
/// move rather than jump.
class GlideList extends StatelessWidget {
  final List<String> ids;
  final String? selected;
  final double extent;
  final Widget Function(BuildContext context, String id) builder;
  final EdgeInsets padding;
  const GlideList({
    super.key,
    required this.ids,
    required this.selected,
    required this.extent,
    required this.builder,
    this.padding = EdgeInsets.zero,
  });
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final span = Motion.span(context, Motion.move);
    final at = selected == null ? -1 : ids.indexOf(selected!);
    return SingleChildScrollView(
      padding: padding,
      child: SizedBox(
        height: ids.length * extent,
        child: Stack(
          children: [
            if (at >= 0)
              AnimatedPositioned(
                key: const ValueKey('home-selection'),
                duration: span,
                curve: Motion.move,
                top: at * extent + 1,
                left: 0,
                right: 0,
                height: extent - 2,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: tone.raised,
                    shape: const RoundedSuperellipseBorder(
                      borderRadius: BorderRadius.all(Radius.circular(Tone.r8)),
                    ),
                  ),
                ),
              ),
            for (final (index, id) in ids.indexed)
              AnimatedPositioned(
                key: ValueKey('row:$id'),
                duration: span,
                curve: Motion.move,
                top: index * extent,
                left: 0,
                right: 0,
                height: extent,
                child: Appear(
                  delay: Motion.delay(index),
                  child: builder(context, id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
