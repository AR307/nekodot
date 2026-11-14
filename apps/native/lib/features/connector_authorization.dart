import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../ui/design.dart';
import 'connector_icon.dart';

String connectorStatus(NekodotClient c, String status) => switch (status) {
  'active' => c.tr('已连接', 'Connected'),
  'pending' => c.tr('等待授权', 'Awaiting authorization'),
  'failed' => c.tr('授权失败', 'Authorization failed'),
  'expired' => c.tr('授权已过期', 'Authorization expired'),
  'cancelled' => c.tr('已取消', 'Cancelled'),
  'stopped' => c.tr('已停止', 'Stopped'),
  _ => c.tr('已断开', 'Disconnected'),
};

/// Shared pending authorization UI; polls only a visible, pending flow.
class ConnectorAuthorizationView extends StatefulWidget {
  final NekodotClient client;
  final Json authorization;
  final bool stopped;
  final VoidCallback? onChanged;
  const ConnectorAuthorizationView({
    super.key,
    required this.client,
    required this.authorization,
    this.stopped = false,
    this.onChanged,
  });
  @override
  State<ConnectorAuthorizationView> createState() =>
      _ConnectorAuthorizationViewState();
}

class _ConnectorAuthorizationViewState extends State<ConnectorAuthorizationView>
    with WidgetsBindingObserver, RouteAware {
  late Json auth = widget.authorization;
  Timer? timer;
  StreamSubscription<Json>? changes;
  bool refreshing = false, cancelling = false;
  bool visible = true, foreground = true, failed = false;
  NekodotClient get c => widget.client;
  String get id => '${auth['authorizationId']}';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    changes = c.connectorChanges.stream.listen((event) {
      final updated = object(event['authorization'] ?? {});
      if (updated['authorizationId'] == id && mounted) {
        setState(() => auth = updated);
        schedule();
      }
    });
    schedule();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) nativeRoutes.subscribe(this, route);
  }

  @override
  void didUpdateWidget(ConnectorAuthorizationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.authorization != oldWidget.authorization) {
      auth = widget.authorization;
    }
    schedule();
  }

  void schedule() {
    timer?.cancel();
    if (visible &&
        foreground &&
        !cancelling &&
        !widget.stopped &&
        auth['status'] == 'pending') {
      timer = Timer(const Duration(seconds: 4), () => unawaited(refresh()));
    }
  }

  @override
  void didPushNext() {
    visible = false;
    schedule();
  }

  @override
  void didPopNext() {
    visible = true;
    unawaited(refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground && visible) {
      unawaited(refresh());
    } else {
      schedule();
    }
  }

  Future<void> refresh() async {
    if (refreshing ||
        cancelling ||
        widget.stopped ||
        auth['status'] != 'pending') {
      return;
    }
    setState(() => refreshing = true);
    try {
      final result = await c.account.request('/connectors/authorizations/$id');
      if (mounted && !cancelling && auth['status'] == 'pending') {
        setState(() {
          auth = result;
          failed = false;
        });
        if (auth['status'] != 'pending') widget.onChanged?.call();
      }
    } catch (_) {
      if (mounted && !cancelling && auth['status'] == 'pending') {
        setState(() => failed = true);
      }
    } finally {
      if (mounted) {
        setState(() => refreshing = false);
        schedule();
      }
    }
  }

  Future<void> cancel() async {
    if (cancelling) return;
    timer?.cancel();
    setState(() => cancelling = true);
    try {
      final result = await c.account.request(
        '/connectors/authorizations/$id/cancel',
        method: 'POST',
      );
      if (mounted) {
        setState(() {
          auth = result;
          failed = false;
        });
        widget.onChanged?.call();
      }
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) {
        setState(() => cancelling = false);
        schedule();
      }
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    changes?.cancel();
    nativeRoutes.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = object(auth['service']);
    final pending = !widget.stopped && auth['status'] == 'pending';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ConnectorIcon(url: service['icon'] as String?),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${service['name']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                connectorStatus(
                  c,
                  widget.stopped ? 'stopped' : '${auth['status']}',
                ),
                style: TextStyle(color: context.tone.ink2),
              ),
            ],
          ),
          if (failed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(c.tr('请求失败，请重试', 'Request failed. Try again.')),
            ),
          if (pending)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: cancelling
                        ? null
                        : () async {
                            final opened = await launchUrl(
                              Uri.parse(auth['url'] as String),
                              mode: LaunchMode.externalApplication,
                            );
                            if (!opened && mounted) {
                              setState(() => failed = true);
                            }
                          },
                    icon: const Icon(Symbols.open_in_new, size: 18),
                    label: Text(c.tr('打开授权页面', 'Open authorization')),
                  ),
                  TextButton(
                    onPressed: refreshing || cancelling ? null : refresh,
                    child: Text(c.tr('刷新', 'Refresh')),
                  ),
                  TextButton(
                    onPressed: cancelling ? null : cancel,
                    child: Text(c.tr('取消', 'Cancel')),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class ConnectorChatCard extends StatelessWidget {
  final NekodotClient client;
  final Json content;
  const ConnectorChatCard({
    super.key,
    required this.client,
    required this.content,
  });
  @override
  Widget build(BuildContext context) => ChatCard(
    child: ConnectorAuthorizationView(
      client: client,
      authorization: object(content['authorization']),
      stopped: content['stopped'] == true,
    ),
  );
}
