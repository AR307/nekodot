import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../data/account.dart';
import '../platform/rust.dart';
import '../ui/design.dart';
import 'bridge/api.dart';

class ScreenPage extends StatefulWidget {
  final NekodotClient client;
  final Json bot;
  final List<Json> members;

  /// As a small window over a conversation it shows the screen, who holds
  /// it, and the one thing to do with it.
  final bool floating;

  /// Set when it is shown over or beside a conversation rather than as a
  /// page: closes it. [onWide] asks for room beside the conversation, and
  /// [onOwn] says when control is taken or handed back.
  final VoidCallback? onClose, onWide;
  final ValueChanged<bool>? onOwn;
  const ScreenPage({
    super.key,
    required this.client,
    required this.bot,
    this.members = const [],
    this.floating = false,
    this.onClose,
    this.onWide,
    this.onOwn,
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
  (ScreenFrame, String)? pendingFrame;
  bool decoding = false;
  String error = '';
  bool connected = false, active = true, busy = false, typing = false;
  int attempts = 0, buttons = 0;
  final keyboard = TextEditingController(), focus = FocusNode();
  NekodotClient get c => widget.client;

  /// Whether control was the viewer's when [ScreenPage.onOwn] was last told.
  bool told = false;
  void tell() {
    if (own == told) return;
    told = own;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onOwn?.call(told);
    });
  }

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
      await ensureRust();
      final ticket = await c.account.request(
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
            url: c.account.wsUrl('/ws/tunnel', {
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
              pendingFrame = (frame, identity);
              decodeLatest();
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

  void decodeLatest() {
    if (decoding || pendingFrame == null) return;
    final (frame, identity) = pendingFrame!;
    pendingFrame = null;
    decoding = true;
    ui.decodeImageFromPixels(
      frame.pixels,
      frame.width,
      frame.height,
      ui.PixelFormat.bgra8888,
      (value) {
        decoding = false;
        if (!mounted || identity != viewer) {
          value.dispose();
        } else {
          final previous = image;
          setState(() {
            image = value;
            connected = true;
            error = '';
            attempts = 0;
          });
          previous?.dispose();
        }
        decodeLatest();
      },
    );
  }

  void disconnected(String reason, {bool retryConnection = true}) {
    if (!mounted) return;
    subscription?.cancel();
    subscription = null;
    viewer = null;
    pendingFrame = null;
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
    pendingFrame = null;
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
  Widget build(BuildContext context) {
    tell();
    return widget.floating ? small(context) : full(context);
  }

  /// The screen as a small window: what is on it, who holds it, and the one
  /// thing to do.
  Widget small(BuildContext context) {
    final tone = context.tone;
    final running = status?['running'] == true;
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(Tone.r12),
      side: BorderSide(color: tone.line, width: Tone.hair),
    );
    return Container(
      key: const ValueKey('screen-window'),
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: tone.menu,
        shape: shape,
        shadows: tone.lift,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 10,
              child: ColoredBox(
                color: Colors.black,
                child: image == null
                    ? const Center(
                        child: Opacity(
                          opacity: .25,
                          child: CatAvatar(color: '#FFFFFF', size: 36),
                        ),
                      )
                    : FittedBox(
                        child: RawImage(
                          image: image,
                          width: image!.width.toDouble(),
                          height: image!.height.toDouble(),
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 10, right: 2),
              child: SizedBox(
                height: 40,
                child: Row(
                  children: [
                    connected && status?['holder'] != 'human'
                        ? const ShiningText(style: TextStyle(fontSize: 12))
                        : StatusDot(on: connected),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        !connected
                            ? c.tr('未连接', 'Disconnected')
                            : status?['holder'] == 'human'
                            ? c.tr('他处控制中', 'Controlled elsewhere')
                            : c.tr('Bot 控制中', 'Bot is in control'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: tone.ink2),
                      ),
                    ),
                    if (running)
                      TextButton(
                        key: const ValueKey('screen-take'),
                        onPressed: busy || !connected
                            ? null
                            : () => control('take'),
                        child: Text(c.tr('接管', 'Take control')),
                      ),
                    IconButton(
                      key: const ValueKey('screen-wide'),
                      tooltip: c.tr('展开', 'Expand'),
                      onPressed: widget.onWide,
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Symbols.open_in_full),
                    ),
                    IconButton(
                      tooltip: c.tr('关闭屏幕', 'Close screen'),
                      onPressed: widget.onClose,
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Symbols.close),
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

  /// The screen with its controls: a page of its own, or the part of the
  /// window beside a conversation.
  Widget full(BuildContext context) {
    final actions = <Widget>[
      if (status?['running'] == true)
        IconButton(
          tooltip: c.tr('键盘', 'Keyboard'),
          isSelected: typing,
          onPressed: () => setState(() => typing = !typing),
          icon: const Icon(Symbols.keyboard),
        ),
      IconButton(
        tooltip: c.tr('重新连接', 'Reconnect'),
        onPressed: () {
          disconnect(intentional: false);
          connect();
        },
        icon: const Icon(Symbols.refresh),
      ),
      if (status?['running'] == true)
        IconButton(
          tooltip: c.tr('停止屏幕', 'Stop screen'),
          onPressed: busy ? null : () => action('screen.stop'),
          icon: const Icon(Symbols.power_settings_new),
        ),
    ];
    final body = SafeArea(
      child: Column(
        children: [
          if (widget.members.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: SizedBox(
                height: context.tone.glass ? 52 : 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: widget.members
                      .map(
                        (b) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Tooltip(
                            message: '${b['displayName']}',
                            child: ChoiceChip(
                              labelPadding: EdgeInsets.zero,
                              padding: const EdgeInsets.all(4),
                              label: CatAvatar.of(b, size: 20),
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
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 12, 6),
            child: Row(
              children: [
                connected && !own && status?['holder'] != 'human'
                    ? const ShiningText(style: TextStyle(fontSize: 12))
                    : StatusDot(on: connected),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    !connected
                        ? c.tr('未连接', 'Disconnected')
                        : own
                        ? c.tr('你正在控制', 'You are in control')
                        : status?['holder'] == 'human'
                        ? c.tr('他处控制中', 'Controlled elsewhere')
                        : c.tr('Bot 控制中', 'Bot is in control'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (busy) const ShiningText(style: TextStyle(fontSize: 12)),
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
              ],
            ),
          ),
          if (status?['blocker'] != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ErrorNotice('${status!['blocker']}'),
            ),
          if (status?['installed'] == false)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Panel(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    '${status?['installCommand'] ?? ''}',
                    style: const TextStyle(fontFamily: monoFont, fontSize: 13),
                  ),
                ),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                decoration: ShapeDecoration(
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: own ? context.tone.ink : context.tone.line,
                      width: own ? 2 : 1,
                    ),
                  ),
                ),
                child: ClipRSuperellipse(
                  borderRadius: BorderRadius.circular(9),
                  child: ColoredBox(
                    color: Colors.black,
                    child: image == null
                        ? const Center(
                            child: Opacity(
                              opacity: .25,
                              child: CatAvatar(color: '#FFFFFF', size: 56),
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) =>
                                InteractiveViewer(
                                  minScale: .3,
                                  maxScale: 4,
                                  panEnabled: !own,
                                  child: Center(
                                    child: FittedBox(
                                      child: Focus(
                                        focusNode: focus,
                                        onKeyEvent: (_, event) {
                                          if (!own) {
                                            return KeyEventResult.ignored;
                                          }
                                          final keys = {
                                            LogicalKeyboardKey.enter: 0xff0d,
                                            LogicalKeyboardKey.escape: 0xff1b,
                                            LogicalKeyboardKey.tab: 0xff09,
                                            LogicalKeyboardKey.backspace:
                                                0xff08,
                                            LogicalKeyboardKey.delete: 0xffff,
                                            LogicalKeyboardKey.arrowLeft:
                                                0xff51,
                                            LogicalKeyboardKey.arrowUp: 0xff52,
                                            LogicalKeyboardKey.arrowRight:
                                                0xff53,
                                            LogicalKeyboardKey.arrowDown:
                                                0xff54,
                                            LogicalKeyboardKey.controlLeft:
                                                0xffe3,
                                            LogicalKeyboardKey.controlRight:
                                                0xffe4,
                                            LogicalKeyboardKey.shiftLeft:
                                                0xffe1,
                                            LogicalKeyboardKey.shiftRight:
                                                0xffe2,
                                            LogicalKeyboardKey.altLeft: 0xffe9,
                                            LogicalKeyboardKey.altRight: 0xffea,
                                          };
                                          final point = event
                                              .character
                                              ?.runes
                                              .firstOrNull;
                                          final key =
                                              keys[event.logicalKey] ??
                                              (point == null
                                                  ? null
                                                  : point <= 255
                                                  ? point
                                                  : 0x01000000 | point);
                                          if (key == null) {
                                            return KeyEventResult.ignored;
                                          }
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
                                                event.kind ==
                                                    PointerDeviceKind.touch
                                                ? 1
                                                : (event.buttons & 1) |
                                                      ((event.buttons & 2) <<
                                                          1) |
                                                      ((event.buttons & 4) >>
                                                          1);
                                            input(
                                              'pointer',
                                              x: event.localPosition.dx
                                                  .round()
                                                  .clamp(0, image!.width - 1),
                                              y: event.localPosition.dy
                                                  .round()
                                                  .clamp(0, image!.height - 1),
                                              mask: buttons,
                                            );
                                          },
                                          onPointerMove: (event) => input(
                                            'pointer',
                                            x: event.localPosition.dx
                                                .round()
                                                .clamp(0, image!.width - 1),
                                            y: event.localPosition.dy
                                                .round()
                                                .clamp(0, image!.height - 1),
                                            mask: buttons,
                                          ),
                                          onPointerHover: (event) => input(
                                            'pointer',
                                            x: event.localPosition.dx
                                                .round()
                                                .clamp(0, image!.width - 1),
                                            y: event.localPosition.dy
                                                .round()
                                                .clamp(0, image!.height - 1),
                                          ),
                                          onPointerUp: (event) {
                                            buttons = 0;
                                            input(
                                              'pointer',
                                              x: event.localPosition.dx
                                                  .round()
                                                  .clamp(0, image!.width - 1),
                                              y: event.localPosition.dy
                                                  .round()
                                                  .clamp(0, image!.height - 1),
                                            );
                                          },
                                          onPointerSignal: (event) {
                                            if (event is PointerScrollEvent) {
                                              input(
                                                'pointer',
                                                x: event.localPosition.dx
                                                    .round()
                                                    .clamp(0, image!.width - 1),
                                                y: event.localPosition.dy
                                                    .round()
                                                    .clamp(
                                                      0,
                                                      image!.height - 1,
                                                    ),
                                                mask: event.scrollDelta.dy < 0
                                                    ? 8
                                                    : 16,
                                              );
                                              input(
                                                'pointer',
                                                x: event.localPosition.dx
                                                    .round()
                                                    .clamp(0, image!.width - 1),
                                                y: event.localPosition.dy
                                                    .round()
                                                    .clamp(
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
              ),
            ),
          ),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ErrorNotice(error),
            ),
          if (typing)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Panel(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      TextField(
                        key: const ValueKey('screen-keyboard'),
                        controller: keyboard,
                        enabled: own,
                        maxLines: 2,
                        minLines: 1,
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
                ),
              ),
            ),
        ],
      ),
    );
    if (widget.onClose == null) {
      return AppPage(
        title: '${bot['displayName']}',
        actions: actions,
        body: body,
      );
    }
    return Material(
      key: const ValueKey('screen-beside'),
      color: context.tone.base,
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                const SizedBox(width: 4),
                IconButton(
                  tooltip: c.tr('关闭屏幕', 'Close screen'),
                  onPressed: widget.onClose,
                  icon: const Icon(Symbols.close),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${bot['displayName']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ...actions,
                const SizedBox(width: 4),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}
