import 'dart:async';

import 'package:flutter/material.dart';

import '../data/client.dart';
import 'design.dart';

/// One non-modal notice per interruption, above (not instead of) the workspace.
class ConnectionNotice extends StatefulWidget {
  final NekodotClient client;
  final Widget child;
  const ConnectionNotice({
    super.key,
    required this.client,
    required this.child,
  });
  @override
  State<ConnectionNotice> createState() => _ConnectionNoticeState();
}

class _ConnectionNoticeState extends State<ConnectionNotice> {
  Timer? delay, hide;
  bool shown = false, visible = false;
  NekodotClient get c => widget.client;
  bool get disconnected =>
      !c.connection.ready ||
      (c.selectedNodeId != null && !c.node.online) ||
      c.deliveries.items.any(
        (i) => i['state'] == 'queued' && c.nodes[i['nodeId']]?.online != true,
      );
  @override
  void initState() {
    super.initState();
    c.addListener(changed);
    c.deliveries.addListener(changed);
    changed();
  }

  void changed() {
    if (c.account.token == null || !disconnected) {
      delay?.cancel();
      delay = null;
      hide?.cancel();
      shown = false;
      if (visible && mounted) setState(() => visible = false);
      return;
    }
    if (visible && mounted) setState(() {});
    if (shown || delay != null) return;
    delay = Timer(const Duration(seconds: 3), () {
      delay = null;
      if (!mounted || !disconnected || c.account.token == null) return;
      setState(() {
        shown = true;
        visible = true;
      });
      hide = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => visible = false);
      });
    });
  }

  @override
  void dispose() {
    delay?.cancel();
    hide?.cancel();
    c.removeListener(changed);
    c.deliveries.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = c.deliveries.items.any(
      (i) => i['action'] != true && ['queued', 'sending'].contains(i['state']),
    );
    return Stack(
      children: [
        widget.child,
        if (visible)
          Positioned(
            right: 16,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 100,
            child: IgnorePointer(
              child: Material(
                elevation: 2,
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                color: context.tone.menu,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width - 60,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Symbols.cloud_off,
                          size: 16,
                          color: context.tone.ink3,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            pending
                                ? c.tr(
                                    '无法连接，内容会在重连后自动发出',
                                    'Unable to connect. Your messages will send after reconnecting.',
                                  )
                                : c.tr('无法连接', 'Unable to connect'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
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

class ContentRefreshScope extends InheritedNotifier<ValueNotifier<int>> {
  const ContentRefreshScope({
    super.key,
    required super.notifier,
    required super.child,
  });
  static int of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ContentRefreshScope>()
          ?.notifier
          ?.value ??
      0;
}
