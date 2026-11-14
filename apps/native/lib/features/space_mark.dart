import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/spaces.dart';
import '../ui/design.dart';

/// A space's own mark, a rounded square: the icon its Dot drew for it. A
/// space published before Dots drew icons, or one whose drawing cannot be
/// drawn, shows the plain mark of a space.
class SpaceMark extends StatelessWidget {
  final Space? space;
  final double size;
  const SpaceMark({super.key, required this.space, required this.size});

  @override
  Widget build(BuildContext context) {
    final tone = context.tone, icon = space?.icon;
    final plain = ColoredBox(
      color: tone.bubble,
      child: Center(
        child: Icon(
          Symbols.space_dashboard,
          size: size * .56,
          color: tone.ink2,
        ),
      ),
    );
    return SizedBox.square(
      dimension: size,
      child: ClipPath(
        clipper: ShapeBorderClipper(
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(size * .28),
          ),
        ),
        child: icon == null
            ? plain
            : SvgPicture.string(
                icon,
                key: const ValueKey('space-mark-drawn'),
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholderBuilder: (_) => ColoredBox(color: tone.bubble),
                errorBuilder: (_, _, _) => plain,
              ),
      ),
    );
  }
}
