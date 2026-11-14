import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'design.dart';

/// nekodot's own mark: a cat peeking over an edge, its eyes cut through. It
/// spans the width of a square of [size], in [color] or the ink of the theme.
class BrandMark extends StatelessWidget {
  final double size;
  final Color? color;
  const BrandMark({super.key, required this.size, this.color});

  // The outline, then the two eyes; the same drawing as the app's icon.
  static const _drawing =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="9 20 82 55">'
      '<path fill-rule="evenodd" d="'
      'M10.80 66.03L18.35 28.94A4.00 4.00 0 0 1 24.73 26.58L34.19 33.97A6.93 6.93 0 0 0 40.16 35.23A40.00 40.00 0 0 1 59.84 35.23A6.93 6.93 0 0 0 65.81 33.97L75.27 26.58A4.00 4.00 0 0 1 81.65 28.94L89.20 66.03A40.00 40.00 0 0 1 90.00 74.00L10.00 74.00A40.00 40.00 0 0 1 10.80 66.03Z'
      'M29.7 62a5.8 5.8 0 1 0 11.6 0a5.8 5.8 0 1 0 -11.6 0Z'
      'M58.7 62a5.8 5.8 0 1 0 11.6 0a5.8 5.8 0 1 0 -11.6 0Z'
      '"/></svg>';

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: SvgPicture.string(
      _drawing,
      colorFilter: ColorFilter.mode(color ?? context.tone.ink, BlendMode.srcIn),
      excludeFromSemantics: true,
    ),
  );
}
