import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../platform/desktop.dart';
import 'design.dart';

const _blur = 26.0;

/// The one backdrop every phone page floats over. Soft neutral orbs give the
/// glass something to refract; it stays still so content carries the motion.
class Ambient extends StatelessWidget {
  final Widget child;
  const Ambient({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      RepaintBoundary(
        child: CustomPaint(
          painter: _OrbPainter(context.tone),
          size: Size.infinite,
        ),
      ),
      BackdropGroup(child: child),
    ],
  );
}

class _OrbPainter extends CustomPainter {
  final Tone tone;
  _OrbPainter(this.tone);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = tone.base);
    final unit = math.max(size.width, size.height);
    void orb(double x, double y, double radius, Color color) {
      final center = Offset(size.width * x, size.height * y);
      canvas.drawCircle(
        center,
        unit * radius,
        Paint()
          ..shader = ui.Gradient.radial(center, unit * radius, [
            color,
            color.withValues(alpha: 0),
          ]),
      );
    }

    orb(.08, .02, .62, tone.orbs[0]);
    orb(.96, .78, .58, tone.orbs[1]);
    orb(.74, .12, .34, tone.orbs[2]);
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.tone != tone;
}

/// The frosted strip behind a phone page's bar; content scrolls beneath it.
class Frost extends StatelessWidget {
  const Frost({super.key});
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    return ClipRect(
      child: BackdropFilter.grouped(
        filter: ui.ImageFilter.blur(sigmaX: _blur, sigmaY: _blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tone.bar,
            border: Border(bottom: BorderSide(color: tone.line)),
          ),
        ),
      ),
    );
  }
}

/// A card: flat with one hairline on the desktop, frosted on the phone.
class Panel extends StatelessWidget {
  final Widget child;
  final double radius;
  const Panel({super.key, required this.child, this.radius = 12});
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    if (tone.glass) {
      final corners = BorderRadius.circular(radius + 2);
      return ClipRSuperellipse(
        borderRadius: corners,
        child: BackdropFilter.grouped(
          filter: ui.ImageFilter.blur(sigmaX: _blur, sigmaY: _blur),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [tone.fillTop, tone.fillBottom],
              ),
              shape: RoundedSuperellipseBorder(
                borderRadius: corners,
                side: BorderSide(color: tone.line),
              ),
            ),
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      );
    }
    return Material(
      color: tone.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: tone.line),
      ),
      child: child,
    );
  }
}

class IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  const IconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });
  @override
  Widget build(BuildContext context) =>
      IconButton(tooltip: tooltip, onPressed: onPressed, icon: Icon(icon));
}

/// Page shell: plain background, small bar, quiet icon actions.
class AppPage extends StatelessWidget {
  final String? title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Widget body;
  const AppPage({
    super.key,
    this.title,
    this.actions,
    this.bottom,
    required this.body,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    extendBodyBehindAppBar: context.tone.glass,
    appBar: AppBar(
      flexibleSpace: context.tone.glass ? const Frost() : const WindowDrag(),
      title: title == null ? null : Text(title!),
      actions: [
        ...?actions,
        const SizedBox(width: 8),
        SizedBox(width: WindowChrome.reserved(context)),
      ],
      bottom: bottom,
    ),
    body: body,
  );
}

/// A field with its label above it, always visible and never inside the box.
class LabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  const LabeledField({super.key, required this.label, required this.child});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(label, style: Theme.of(context).textTheme.titleSmall),
      ),
      child,
    ],
  );
}

/// A centered column of content.
class PageList extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;
  const PageList({super.key, required this.children, this.maxWidth = 560});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final inset = MediaQuery.paddingOf(context);
      final side = math.max(16.0, (constraints.maxWidth - maxWidth) / 2);
      return ListView(
        padding: EdgeInsets.fromLTRB(
          side,
          inset.top + 12,
          side,
          inset.bottom + 28,
        ),
        children: children,
      );
    },
  );
}

/// Related rows sharing one card, separated by hairlines.
class PanelGroup extends StatelessWidget {
  final List<Widget> children;
  const PanelGroup({super.key, required this.children});
  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, child) in children.indexed) ...[
          if (index > 0) const Divider(height: 1),
          child,
        ],
      ],
    ),
  );
}

/// A quiet label above a group.
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 18, 0, 6),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleSmall),
        ),
        ?trailing,
      ],
    ),
  );
}

/// State without words: solid is on, a hollow ring is off.
class StatusDot extends StatelessWidget {
  final bool on;
  final double size;
  final Color? color;
  const StatusDot({super.key, this.on = true, this.size = 8, this.color});
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? color ?? tone.ink : null,
        border: on ? null : Border.all(color: tone.ink3, width: 1.5),
      ),
    );
  }
}

/// A dot that breathes while something is under way.
class Breathing extends StatefulWidget {
  final double size;
  const Breathing({super.key, this.size = 10});
  @override
  State<Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<Breathing>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.value = 1;
    } else if (!controller.isAnimating) {
      controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(
      begin: .25,
      end: 1,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut)),
    child: StatusDot(size: widget.size),
  );
}

/// Relay progress: one dot per turn.
class ChainDots extends StatelessWidget {
  final int count, max;
  const ChainDots({super.key, required this.count, required this.max});
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$count / $max',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < max; index++)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: StatusDot(size: 6, on: index < count),
          ),
      ],
    ),
  );
}

/// Sliding pill selector. The thumb is the only thing that moves.
class Segment<T> extends StatelessWidget {
  final T value;
  final Map<T, Widget> options;
  final ValueChanged<T> onChanged;
  const Segment({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final keys = options.keys.toList();
    final selected = keys.indexOf(value);
    final still = MediaQuery.disableAnimationsOf(context);
    final corners = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tone.corner - 1),
    );
    return Container(
      height: tone.glass ? 36 : 28,
      padding: const EdgeInsets.all(2),
      decoration: ShapeDecoration(color: tone.raised, shape: corners),
      child: IntrinsicWidth(
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedAlign(
                duration: still
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment(
                  keys.length == 1 ? 0 : -1 + 2 * selected / (keys.length - 1),
                  0,
                ),
                child: FractionallySizedBox(
                  widthFactor: 1 / keys.length,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: tone.ink,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(tone.corner - 2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (final key in keys)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: key == value,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(key),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: IconTheme(
                              data: IconThemeData(
                                size: tone.glass ? 18 : 15,
                                color: key == value ? tone.base : tone.ink2,
                              ),
                              child: DefaultTextStyle.merge(
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: key == value
                                          ? tone.base
                                          : tone.ink2,
                                    ),
                                child: options[key]!,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Reports a child's height, so a list can scroll under a floating composer.
class MeasureHeight extends SingleChildRenderObjectWidget {
  final ValueChanged<double> onChange;
  const MeasureHeight({super.key, required this.onChange, super.child});
  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderMeasureHeight(onChange);
  @override
  void updateRenderObject(
    BuildContext context,
    RenderMeasureHeight renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class RenderMeasureHeight extends RenderProxyBox {
  ValueChanged<double> onChange;
  double? last;
  RenderMeasureHeight(this.onChange);
  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height != last) {
      last = height;
      WidgetsBinding.instance.addPostFrameCallback((_) => onChange(height));
    }
  }
}
