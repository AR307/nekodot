import 'package:flutter/material.dart';

import '../data/json.dart';
import '../ui/design.dart';

/// One quiet, non-interactive line directly above the composer.
class ThinkingRow extends StatelessWidget {
  final Json? bot;
  final String line;
  final bool moving;
  const ThinkingRow({
    super.key,
    this.bot,
    required this.line,
    required this.moving,
  });

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: context.tone.glass ? 14 : 13,
      color: context.tone.ink2,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          if (bot != null)
            CatAvatar.of(bot!, size: 24)
          else
            const CatAvatar(size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: moving
                ? ShiningText(text: line, style: style)
                : Text(
                    line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
          ),
        ],
      ),
    );
  }
}
