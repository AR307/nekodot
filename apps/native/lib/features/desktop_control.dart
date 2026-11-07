import 'package:flutter/material.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../local/runtime.dart';
import '../ui/design.dart';

/// Whether this Bot may drive the real mouse and keyboard of the computer its node runs on.
/// Only desktop-hosted nodes have one; servers keep their independent Bot screens instead.
class DesktopControlTile extends StatefulWidget {
  final NekodotClient client;
  final String botId;
  const DesktopControlTile({
    super.key,
    required this.client,
    required this.botId,
  });
  @override
  State<DesktopControlTile> createState() => _DesktopControlTileState();
}

class _DesktopControlTileState extends State<DesktopControlTile> {
  NekodotClient get c => widget.client;
  bool? enabled;
  bool busy = false;
  String error = '';
  Json status = {};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load([bool? value]) async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final result = await c.rpc('bots.desktopControl', {
        'botId': widget.botId,
        'enabled': ?value,
      });
      final capabilities = await c.rpc('desktop.status', {});
      if (!mounted) return;
      setState(() {
        enabled = result['enabled'] == true;
        status = object(capabilities['desktopControl'] ?? {});
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String get readiness {
    if (status['installed'] != true) {
      return c.tr('未安装桌面驱动', 'Desktop driver not installed');
    }
    if (status['ready'] == true) return c.tr('可用', 'Ready');
    if (status['canGrant'] == true) {
      return c.tr(
        '需要在这台电脑上授予辅助功能与屏幕录制权限',
        'Needs Accessibility and Screen Recording on that computer',
      );
    }
    final detail = '${status['detail'] ?? ''}';
    return detail.isEmpty ? c.tr('暂不可用', 'Unavailable') : detail;
  }

  @override
  Widget build(BuildContext context) {
    final local = localRuntime;
    final here = local != null && local.nodeId == c.selectedNodeId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const ValueKey('bot-desktop-control'),
          secondary: const Icon(Icons.mouse_outlined),
          title: Text(c.tr('操作这台电脑', 'Operate this computer')),
          subtitle: Text(
            '${c.tr('用鼠标和键盘操作运行它的电脑上你正在使用的桌面，按审批设置确认，可随时停止。', 'Uses the mouse and keyboard on the desktop you are using on its computer, following approval settings; stop at any time.')}\n$readiness',
          ),
          isThreeLine: true,
          value: enabled ?? false,
          onChanged: enabled == null || busy ? null : (value) => load(value),
        ),
        if (here && status['canGrant'] == true && status['ready'] != true)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      final result = await local.grantDesktopControl();
                      if (mounted) setState(() => error = result);
                      await load();
                    },
              child: Text(c.tr('打开系统授权', 'Open system permission')),
            ),
          ),
        ErrorNotice(error),
      ],
    );
  }
}
