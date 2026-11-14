import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'design.dart';

/// A page that grows out of the box that opened it and shrinks back into it
/// on the way out. With no box to grow from, it rises into place.
class GrowRoute<T> extends PageRoute<T> {
  final Widget? _page;
  final Rect? _box;

  /// [from] is where the box is in the window.
  GrowRoute(Widget page, {Rect? from}) : _page = page, _box = from;
  GrowRoute._of(GrowPage<T> page)
    : _page = null,
      _box = null,
      super(settings: page);

  // A page in a navigator's list is rebuilt in place: what it shows is read
  // from the list each time.
  Widget get page => _page ?? (settings as GrowPage<T>).child;
  Rect? get from => _page == null ? (settings as GrowPage<T>).from : _box;

  @override
  Color? get barrierColor => null;
  @override
  String? get barrierLabel => null;
  @override
  bool get maintainState => true;
  @override
  Duration get transitionDuration =>
      Motion.span(navigator!.context, Motion.zoom);
  @override
  Duration get reverseTransitionDuration =>
      Motion.still(navigator!.context) ? Duration.zero : Motion.pushLeave;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => page;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final from = this.from;
    final box = navigator!.context.findRenderObject() as RenderBox?;
    return _Grow(
      animation: animation,
      from: from == null || box == null || !box.hasSize
          ? null
          : box.globalToLocal(from.topLeft) & from.size,
      child: child,
    );
  }
}

/// A [GrowRoute] as one of a navigator's pages.
class GrowPage<T> extends Page<T> {
  final Widget child;
  final Rect? from;
  const GrowPage({super.key, required this.child, this.from});
  @override
  Route<T> createRoute(BuildContext context) => GrowRoute<T>._of(this);
}

class _Grow extends StatelessWidget {
  final Animation<double> animation;

  /// The box it grows from, in the navigator's own coordinates.
  final Rect? from;
  final Widget child;
  const _Grow({
    required this.animation,
    required this.from,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // In on the spring; out quicker, never speeding up on the way.
    double grown() {
      final t = animation.value;
      if (t == 0 || t == 1) return t;
      return animation.status == AnimationStatus.reverse
          ? 1 - Motion.leave.transform(1 - t)
          : Motion.zoom.transform(t);
    }

    return LayoutBuilder(
      builder: (context, box) {
        final area = Offset.zero & box.biggest;
        final start = from ?? area.shift(const Offset(0, 14));
        return AnimatedBuilder(
          animation: animation,
          child: child,
          // The page keeps its place in the tree from the first frame to the
          // last, so nothing in it starts over when it has finished growing.
          builder: (context, child) {
            final size = grown();
            final rect = Rect.lerp(start, area, size)!;
            final done = animation.isCompleted;
            return Stack(
              children: [
                Positioned.fromRect(
                  rect: rect,
                  child: Opacity(
                    opacity: Motion.fade.transform(animation.value),
                    child: ClipRRect(
                      clipBehavior: done ? Clip.none : Clip.antiAlias,
                      borderRadius: BorderRadius.circular(
                        from == null
                            ? 0
                            : lerpDouble(Tone.r12, 0, size.clamp(0, 1))!,
                      ),
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: area.width,
                        maxWidth: area.width,
                        minHeight: area.height,
                        maxHeight: area.height,
                        child: Transform.scale(
                          scale: rect.width / area.width,
                          alignment: Alignment.topLeft,
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
