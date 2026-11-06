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
    final shadows = lifted ? tone.lift : tone.rest;
    final corners = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: corners, boxShadow: shadows),
      child: Material(
        color: color ?? tone.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: corners),
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
      decoration: BoxDecoration(
        color: tone.surface,
        border: Border.all(color: tone.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

/// A row of a menu, as the reference account menu draws them: a small
/// outlined icon, the words at body size, and grey extras at the end.
class MenuRow extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String label;
  final Widget? trailing;
  const MenuRow({
    super.key,
    this.icon,
    this.leading,
    required this.label,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final text = Theme.of(context).textTheme.bodyMedium!;
    return Row(
      children: [
        if (icon != null || leading != null) ...[
          SizedBox(
            width: 18,
            child: Center(
              child: leading ?? Icon(icon, size: 17, color: tone.ink2),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.copyWith(
              fontSize: tone.glass ? 15 : 14,
              color: tone.ink,
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          IconTheme.merge(
            data: IconThemeData(size: 16, color: tone.ink3),
            child: DefaultTextStyle.merge(
              style: TextStyle(fontSize: 13, color: tone.ink3),
              child: trailing!,
            ),
          ),
        ],
      ],
    );
  }
}

/// How wide every menu opens: never narrower than the reference menu.
const menuConstraints = BoxConstraints(minWidth: 220, maxWidth: 340);

/// One entry of a popup menu or a select, as a [MenuRow] at the menu's height.
PopupMenuItem<T> menuItem<T>(
  BuildContext context, {
  Key? key,
  required T value,
  IconData? icon,
  Widget? leading,
  required String label,
  Widget? trailing,
  bool enabled = true,
}) => PopupMenuItem<T>(
  key: key,
  value: value,
  enabled: enabled,
  height: context.tone.glass ? 44 : 36,
  padding: const EdgeInsets.symmetric(horizontal: 16),
  child: MenuRow(
    icon: icon,
    leading: leading,
    label: label,
    trailing: trailing,
  ),
);

/// The hairline between groups of a menu, inset from both edges.
const menuDivider = PopupMenuDivider(
  height: 9,
  thickness: 1,
  indent: 16,
  endIndent: 16,
);

/// A field that opens its choices as a menu like every other one: the
/// chosen words, a chevron, and on a tap the rows with a tick on the chosen.
class MenuSelect<T> extends StatelessWidget {
  final T? value;
  final List<(T, String)> options;
  final ValueChanged<T>? onChanged;
  final String? label;
  const MenuSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
  });

  /// Opens the choices under the field, exactly as wide as it.
  Future<void> open(BuildContext context) async {
    final field = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final top = field.localToGlobal(
      Offset(0, field.size.height + 4),
      ancestor: overlay,
    );
    final picked = await showMenu<T>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(top.dx, top.dy, field.size.width, 0),
        Offset.zero & overlay.size,
      ),
      constraints: BoxConstraints.tightFor(width: field.size.width),
      initialValue: value,
      items: [
        for (final (option, words) in options)
          menuItem(
            context,
            key: ValueKey('select-$option'),
            value: option,
            label: words,
            trailing: option == value ? const Icon(Icons.check) : null,
          ),
      ],
    );
    if (picked != null) onChanged?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    final chosen = options.where((o) => o.$1 == value).firstOrNull;
    final enabled = onChanged != null && options.isNotEmpty;
    return Builder(
      builder: (field) => InkWell(
        borderRadius: BorderRadius.circular(context.tone.corner),
        onTap: enabled ? () => open(field) : null,
        child: InputDecorator(
          isEmpty: chosen == null,
          decoration: InputDecoration(
            labelText: label,
            enabled: enabled,
            suffixIcon: const Icon(Icons.expand_more, size: 20),
          ),
          child: Text(
            chosen?.$2 ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// A list of choices on the menu card, under a field (suggestions).
Widget menuOptions<T extends Object>(
  BuildContext context,
  Iterable<T> options,
  AutocompleteOnSelected<T> onSelected,
  String Function(T) words,
) {
  final tone = context.tone;
  return Align(
    alignment: Alignment.topLeft,
    child: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: MenuCard(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              for (final option in options)
                InkWell(
                  onTap: () => onSelected(option),
                  child: Container(
                    height: tone.glass ? 44 : 36,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: MenuRow(label: words(option)),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
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
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 2,
          vertical: tone.glass ? 9 : 7,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? tone.ink : tone.bubble,
                border: Border.all(color: selected ? tone.ink : tone.line),
                borderRadius: BorderRadius.circular(7),
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
    minimumSize: WidgetStatePropertyAll(Size(0, glass ? 34 : 28)),
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
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text, textAlign: TextAlign.center),
      padding: const EdgeInsets.symmetric(horizontal: padding, vertical: 7),
      margin: EdgeInsets.fromLTRB(side, 0, side, tone.glass ? 76 : 60),
      duration: Duration(seconds: text.length > 24 ? 4 : 2),
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
    const corners = StadiumBorder();
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
                      shape: corners,
                      shadows: tone.rest,
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
  const SidePanel({super.key, this.child, this.width = 340});
  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    reverseDuration: const Duration(milliseconds: 180),
    value: widget.child == null ? 0 : 1,
  );
  late final curve = CurvedAnimation(
    parent: controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late Widget? shown = widget.child;

  @override
  void didUpdateWidget(SidePanel old) {
    super.didUpdateWidget(old);
    final still = MediaQuery.disableAnimationsOf(context);
    if (widget.child != null) {
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
        return SizedBox(
          width: widget.width * t,
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: widget.width,
            maxWidth: widget.width,
            child: Transform.translate(
              offset: Offset((1 - t) * 28, 0),
              child: Opacity(opacity: t, child: child),
            ),
          ),
        );
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tone.base,
          boxShadow: [
            for (final shadow in tone.lift)
              shadow.copyWith(offset: Offset(-shadow.offset.dy, 0)),
          ],
        ),
        child: shown,
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
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (context, animation, secondary) => page,
        transitionsBuilder: (context, animation, secondary, child) {
          if (MediaQuery.disableAnimationsOf(context)) return child;
          final grow = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: grow,
            child: ScaleTransition(
              alignment: Alignment.topCenter,
              scale: Tween<double>(begin: .94, end: 1).animate(grow),
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
