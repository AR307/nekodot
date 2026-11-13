import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../platform/desktop.dart';
import 'design.dart';

const _blur = 26.0;

/// The one plain ground every phone page sits on, shared so pages can fade
/// over each other and bars can blur what scrolls beneath them.
class Ambient extends StatelessWidget {
  final Widget child;
  const Ambient({super.key, required this.child});
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.tone.base,
    child: BackdropGroup(child: child),
  );
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

/// A card: a raised surface that carries its depth as a soft shadow, never a
/// hairline under it.
class Panel extends StatelessWidget {
  final Widget child;
  final double radius;

  /// Lifted cards (menus, the selected row) sit higher than resting ones.
  final bool lifted;
  final Color? color;
  const Panel({
    super.key,
    required this.child,
    this.radius = 14,
    this.lifted = false,
    this.color,
  });
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final shadows = lifted ? tone.lift : const <BoxShadow>[];
    final corners = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: ShapeDecoration(
        shadows: shadows,
        shape: RoundedSuperellipseBorder(borderRadius: corners),
      ),
      child: Material(
        color: color ?? tone.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedSuperellipseBorder(borderRadius: corners),
        child: child,
      ),
    );
  }
}

/// What a Bot puts in the chat besides words: a question, an approval, a
/// file. One hairline, no shadow, nothing nested inside.
class ChatCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const ChatCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 12),
  });
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    return Container(
      padding: padding,
      decoration: ShapeDecoration(
        color: tone.surface,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: tone.line, width: .5),
        ),
      ),
      child: child,
    );
  }
}

/// The card a menu sits on, for lists that are not popup menus (suggestions).
class MenuCard extends StatelessWidget {
  final Widget child;
  const MenuCard({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final menu = Theme.of(context).popupMenuTheme;
    return Material(
      color: menu.color,
      surfaceTintColor: Colors.transparent,
      elevation: menu.elevation ?? 6,
      shadowColor: menu.shadowColor,
      shape: menu.shape,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: menu.menuPadding ?? const EdgeInsets.symmetric(vertical: 6),
        child: child,
      ),
    );
  }
}

