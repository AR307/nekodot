import 'package:flutter/material.dart';

class LoadingTextScope extends InheritedWidget {
  final String label;
  const LoadingTextScope({
    super.key,
    required this.label,
    required super.child,
  });
  @override
  bool updateShouldNotify(LoadingTextScope oldWidget) =>
      label != oldWidget.label;
}

/// The same two-second, 110-degree text sweep as the React component.
class ShiningText extends StatefulWidget {
  final String? text;
  final TextStyle? style;
  const ShiningText({super.key, this.text, this.style});

  @override
  State<ShiningText> createState() => _ShiningTextState();
}

class _ShiningTextState extends State<ShiningText>
    with SingleTickerProviderStateMixin {
  late final motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.highContrastOf(context)) {
      motion.stop();
    } else if (!motion.isAnimating) {
      motion.repeat();
    }
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style
        .merge(widget.style)
        .copyWith(fontWeight: FontWeight.w400);
    final label =
        widget.text ??
        context.dependOnInheritedWidgetOfExactType<LoadingTextScope>()?.label ??
        '加载中…';
    final text = Text(
      label,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.highContrastOf(context)) {
      return text;
    }
    final base = (style.color?.computeLuminance() ?? 0) > .5
        ? const Color(0xFFA3A3A3)
        : const Color(0xFF404040);
    return AnimatedBuilder(
      animation: motion,
      child: text,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) {
          final offset = bounds.width * (2 - 4 * motion.value);
          return LinearGradient(
            begin: const Alignment(-1, -.36),
            end: const Alignment(1, .36),
            colors: [base, base, Colors.white, base, base],
            stops: const [0, .35, .5, .75, 1],
          ).createShader(
            Rect.fromLTWH(offset, 0, bounds.width * 2, bounds.height),
          );
        },
        child: child,
      ),
    );
  }
}
