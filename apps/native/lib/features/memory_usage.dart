import 'package:flutter/material.dart';

import '../data/client.dart';
import '../ui/design.dart';

/// What Hermes' MemoryStore counts against its cap: the unique trimmed entries
/// joined by its native separator, measured in code points.
int nativeMemoryLength(String content) => content
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .split('\n§\n')
    .map((entry) => entry.trim())
    .where((entry) => entry.isNotEmpty)
    .toSet()
    .join('\n§\n')
    .runes
    .length;

/// Within the last tenth of the cap, Hermes may already refuse a new entry.
bool nearMemoryLimit(String content, int limit) =>
    nativeMemoryLength(content) >= limit * 0.9;

class MemoryUsage extends StatelessWidget {
  final NekodotClient client;
  final String content;
  final int limit;
  const MemoryUsage({
    super.key,
    required this.client,
    required this.content,
    required this.limit,
  });

  @override
  Widget build(BuildContext context) {
    final used = nativeMemoryLength(content);
    return Column(
      key: const ValueKey('memory-usage'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(
          value: (used / limit).clamp(0, 1).toDouble(),
          minHeight: 4,
          borderRadius: BorderRadius.circular(4),
          backgroundColor: context.tone.raised,
        ),
        const SizedBox(height: 4),
        Text(
          '$used / $limit ${client.tr('字符', 'characters')}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: nearMemoryLimit(content, limit)
                ? FontWeight.w800
                : null,
          ),
        ),
      ],
    );
  }
}
