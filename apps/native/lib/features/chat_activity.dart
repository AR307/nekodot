import 'package:flutter/material.dart';

import '../data/json.dart';
import '../ui/design.dart';

/// One quiet line directly above the composer. It opens something only while
/// the Dot is waiting for you, and keeps its height either way.
class ThinkingRow extends StatelessWidget {
  final Json? bot;
  final String line;
  final bool moving;
  final VoidCallback? onTap;
  const ThinkingRow({
    super.key,
    this.bot,
    required this.line,
    required this.moving,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: tone.glass ? 14 : 13,
      color: onTap == null ? tone.ink2 : tone.ink,
    );
    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: tone.glass ? 48 : 40),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
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
            if (onTap != null) ...[
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 16, color: tone.ink3),
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        child: row,
      ),
    );
  }
}
