import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'brand_mark.dart';
import 'design.dart';

class AuthFrame extends StatelessWidget {
  final bool zh;
  final Widget child;
  const AuthFrame({super.key, required this.zh, required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000;
      return Row(
        children: [
          if (wide)
            Expanded(
              child: ColoredBox(
                color: context.tone.sidebar,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ExcludeSemantics(child: _FloatingPaths()),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(48, 64, 48, 44),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              BrandMark(size: 30),
                              SizedBox(width: 10),
                              Text(
                                'nekodot',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            zh ? '一个会干活的 AI 小队，\n住在你自己的电脑里。' : 'An AI crew that gets things done.\nOn your own computer.',
                            style: const TextStyle(
                              fontSize: 38,
                              height: 1.25,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            zh
                                ? '把你的 AI 小队，带到自己的电脑上。'
                                : 'Bring your AI crew to your own computer.',
                            style: TextStyle(
                              color: context.tone.ink2,
                              fontSize: 15,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            zh
                                ? '模型随你选，也能接自己的接口'
                                : 'Choose your models. Connect your own API.',
                            style: TextStyle(
                              color: context.tone.ink2,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, panel) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 80, 24, 40),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: math.max(0, panel.maxHeight - 120),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _FloatingPaths extends StatefulWidget {
  const _FloatingPaths();
  @override
  State<_FloatingPaths> createState() => _FloatingPathsState();
}

class _FloatingPathsState extends State<_FloatingPaths>
    with SingleTickerProviderStateMixin {
  late final motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 28),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
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
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: motion,
    builder: (_, child) =>
        CustomPaint(painter: _Paths(context.tone.ink3, motion.value)),
  );
}

class _Paths extends CustomPainter {
  final Color color;
  final double phase;
  _Paths(this.color, this.phase);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 600, size.height / 800);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7
      ..color = color.withValues(alpha: .25);
    for (var direction = 0; direction < 2; direction++) {
      canvas.save();
      if (direction == 1) {
        canvas.translate(600, 800);
        canvas.rotate(math.pi);
      }
      for (var index = 0; index < 24; index++) {
        final offset = math.sin(phase * math.pi * 2 + index * .08) * 18;
        canvas.drawPath(
          Path()
            ..moveTo(-160 + index * 12, -80)
            ..cubicTo(
              380 + index * 8 + offset,
              120,
              -240 + index * 14,
              420,
              320 + index * 12,
              900,
            ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_Paths oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.color != color;
}
