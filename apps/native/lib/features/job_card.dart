import 'dart:async';

import 'package:flutter/material.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../ui/design.dart';

/// How long, as a clock reads it: 0:37, 1:07, 1:02:03.
String jobClock(num seconds) {
  final total = seconds.round().clamp(0, 1 << 31);
  final hours = total ~/ 3600, minutes = total % 3600 ~/ 60, rest = total % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${two(minutes)}:${two(rest)}'
      : '$minutes:${two(rest)}';
}

/// A long job the Dot runs in the background, as its progress line shows it:
/// how far, how fast and how long is left while it runs, how it ended after.
class JobCard extends StatefulWidget {
  final NekodotClient client;
  final String messageId;
  final Json content;
  const JobCard({
    super.key,
    required this.client,
    required this.messageId,
    required this.content,
  });
  @override
  State<JobCard> createState() => _JobCardState();
}

class _JobCardState extends State<JobCard> {
  NekodotClient get c => widget.client;

  /// Stopping takes a second tap, so a slip never ends hours of work.
  bool arming = false, busy = false;
  String error = '';
  Timer? disarm;

  @override
  void dispose() {
    disarm?.cancel();
    super.dispose();
  }

  Future<void> stop() async {
    disarm?.cancel();
    if (!arming) {
      setState(() => arming = true);
      disarm = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => arming = false);
      });
      return;
    }
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await c.rpc('jobs.stop', {'messageId': widget.messageId});
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          arming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final text = Theme.of(context).textTheme;
    final body = widget.content;
    final label = '${body['label'] ?? ''}';
    final percent = (body['percent'] as num?)?.toDouble();
    final done = body['done'] as String?, total = body['total'] as String?;
    final count = done == null
        ? null
        : total == null
        ? done
        : '$done / $total';
    const numbers = [FontFeature.tabularFigures()];
    final small = text.bodySmall?.copyWith(
      color: tone.ink2,
      fontFeatures: numbers,
    );
    if (body['state'] != 'running') {
      // Ended: one line, like an answered question.
      final (icon, word, color) = switch (body['state']) {
        'done' => (Symbols.check, c.tr('已完成', 'Done'), tone.ink3),
        'failed' => (Symbols.error, c.tr('失败', 'Failed'), tone.danger),
        _ => (Symbols.remove, c.tr('已停止', 'Stopped'), tone.ink3),
      };
      final elapsed = body['elapsedSeconds'] as num?;
      return Padding(
        key: ValueKey('job-ended-${widget.messageId}'),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(label, style: text.bodyMedium),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(word, style: text.bodySmall?.copyWith(color: color)),
              ],
            ),
            if (count != null) Text(count, style: small),
            if (elapsed != null)
              Text(
                c.tr('用时 ${jobClock(elapsed)}', 'took ${jobClock(elapsed)}'),
                style: small,
              ),
            if (body['state'] == 'failed' && body['exitCode'] != null)
              Text(
                c.tr(
                  '退出码 ${body['exitCode']}',
                  'exit code ${body['exitCode']}',
                ),
                style: small,
              ),
          ],
        ),
      );
    }
    final eta = body['etaSeconds'] as num?, rate = body['rate'] as String?;
    final still = MediaQuery.disableAnimationsOf(context);
    Widget bar(double? value) => LinearProgressIndicator(
      value: value,
      minHeight: 4,
      color: tone.ink,
      backgroundColor: tone.raised,
      semanticsLabel: label,
      semanticsValue: percent == null ? null : '${percent.floor()}%',
    );
    return ChatCard(
      key: ValueKey('job-${widget.messageId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Symbols.terminal, size: 16, color: tone.ink2),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (percent != null)
                Text(
                  '${percent.floor()}%',
                  style: text.bodyMedium?.copyWith(fontFeatures: numbers),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRSuperellipse(
            borderRadius: BorderRadius.circular(2),
            // A job that prints no total moves without saying how far it is.
            child: percent == null
                ? bar(still ? 0 : null)
                : TweenAnimationBuilder<double>(
                    tween: Tween(end: percent / 100),
                    duration: still
                        ? Duration.zero
                        : const Duration(milliseconds: 700),
                    curve: Curves.easeOutExpo,
                    builder: (context, value, _) => bar(value),
                  ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 14,
                  runSpacing: 2,
                  children: [
                    if (count != null) Text(count, style: small),
                    if (rate != null) Text(rate, style: small),
                    if (eta != null)
                      Text(
                        c.tr('剩余 ${jobClock(eta)}', '${jobClock(eta)} left'),
                        key: ValueKey('job-eta-${widget.messageId}'),
                        style: small,
                      ),
                  ],
                ),
              ),
              TextButton(
                key: ValueKey('job-stop-${widget.messageId}'),
                onPressed: busy || !c.online ? null : stop,
                style: TextButton.styleFrom(
                  foregroundColor: arming ? tone.danger : tone.ink2,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  arming ? c.tr('确认停止', 'Confirm stop') : c.tr('停止', 'Stop'),
                ),
              ),
            ],
          ),
          ErrorNotice(error),
        ],
      ),
    );
  }
}
