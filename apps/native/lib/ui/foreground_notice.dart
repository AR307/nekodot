import 'dart:async';

import 'package:flutter/material.dart';

import '../data/client.dart';
import '../data/json.dart';
import 'design.dart';

/// One non-blocking foreground message; native notifications own background delivery.
class ForegroundNotice extends StatefulWidget {
  final NekodotClient client;
  final Widget child;
  const ForegroundNotice({
    super.key,
    required this.client,
    required this.child,
  });
  @override
  State<ForegroundNotice> createState() => _ForegroundNoticeState();
}

class _ForegroundNoticeState extends State<ForegroundNotice> {
  Json? shown;
  Timer? timer;
  int priority(Json value) =>
      const {'approval', 'question', 'failed'}.contains(value['kind']) ? 1 : 0;
  @override
  void initState() {
    super.initState();
    widget.client.foregroundNotice.addListener(receive);
  }

  void receive() {
    final next = widget.client.foregroundNotice.value;
    if (next != null &&
        shown != null &&
        next['conversationId'] != shown!['conversationId'] &&
        priority(next) < priority(shown!)) {
      return;
    }
    timer?.cancel();
    setState(() => shown = next);
    if (next != null) {
      timer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => shown = null);
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.client.foregroundNotice.removeListener(receive);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final signal = shown;
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: MediaQuery.paddingOf(context).top + 52,
          left: 16,
          right: 16,
          child: Align(
            alignment: Alignment.topRight,
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              child: signal == null
                  ? const SizedBox.shrink()
                  : ConstrainedBox(
                      key: ValueKey(
                        '${signal['nodeId']}:${signal['conversationId']}',
                      ),
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Panel(
                        lifted: true,
                        child: InkWell(
                          key: const ValueKey('foreground-notice'),
                          onTap: () {
                            widget.client.openNotification(signal);
                            timer?.cancel();
                            setState(() => shown = null);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(switch (signal['kind']) {
                                  'approval' => Icons.shield_outlined,
                                  'question' => Icons.help_outline,
                                  'failed' => Icons.error_outline,
                                  _ => Icons.chat_bubble_outline,
                                }, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${signal['displayName']}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${signal['preview']}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