/// One lettered choice in a question or an approval.
class ChoiceRow extends StatelessWidget {
  final int index;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const ChoiceRow({
    super.key,
    required this.index,
    required this.label,
    this.selected = false,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final text = Theme.of(context).textTheme;
    return InkWell(
      customBorder: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 2,
          vertical: tone.glass ? 12 : 7,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: selected ? tone.ink : tone.bubble,
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(7),
                  side: BorderSide(color: selected ? tone.ink : tone.line),
                ),
              ),
              child: Text(
                String.fromCharCode(65 + index % 26),
                style: text.labelSmall?.copyWith(
                  color: selected ? tone.base : tone.ink2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: text.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

/// The small pill for a choice inside a card: approval options, answers.
ButtonStyle optionStyle(BuildContext context) {
  final glass = context.tone.glass;
  return ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(0, glass ? 48 : 32)),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: glass ? 14 : 12),
    ),
    textStyle: WidgetStatePropertyAll(
      Theme.of(context).textTheme.labelLarge?.copyWith(
        fontSize: glass ? 13.5 : 12.5,
        fontWeight: FontWeight.w700,
      ),
    ),
    tapTargetSize: glass
        ? MaterialTapTargetSize.padded
        : MaterialTapTargetSize.shrinkWrap,
  );
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
  final bool? extendBodyBehindAppBar;
  final Widget body;
  const AppPage({
    super.key,
    this.title,
    this.actions,
    this.bottom,
    this.extendBodyBehindAppBar,
    required this.body,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.tone.ground,
    extendBodyBehindAppBar: extendBodyBehindAppBar ?? false,
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

/// A brief notice: centered, as wide as its text, above the dock and composer.
void showNotice(BuildContext context, String text) {
  const padding = 14.0;
  final tone = context.tone;
  final screen = MediaQuery.sizeOf(context).width;
  final measured = TextPainter(
    text: TextSpan(
      text: text,
      style: Theme.of(context).snackBarTheme.contentTextStyle,
    ),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = math.min(
    math.min(screen - 32, 420.0),
    measured.width + padding * 2 + 2,
  );
  measured.dispose();
  final side = (screen - width) / 2;
  // A pill that rises above the bottom controls and leaves on its own: long
  // enough to read, short enough not to stay in the way.
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text, textAlign: TextAlign.center),
        padding: const EdgeInsets.symmetric(horizontal: padding, vertical: 9),
        margin: EdgeInsets.fromLTRB(side, 0, side, tone.glass ? 76 : 60),
        shape: const RoundedSuperellipseBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        duration: Duration(milliseconds: text.length > 24 ? 4000 : 2500),
      ),
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

/// Marks content laid out inside a longer page: a list in it takes its full
/// height and leaves the scrolling to that page.
class Unscrolled extends InheritedWidget {
  const Unscrolled({super.key, required super.child});
  static bool of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<Unscrolled>() != null;
  @override
  bool updateShouldNotify(Unscrolled oldWidget) => false;
}

/// A centered column of content.
class PageList extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;
  const PageList({super.key, required this.children, this.maxWidth = 560});
  @override
  Widget build(BuildContext context) => Unscrolled.of(context)
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: children,
        )
      : LayoutBuilder(
          builder: (context, constraints) {
            final inset = MediaQuery.paddingOf(context);
            final side = math.max(16.0, (constraints.maxWidth - maxWidth) / 2);
            return ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
          // Hairlines inset from the leading edge, as the rows they part.
          if (index > 0)
            Divider(
              height: 1,
              thickness: .5,
              indent: 16,
              color: context.tone.line,
            ),
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

/// One entry on a timeline: its mark on the line at the left, what happened
/// beside it.
class TimelineEntry extends StatelessWidget {
  final Widget mark, child;

  /// The last entry ends the line.
  final bool last;
  const TimelineEntry({
    super.key,
    required this.mark,
    required this.child,
    this.last = false,
  });
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 24,
          child: Column(
            children: [
              SizedBox(height: 48, child: Center(child: mark)),
              if (!last)
                Expanded(
                  child: VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: context.tone.line,
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

/// A dot that breathes beside a step that is under way.
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
      controller.stop();
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
  final double? position;
  const Segment({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.position,
  });
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final keys = options.keys.toList();
    final selected = position ?? keys.indexOf(value).toDouble();
    final still = MediaQuery.disableAnimationsOf(context);
    final fontSize = tone.glass ? 16.0 : 14.0;
    final height = math.max(
      tone.glass ? 40.0 : 32.0,
      MediaQuery.textScalerOf(context).scale(fontSize) * 1.2 + 8,
    );
    final target = math.max(height, tone.glass ? 48.0 : height);
    const corners = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.all(Radius.circular(Tone.r8)),
    );
    final thumb = RoundedSuperellipseBorder(
      borderRadius: const BorderRadius.all(Radius.circular(6)),
      side: BorderSide(color: tone.line, width: Tone.hair),
    );
    return IntrinsicWidth(
      child: SizedBox(
        height: target,
        child: Stack(
          children: [
            Positioned.fill(
              top: (target - height) / 2,
              bottom: (target - height) / 2,
              child: DecoratedBox(
                key: const ValueKey('segment-track'),
                decoration: ShapeDecoration(color: tone.hover, shape: corners),
              ),
            ),
            Positioned.fill(
              left: 2,
              right: 2,
              top: (target - height) / 2 + 2,
              bottom: (target - height) / 2 + 2,
              child: AnimatedAlign(
                duration: still || position != null
                    ? Duration.zero
                    : Motion.move.duration,
                curve: Motion.move,
                alignment: Alignment(
                  keys.length == 1 ? 0 : -1 + 2 * selected / (keys.length - 1),
                  0,
                ),
                child: FractionallySizedBox(
                  widthFactor: 1 / keys.length,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: tone.thumb,
                      shape: thumb,
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
                      child: InkWell(
                        customBorder: corners,
                        onTap: () => onChanged(key),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: tone.glass ? 48 : 36,
                          ),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: IconTheme(
                                data: IconThemeData(
                                  size: tone.glass ? 17 : 15,
                                  color: key == value ? tone.ink : tone.ink2,
                                ),
                                child: DefaultTextStyle.merge(
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        fontSize: fontSize,
                                        height: 1.2,
                                        fontWeight: key == value
                                            ? null
                                            : FontWeight.w400,
                                        color: key == value
                                            ? tone.ink
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
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A panel that slides in from the right edge, pushing the content beside it
/// aside, and slides back out when [child] becomes null. It casts its shadow
/// over that content, so the opening reads as the panel rising above it.
/// Bypass the size animator for reduced motion: a zero-duration AnimatedSize
/// can notify its render object from inside layout when the child changes size.
class SizeMotion extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final Alignment alignment;
  final Curve curve;
  const SizeMotion({
    super.key,
    required this.child,
    required this.duration,
    this.alignment = Alignment.center,
    this.curve = Curves.easeOutCubic,
  });
  @override
  Widget build(BuildContext context) => MediaQuery.disableAnimationsOf(context)
      ? child
      : AnimatedSize(
          duration: duration,
          alignment: alignment,
          curve: curve,
          child: child,
        );
}

class SidePanel extends StatefulWidget {
  final Widget? child;
  final double width;

  /// Whether it lies over the page rather than beside it: it then casts a
  /// shadow and settles as a drawer does.
  final bool floating;
  const SidePanel({
    super.key,
    this.child,
    this.width = 340,
    this.floating = false,
  });
  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: Motion.side.duration,
    reverseDuration: Motion.sideLeave,
    value: widget.child == null ? 0 : 1,
  );
  late final curve = CurvedAnimation(
    parent: controller,
    curve: Motion.side,
    reverseCurve: const FlippedCurve(Motion.leave),
  );
  late Widget? shown = widget.child;
  late double shownWidth = widget.width;
  late bool shownFloating = widget.floating;

  @override
  void didUpdateWidget(SidePanel old) {
    super.didUpdateWidget(old);
    final still = MediaQuery.disableAnimationsOf(context);
    if (widget.child != null) {
      shownWidth = widget.width;
      shownFloating = widget.floating;
      final spring = widget.floating ? Motion.drawer : Motion.side;
      curve.curve = spring;
      controller.duration = spring.duration;
      controller.reverseDuration = widget.floating
          ? Motion.drawerLeave
          : Motion.sideLeave;
      final opening = shown == null;
      shown = widget.child;
      if (still) {
        controller.value = 1;
      } else if (opening) {
        // Build the panel at zero width first, so its first (costly) frame
        // is not the one the slide starts on.
        afterFirstFrames(() {
          if (mounted && widget.child != null) controller.forward();
        });
      } else {
        controller.forward();
      }
    } else if (still) {
      controller.value = 0;
      shown = null;
    } else {
      // Keep the last panel on screen while it leaves.
      controller.reverse().whenComplete(() {
        if (mounted && widget.child == null) setState(() => shown = null);
      });
    }
  }

  @override
  void dispose() {
    curve.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) {
        final t = curve.value;
        if (shown == null) return const SizedBox.shrink();
        // The room it takes never passes its width; only the panel itself
        // overshoots as it settles.
        return SizedBox(
          width: shownWidth * t.clamp(0.0, 1.0),
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: shownWidth,
            maxWidth: shownWidth,
            child: Transform.translate(
              offset: Offset((1 - t) * 40, 0),
              child: Opacity(
                opacity: controller.status == AnimationStatus.reverse
                    ? t.clamp(0.0, 1.0)
                    : Motion.fade.transform(controller.value),
                child: child,
              ),
            ),
          ),
        );
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tone.base,
          border: Border(
            left: BorderSide(color: tone.line, width: Tone.hair),
          ),
          boxShadow: shownFloating ? tone.lift : null,
        ),
        child: TickerMode(
          enabled: widget.child != null,
          child: shown ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Opens a page that grows out of the bar above, for details that pop up
/// from where they were asked for rather than slide in as a new step.
Future<T?> popPage<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(_PopRoute(page));

class _PopRoute<T> extends PageRouteBuilder<T> {
  _PopRoute(Widget page)
    : super(
        transitionDuration: Motion.pop.duration,
        reverseTransitionDuration: Motion.popLeave,
        pageBuilder: (context, animation, secondary) => page,
        transitionsBuilder: (context, animation, secondary, child) {
          if (Motion.still(context)) return child;
          return FadeTransition(
            opacity: Motion.fadeIn(animation),
            child: ScaleTransition(
              alignment: Alignment.topCenter,
              scale: Tween<double>(
                begin: .9,
                end: 1,
              ).animate(Motion.spring(animation, Motion.pop)),
              child: child,
            ),
          );
        },
      );

  /// Holds at the start until the page's first (costly) frame is on screen,
  /// so that frame is not the one the motion starts on.
  @override
  TickerFuture didPush() {
    final pushed = super.didPush();
    controller!.stop();
    afterFirstFrames(() {
      if (isActive && controller!.status == AnimationStatus.forward) {
        controller!.forward();
      }
    });
    return pushed;
  }
}

/// Runs [start] once the next two frames are drawn. A costly first build
/// holds up the frame after it too, which then carries a stale time stamp;
/// a motion started there would jump straight to its end.
void afterFirstFrames(VoidCallback start) {
  final binding = WidgetsBinding.instance;
  binding.addPostFrameCallback((_) {
    binding.addPostFrameCallback((_) => start());
    binding.scheduleFrame();
  });
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

/// Short facts side by side, parted by a hairline rather than a "·", whose
/// height and baseline differ from font to font.
class MetaText extends StatelessWidget {
  final List<String> parts;
  final TextStyle? style;
  final int maxLines;
  final TextAlign textAlign;
  const MetaText(
    this.parts, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.textAlign = TextAlign.start,
  });
  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final part in parts)
        if (part.trim().isNotEmpty) part,
    ];
    final size = (style ?? DefaultTextStyle.of(context).style).fontSize ?? 13;
    return Text.rich(
      TextSpan(
        children: [
          for (final (index, part) in shown.indexed) ...[
            if (index > 0)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  width: 1 / MediaQuery.devicePixelRatioOf(context),
                  height: size * .8,
                  margin: const EdgeInsets.symmetric(horizontal: 7),
                  color: context.tone.ink3.withValues(alpha: .6),
                ),
              ),
            TextSpan(text: part),
          ],
        ],
      ),
      style: style,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
    );
  }
}
