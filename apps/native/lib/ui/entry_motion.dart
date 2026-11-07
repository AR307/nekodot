import 'package:flutter/material.dart';

/// Brings something that just arrived into view once: it fades in and rises a
/// little. What you sent yourself also grows from its bottom-right corner, as
/// if it left the composer. Plays only when [play] is true at first build, so
/// scrolling an item away and back does not replay it.
class EntryMotion extends StatefulWidget {
  final Widget child;
  final bool play, own;
  const EntryMotion({
    super.key,
    required this.child,
    required this.play,
    this.own = false,
  });
  @override
  State<EntryMotion> createState() => _EntryMotionState();
}

class _EntryMotionState extends State<EntryMotion>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: widget.play ? 0 : 1,
  );
  late final curve = CurvedAnimation(
    parent: controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (controller.value < 1) {
      if (MediaQuery.disableAnimationsOf(context)) {
        controller.value = 1;
      } else if (!controller.isAnimating) {
        controller.forward();
      }
    }
  }

  @override
  void dispose() {
    curve.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: curve,
    child: widget.child,
    builder: (context, child) {
      final t = curve.value;
      if (t == 1) return child!;
      return Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 10),
          child: widget.own
              ? Transform.scale(
                  scale: .96 + .04 * t,
                  alignment: Alignment.bottomRight,
                  child: child,
                )
              : child,
        ),
      );
    },
  );
}
