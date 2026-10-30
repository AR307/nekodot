import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/client.dart';
import '../ui/design.dart';
import 'bridge/api.dart';
import 'bridge/frb_generated.dart';

class ScreenPage extends StatefulWidget {
  final NekodotClient client;
  final Json bot;
  final List<Json> members;
  const ScreenPage({
    super.key,
    required this.client,
    required this.bot,
    this.members = const [],
  });
  @override
  State<ScreenPage> createState() => _ScreenPageState();
}

class _ScreenPageState extends State<ScreenPage> with WidgetsBindingObserver {
  late Json bot = widget.bot;
  Json? status;
  String? session, viewer;
  StreamSubscription<ScreenFrame>? subscription;
  Timer? poll, retry;
  ui.Image? image;
  String error = '';
  bool connected = false, active = true, busy = false;
  static Future<void>? bridgeInitialization;
  int attempts = 0, buttons = 0;
  final keyboard = TextEditingController(), focus = FocusNode();
  NekodotClient get c => widget.client;
  bool get own =>
      active &&
      connected &&
      c.online &&
      status?['holder'] == 'human' &&
      status?['controllerSessionId'] == session;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
    poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (active) refresh();
    });
  }

  Future<void> refresh() async {
    try {
      final value = await c.rpc('screen.status', {'botId': bot['botId']});
      if (!mounted) return;
      setState(() => status = value);
      if (value['running'] == true &&
          viewer == null &&
          active &&
          retry == null) {
        await connect();
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> connect() async {
    retry?.cancel();
    retry = null;
    if (!mounted || !active || busy || viewer != null) return;
    busy = true;
    try {
      await (bridgeInitialization ??= RustLib.init());
      final ticket = await c.request(
        '/tunnels',
        method: 'POST',
        body: {
          'nodeId': c.selectedNodeId,
          'botId': bot['botId'],
          'kind': 'vnc',
          if (session != null) 'sessionId': session,
        },
      );
      if (!mounted || !active) return;
      session = ticket['sessionId'] as String;
      viewer = uid();
      final identity = viewer!;
      subscription =
          watchScreen(
            id: identity,
            url: c.wsUrl('/ws/tunnel', {
              'ticket': ticket['ticket'] as String,
            }).toString(),
          ).listen(
            (frame) {
              if (!mounted || identity != viewer) return;
              if (frame.closeCode != 0) {
                disconnected(
                  frame.detail,
                  retryConnection: ![
                    1000,
                    4401,
                    4403,
                  ].contains(frame.closeCode),
                );
                return;
              }
              ui.decodeImageFromPixels(
                frame.pixels,
                frame.width,
                frame.height,
                ui.PixelFormat.bgra8888,
                (value) {
                  if (!mounted || identity != viewer) {
                    value.dispose();
                    return;
                  }
                  final previous = image;
                  setState(() {
                    image = value;
                    connected = true;
                    error = '';
                    attempts = 0;
                  });
                  previous?.dispose();
                },
              );
            },
            onError: (Object e) {
              if (viewer == identity) disconnected('$e');
            },
            onDone: () {
              if (viewer == identity) {
                disconnected(c.tr('屏幕连接已关闭', 'Screen connection closed'));
              }
            },
          );
    } on RelayError catch (e) {
      if (e.status == 409) session = null;
      disconnected(e.message);
    } catch (e) {
      disconnected('$e');
    } finally {
      busy = false;
    }
  }

  void disconnected(String reason, {bool retryConnection = true}) {
    if (!mounted) return;
    subscription?.cancel();
    subscription = null;
    viewer = null;
    setState(() {
      connected = false;
      error = reason;
    });
    retry?.cancel();
    if (active && retryConnection) {
      retry = Timer(Duration(seconds: (1 << attempts++).clamp(1, 30)), () {
        retry = null;
        connect();
      });
    }
  }

  void input(
    String kind, {
    int x = 0,
    int y = 0,
    int mask = 0,
    int key = 0,
    bool down = false,
    String text = '',
  }) {
    if (!own || viewer == null) return;
    screenInput(
      id: viewer!,
      input: ScreenInput(
        kind: kind,
        x: x,
        y: y,
        buttons: mask,
        key: key,
        down: down,
        text: text,
      ),
    );
  }

  void disconnect({required bool intentional}) {
    retry?.cancel();
    retry = null;
    if (viewer != null) {
      screenInput(
        id: viewer!,
        input: ScreenInput(
          kind: intentional ? 'close' : 'pause',
          x: 0,
          y: 0,
          buttons: 0,
          key: 0,
          down: false,
          text: '',
        ),
      );
    }
    viewer = null;
    connected = false;
    subscription?.cancel();
    subscription = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      active = true;
      refresh();
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      active = false;
      disconnect(intentional: false);
      if (mounted) setState(() {});
    }
  }

  Future<void> control(String action) async {
    setState(() => busy = true);
    try {
      final value = await c.rpc('screen.control', {
        'botId': bot['botId'],
        if (session != null) 'sessionId': session,
        'action': action,
      });
      if (mounted) {
        setState(() {
          status = value;
          error = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> action(String method) async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      var operation = await c.rpc(method, {'botId': bot['botId']});
      while (operation['status'] == 'running' && mounted) {
        await Future<void>.delayed(const Duration(seconds: 1));
        operation = await c.rpc('operations.get', {
          'operationId': operation['operationId'],
        });
      }
      if (operation['status'] != 'done') {
        throw RelayError('${operation['detail']}');
      }
      await refresh();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void press(int key) {
    input('key', key: key, down: true);
    input('key', key: key);
  }

  void typeText() {
    for (final point in keyboard.text.runes) {
      press(
        point == 10
            ? 0xff0d
            : point <= 255
            ? point
            : 0x01000000 | point,
      );
    }
    keyboard.clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    poll?.cancel();
    disconnect(intentional: true);
    image?.dispose();
    keyboard.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${bot['displayName']} · ${c.tr('屏幕', 'Screen')}'),
      actions: [
        IconButton(
          tooltip: c.tr('重新连接', 'Reconnect'),
          onPressed: () {
            disconnect(intentional: false);
            connect();
          },
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (widget.members.length > 1)
            SizedBox(
              height: 54,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: widget.members
                    .map(
                      (b) => Padding(
                        padding: const EdgeInsets.all(6),
                        child: ChoiceChip(
                          label: Text('${b['displayName']}'),
                          selected: b['botId'] == bot['botId'],
                          onSelected: (_) {
                            disconnect(intentional: true);
                            session = null;
                            setState(() {
                              bot = b;
                              status = null;
                              image?.dispose();
                              image = null;
                            });
                            refresh();
                          },
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  !connected
                      ? c.tr('未连接', 'Disconnected')
                      : own
                      ? c.tr('你正在控制', 'You are in control')
                      : status?['holder'] == 'human'
                      ? c.tr(
                          '其他客户端正在控制 · 只读',
                          'Another client is controlling · Read-only',
                        )
                      : c.tr('Bot 控制中 · 只读观看', 'Bot is in control · Read-only'),
                ),
                if (status?['running'] == true)
                  FilledButton(
                    onPressed: busy || !connected
                        ? null
                        : () => control(own ? 'release' : 'take'),
                    child: Text(
                      own
                          ? c.tr('交还', 'Hand back')
                          : c.tr('接管', 'Take control'),
                    ),
                  ),
                if (status?['holder'] == 'human' && !own)
                  TextButton(
                    onPressed: busy ? null : () => control('force-release'),
                    child: Text(c.tr('强制交还', 'Force hand back')),
                  ),
                if (status?['installed'] == true && status?['running'] != true)
                  FilledButton(
                    onPressed: busy ? null : () => action('screen.start'),
                    child: Text(c.tr('启动屏幕', 'Start screen')),
                  ),
                if (status?['running'] == true)
                  TextButton(
                    onPressed: busy ? null : () => action('screen.stop'),
                    child: Text(c.tr('停止屏幕', 'Stop screen')),
                  ),
                if (busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          if (status?['blocker'] != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ErrorNotice('${status!['blocker']}'),
            ),
          if (status?['installed'] == false)
            Padding(
              padding: const EdgeInsets.all(20),
              child: SelectableText(
                '${c.tr('屏幕依赖尚未安装', 'Screen dependencies are not installed')}\n${status?['installCommand'] ?? ''}',
              ),
            ),
          Expanded(
            child: ColoredBox(
              color: const Color(0xff16130f),
              child: image == null
                  ? Center(
                      child: Text(
                        c.tr(
                          '画面将在连接后显示',
                          'The screen will appear when connected',
                        ),
                        style: const TextStyle(color: Colors.white70),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) => InteractiveViewer(
                        minScale: .3,
                        maxScale: 4,
                        panEnabled: !own,
                        child: Center(
                          child: FittedBox(
                            child: Focus(
                              focusNode: focus,
                              onKeyEvent: (_, event) {
                                if (!own) return KeyEventResult.ignored;
                                final keys = {
                                  LogicalKeyboardKey.enter: 0xff0d,
                                  LogicalKeyboardKey.escape: 0xff1b,
                                  LogicalKeyboardKey.tab: 0xff09,
                                  LogicalKeyboardKey.backspace: 0xff08,
                                  LogicalKeyboardKey.delete: 0xffff,
                                  LogicalKeyboardKey.arrowLeft: 0xff51,
                                  LogicalKeyboardKey.arrowUp: 0xff52,
                                  LogicalKeyboardKey.arrowRight: 0xff53,
                                  LogicalKeyboardKey.arrowDown: 0xff54,
                                  LogicalKeyboardKey.controlLeft: 0xffe3,
                                  LogicalKeyboardKey.controlRight: 0xffe4,
                                  LogicalKeyboardKey.shiftLeft: 0xffe1,
                                  LogicalKeyboardKey.shiftRight: 0xffe2,
                                  LogicalKeyboardKey.altLeft: 0xffe9,
                                  LogicalKeyboardKey.altRight: 0xffea,
                                };
                                final point =
                                    event.character?.runes.firstOrNull;
                                final key =
                                    keys[event.logicalKey] ??
                                    (point == null
                                        ? null
                                        : point <= 255
                                        ? point
                                        : 0x01000000 | point);
                                if (key == null) return KeyEventResult.ignored;
                                input(
                                  'key',
                                  key: key,
                                  down: event is! KeyUpEvent,
                                );
                                return KeyEventResult.handled;
                              },
                              child: Listener(
                                onPointerDown: (event) {
                                  focus.requestFocus();
                                  buttons =
                                      event.kind == PointerDeviceKind.touch
                                      ? 1
                                      : (event.buttons & 1) |
                                            ((event.buttons & 2) << 1) |
                                            ((event.buttons & 4) >> 1);
                                  input(
                                    'pointer',
                                    x: event.localPosition.dx.round().clamp(
                                      0,
                                      image!.width - 1,
                                    ),
                                    y: event.localPosition.dy.round().clamp(
                                      0,
                                      image!.height - 1,
                                    ),
                                    mask: buttons,
                                  );
                                },
                                onPointerMove: (event) => input(
                                  'pointer',
                                  x: event.localPosition.dx.round().clamp(
                                    0,
                                    image!.width - 1,
                                  ),
                                  y: event.localPosition.dy.round().clamp(
                                    0,
                                    image!.height - 1,
                                  ),
                                  mask: buttons,
                                ),
                                onPointerHover: (event) => input(
                                  'pointer',
                                  x: event.localPosition.dx.round().clamp(
                                    0,
                                    image!.width - 1,
                                  ),
                                  y: event.localPosition.dy.round().clamp(
                                    0,
                                    image!.height - 1,
                                  ),
                                ),
                                onPointerUp: (event) {
                                  buttons = 0;
                                  input(
                                    'pointer',
                                    x: event.localPosition.dx.round().clamp(
                                      0,
                                      image!.width - 1,
                                    ),
                                    y: event.localPosition.dy.round().clamp(
                                      0,
                                      image!.height - 1,
                                    ),
                                  );
                                },
                                onPointerSignal: (event) {
                                  if (event is PointerScrollEvent) {
                                    input(
                                      'pointer',
                                      x: event.localPosition.dx.round().clamp(
                                        0,
                                        image!.width - 1,
                                      ),
                                      y: event.localPosition.dy.round().clamp(
                                        0,
                                        image!.height - 1,
                                      ),
                                      mask: event.scrollDelta.dy < 0 ? 8 : 16,
                                    );
                                    input(
                                      'pointer',
                                      x: event.localPosition.dx.round().clamp(
                                        0,
                                        image!.width - 1,
                                      ),
                                      y: event.localPosition.dy.round().clamp(
                                        0,
                                        image!.height - 1,
                                      ),
                                    );
                                  }
                                },
                                child: RawImage(
                                  image: image,
                                  width: image!.width.toDouble(),
                                  height: image!.height.toDouble(),
                                  filterQuality: FilterQuality.medium,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          Flexible(
            flex: 1,
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  if (error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ErrorNotice(error),
                    ),
                  ExpansionTile(
                    title: Text(c.tr('键盘与常用按键', 'Keyboard & shortcuts')),
                    childrenPadding: const EdgeInsets.all(12),
                    children: [
                      TextField(
                        key: const ValueKey('screen-keyboard'),
                        controller: keyboard,
                        enabled: own,
                        maxLines: 2,
                        minLines: 1,
                        decoration: InputDecoration(
                          hintText: c.tr(
                            '接管后在此输入文字',
                            'Type here after taking control',
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            TextButton(
                              onPressed: own ? typeText : null,
                              child: Text(c.tr('输入', 'Type')),
                            ),
                            TextButton(
                              onPressed: own
                                  ? () {
                                      input('paste', text: keyboard.text);
                                      input('key', key: 0xffe3, down: true);
                                      press(0x76);
                                      input('key', key: 0xffe3);
                                      keyboard.clear();
                                    }
                                  : null,
                              child: Text(c.tr('粘贴', 'Paste')),
                            ),
                            for (final entry in {
                              'Enter': 0xff0d,
                              'Tab': 0xff09,
                              'Esc': 0xff1b,
                              '⌫': 0xff08,
                              '←': 0xff51,
                              '↑': 0xff52,
                              '→': 0xff53,
                              '↓': 0xff54,
                            }.entries)
                              TextButton(
                                onPressed: own
                                    ? () => press(entry.value)
                                    : null,
                                child: Text(entry.key),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
