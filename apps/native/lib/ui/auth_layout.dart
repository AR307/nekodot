import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'brand_mark.dart';
import 'design.dart';

/// Shared account-page composition; authentication remains in the feature.
class AuthLayout extends StatelessWidget {
  final String headline, description;
  final Widget child, home;
  const AuthLayout({
    super.key,
    required this.headline,
    required this.description,
    required this.child,
    required this.home,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1024;
      return Row(
        children: [
          if (wide)
            Expanded(
              child: _BrandPanel(headline: headline, description: description),
            ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      24,
                      context.tone.glass ? 80 : 106,
                      24,
                      32,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(0, constraints.maxHeight - 138),
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!wide) ...[
                                const AuthWordmark(),
                                const SizedBox(height: 32),
                              ],
                              child,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(top: 52, left: 20, child: home),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class AuthWordmark extends StatelessWidget {
  const AuthWordmark({super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const BrandMark(size: 28),
      const SizedBox(width: 10),
      Text(
        'nekodot',
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontSize: 22, fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _BrandPanel extends StatefulWidget {
  final String headline, description;
  const _BrandPanel({required this.headline, required this.description});
  @override
  State<_BrandPanel> createState() => _BrandPanelState();
}

class _BrandPanelState extends State<_BrandPanel>
    with SingleTickerProviderStateMixin {
  late final flow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 28),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      flow.stop();
      flow.value = 0;
    } else if (!flow.isAnimating) {
      flow.repeat();
    }
  }

  @override
  void dispose() {
    flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.sidebar,
        border: Border(right: BorderSide(color: tone.line)),
      ),
      child: ClipRect(
        child: Stack(
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: CustomPaint(painter: _PathsPainter(flow, tone.ink)),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [tone.sidebar, tone.sidebar.withValues(alpha: 0)],
                    stops: const [.04, .76],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(48, 64, 48, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AuthWordmark(),
                  const Spacer(),
                  Text(
                    widget.headline,
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      height: 1.4,
                      letterSpacing: -.8,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.description,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: tone.ink2, fontSize: 15, height: 1.9),
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

class _PathsPainter extends CustomPainter {
  final Animation<double> flow;
  final Color ink;
  _PathsPainter(this.flow, this.ink) : super(repaint: flow);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.max(size.width / 1000, size.height / 1000);
    canvas.translate(
      (size.width - 1000 * scale) / 2 + 240 * scale,
      (size.height - 1000 * scale) / 2 + 60 * scale,
    );
    canvas.scale(scale);
    for (final direction in [1, -1]) {
      for (var index = 0; index < 36; index++) {
        final offset = index * 5 * direction;
        final path = Path()
          ..moveTo(-(380 - offset).toDouble(), -(189 + index * 6).toDouble())
          ..cubicTo(
            -(380 - offset).toDouble(),
            -(189 + index * 6).toDouble(),
            -(312 - offset).toDouble(),
            (216 - index * 6).toDouble(),
            (152 - offset).toDouble(),
            (343 - index * 6).toDouble(),
          )
          ..cubicTo(
            (616 - offset).toDouble(),
            (470 - index * 6).toDouble(),
            (684 - offset).toDouble(),
            (875 - index * 6).toDouble(),
            (684 - offset).toDouble(),
            (875 - index * 6).toDouble(),
          );
        final phase =
            (1 - math.cos(2 * math.pi * flow.value + index * .08)) / 2;
        canvas.drawPath(
          path,
          Paint()
            ..color = ink.withValues(
              alpha: (.1 + index * .018) * (.12 + phase * .12),
            )
            ..style = PaintingStyle.stroke
            ..strokeWidth = .5 + index * .03,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PathsPainter old) => old.ink != ink || old.flow != flow;
}
