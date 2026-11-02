import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:pasteboard/pasteboard.dart';

import '../data/client.dart';
import '../platform/desktop.dart';
import '../ui/design.dart';

/// Device actions never read a server clipboard or a server-local image path.
Future<void> clientCommand(
  BuildContext context,
  NekodotClient c,
  String name,
  String arg,
  List<Json> messages,
  Future<void> Function({String? path, Uint8List? bytes, bool imageOnly})
  attach,
) async {
  if (name == '/copy') {
    final count = arg.isEmpty ? 1 : int.tryParse(arg);
    final replies = messages
        .where((row) => row['author']['type'] == 'bot' && row['kind'] == 'text')
        .toList();
    if (count == null || count < 1 || count > replies.length) {
      throw RelayError(c.tr('没有对应的 Bot 回复', 'No such Bot reply'));
    }
    await Clipboard.setData(
      ClipboardData(
        text: '${replies[replies.length - count]['content']['text'] ?? ''}',
      ),
    );
    if (context.mounted) showNotice(context, c.tr('已复制回复', 'Reply copied'));
    return;
  }
  if (name == '/image') {
    var path = arg.trim();
    if (path.startsWith('"') && path.endsWith('"')) {
      path = path.substring(1, path.length - 1);
    }
    if (Platform.isAndroid && path.isNotEmpty) {
      throw RelayError(
        c.tr(
          'Android 请使用 /image 打开系统文件选择器',
          'Use /image without a path to choose an Android image',
        ),
      );
    }
    await attach(path: path.isEmpty ? null : path, imageOnly: true);
    return;
  }
  if (name == '/paste') {
    if (arg.isNotEmpty) throw RelayError('Usage: /paste');
    final image = await Pasteboard.image;
    if (image == null || image.isEmpty) {
      throw RelayError(
        c.tr('当前设备剪贴板没有可读取的图片', 'No readable image in this device’s clipboard'),
      );
    }
    final codec = await ui.instantiateImageCodec(image);
    final frame = await codec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    await attach(bytes: png!.buffer.asUint8List(), imageOnly: true);
    return;
  }
  final key = name.substring(1);
  if (c.chatDisplay.containsKey(key)) {
    if (!['', 'on', 'off', 'status'].contains(arg)) {
      throw RelayError('Usage: $name [on|off|status]');
    }
    final current = c.chatDisplay[key]!;
    final enabled = arg == 'status'
        ? current
        : arg.isEmpty
        ? !current
        : arg == 'on';
    await c.setChatDisplay(key, enabled);
    if (context.mounted) {
      showNotice(
        context,
        '$name: ${enabled ? 'on' : 'off'} · ${c.tr('当前客户端', 'this client')}',
      );
    }
    return;
  }
  if (name == '/skin') {
    if (!['', 'light', 'dark', 'auto', 'system'].contains(arg)) {
      throw RelayError(
        c.tr(
          'App 外观支持 light / dark / system；终端皮肤不应用于 Flutter。',
          'App appearance supports light / dark / system; terminal skins do not render in Flutter.',
        ),
      );
    }
    final appearance = arg.isEmpty
        ? (c.theme == 'dark' ? 'light' : 'dark')
        : arg == 'auto'
        ? 'system'
        : arg;
    await c.preferences(appearance: appearance);
    return;
  }
  if (name == '/redraw') {
    if (arg.isNotEmpty) throw RelayError('Usage: /redraw');
    await c.synchronize(c.selectedNodeId!);
    if (c.visibleConversation != null) {
      await c.loadMessages(c.visibleConversation!);
    }
    if (context.mounted) {
      showNotice(
        context,
        c.tr('界面已刷新，未重新执行任务', 'View refreshed; no task was replayed'),
      );
    }
    return;
  }
  if (name == '/quit') {
    if (arg.isNotEmpty) {
      throw RelayError(
        c.tr(
          '仅支持 /quit；不会删除会话或终止服务器任务。',
          'Use /quit without arguments. No sessions or server tasks will be deleted.',
        ),
      );
    }
    if (Platform.isWindows) {
      await DesktopHost.quit();
    } else if (Platform.isAndroid) {
      await const MethodChannel('app.nekodot/lifecycle')
          .invokeMethod<void>('background');
    }
  }
}

/// Reads this device, not the remote server's battery or Hermes' terminal UI.
class DeviceBattery extends StatefulWidget {
  final NekodotClient client;
  const DeviceBattery({super.key, required this.client});
  @override
  State<DeviceBattery> createState() => _DeviceBatteryState();
}

class _DeviceBatteryState extends State<DeviceBattery>
    with WidgetsBindingObserver {
  final battery = Battery();
  late Future<int> level;
  late final Timer refresh;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    level = battery.batteryLevel;
    refresh = Timer.periodic(const Duration(minutes: 1), (_) => read());
  }

  void read() {
    if (mounted) {
      setState(() {
        level = battery.batteryLevel;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) read();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    refresh.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<int>(
    future: level,
    builder: (context, snapshot) => Text(
      snapshot.hasError
          ? widget.client.tr('本机无可用电池', 'Device battery unavailable')
          : snapshot.hasData
          ? '${widget.client.tr('本机电量', 'Device battery')}: ${snapshot.data}%'
          : widget.client.tr('读取电量…', 'Reading battery…'),
      key: const ValueKey('device-battery'),
      style: Theme.of(context).textTheme.labelSmall,
    ),
  );
}
