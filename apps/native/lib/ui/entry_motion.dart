import 'package:flutter/material.dart';

import 'motion.dart';

/// Brings something that just arrived into view once: it fades in while it
/// grows into place from the corner it came from, yours from the composer's
/// side, a Bot's from its own. Plays only when [play] is true at first build,
/// so scrolling an item away and back does not replay it.
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
    duration: Motion.message.duration,
    value: widget.play ? 0 : 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (controller.value < 1) {
      if (Motion.still(context)) {
        controller.value = 1;
      } else if (!controller.isAnimating) {
        controller.forward();
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: widget.child,
    builder: (context, child) {
      final t = controller.value;
      if (t == 1) return child!;
      return Opacity(
        opacity: Motion.fade.transform(t),
        child: Transform.scale(
          scale: .86 + .14 * Motion.message.transform(t),
          alignment: widget.own ? Alignment.bottomRight : Alignment.bottomLeft,
          child: child,
        ),
      );
    },
  );
}
