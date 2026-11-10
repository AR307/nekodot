import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../data/flow.dart';
import '../platform/desktop.dart';
import '../ui/design.dart';
import 'work.dart';

typedef FlowMessageFocus = Future<void> Function(String messageId);
const _rowExtent = 56.0;
const _nodeExtent = 32.0;

const _copy = <String, (String, String)>{
  'title': ('Flow', 'Flow'),
  'close': ('关闭', 'Close'),
  'follow': ('当前步骤', 'Current step'),
  'retry': ('重试', 'Retry'),
  'disconnected': ('连接中断', 'Disconnected'),
  'thinking': ('思考中', 'Thinking'),
  'reply': ('回复', 'Reply'),
  'browser': ('浏览器', 'Browser'),
  'search': ('搜索', 'Search'),
  'read': ('读文件', 'Read file'),
  'write': ('写文件', 'Write file'),
  'code': ('执行代码', 'Run code'),
  'terminal': ('终端', 'Terminal'),
  'approval': ('等待授权', 'Approval'),
  'question': ('等待回答', 'Question'),
  'running': ('执行中', 'Running'),
  'waiting': ('等待中', 'Waiting'),
  'pending': ('排队中', 'Queued'),
  'done': ('已完成', 'Done'),
  'failed': ('失败', 'Failed'),
  'cancelled': ('已停止', 'Stopped'),
  'paused': ('已暂停', 'Paused'),
  'unknown': ('状态待确认', 'Status unknown'),
};
String _text(String key, bool zh) => zh ? _copy[key]!.$1 : _copy[key]!.$2;

Color _stateColor(BuildContext context, String state) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (state) {
    'done' => dark ? const Color(0xff66c98c) : const Color(0xff21834a),
    'running' ||
    'waiting' => dark ? const Color(0xff6aaeff) : const Color(0xff2375d4),
    'failed' => dark ? const Color(0xffff7a80) : const Color(0xffcf3e48),
    _ => context.tone.ink3,
  };
}

Future<void> openFlowchart(
  BuildContext context,
  NekodotClient client,
  String conversationId,
  FlowMessageFocus focus, {
  String? taskId,
}) => Navigator.of(context).push<void>(
  PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: true,
    barrierLabel: _text('close', client.zh),
    barrierColor: Colors.black26,
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240),
    reverseTransitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180),
    pageBuilder: (context, _, secondary) => Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width:
            Theme.of(context).platform == TargetPlatform.android ||
                MediaQuery.sizeOf(context).width < 840
            ? MediaQuery.sizeOf(context).width
            : 340,
        child: FlowchartPanel(
          client: client,
          conversationId: conversationId,
          taskId: taskId,
          onClose: () => Navigator.pop(context),
          onMessage: (id) async {
            Navigator.pop(context);
            await focus(id);
          },
        ),
      ),
    ),
    transitionsBuilder: (context, animation, secondary, child) =>
        SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
            CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
          ),
          child: child,
        ),
  ),
);

class FlowchartPanel extends StatefulWidget {
  final NekodotClient client;
  final String conversationId;
  final String? taskId;
  final VoidCallback onClose;
  final FlowMessageFocus onMessage;
  final bool reserveControls;
  const FlowchartPanel({
    super.key,
    required this.client,
    required this.conversationId,
    this.taskId,
    required this.onClose,
    required this.onMessage,
    this.reserveControls = false,
  });
  @override
  State<FlowchartPanel> createState() => _FlowchartPanelState();
}

class _FlowchartPanelState extends State<FlowchartPanel>
    with TickerProviderStateMixin {
  final scroll = ScrollController();
  late final pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  late final travel = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  FlowSnapshot? flow;
  bool follow = true,
      loading = true,
      failed = false,
      connected = false,
      still = false;
  String? travellingTo;
  List<(int, int)> edges = [];
  List<double> positions = [];
  List<FlowStep> visible = [];
  final collapsed = <String>{};
  NekodotClient get c => widget.client;
  late final updates = c.node.conversation(widget.conversationId);

  @override
  void initState() {
    super.initState();
    flow = c.node.flow(widget.conversationId, widget.taskId);
    collapsed.addAll(
      flow?.steps
              .where((s) => s.kind == 'plan' && s.state == 'done')
              .map((s) => s.stepId) ??
          [],
    );
    connected =
        c.online &&
        !c.node.syncing &&
        c.node.taskActivities[flow?.taskId]?.connection != 'reconnecting';
    layout();
    WidgetsBinding.instance.addPostFrameCallback((_) => followCurrent());
    c.addListener(changed);
    updates.addListener(changed);
    unawaited(load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    still = MediaQuery.disableAnimationsOf(context);
    motion();
  }

  Future<void> load() async {
    try {
      await c.loadFlow(widget.conversationId, widget.taskId);
      if (mounted) {
        setState(() {
          loading = false;
          failed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          failed = true;
        });
      }
    }
  }

  void changed() {
    final next = c.node.flow(widget.conversationId, widget.taskId);
    final online =
        c.online &&
        !c.node.syncing &&
        c.node.taskActivities[flow?.taskId]?.connection != 'reconnecting';
    if (identical(next, flow) && connected == online) return;
    FlowStep? cursor(FlowSnapshot? value) => value?.steps
        .where(
          (s) =>
              s.kind != 'bot' &&
              s.kind != 'plan' &&
              (s.state == 'running' || s.state == 'waiting'),
        )
        .lastOrNull;
    final current = cursor(next);
    final previousCursor = cursor(flow);
    final added =
        current != null &&
        (current.stepId != previousCursor?.stepId ||
            current.parentStepId != previousCursor?.parentStepId);
    setState(() {
      if (flow?.flowId != next?.flowId) {
        follow = true;
        collapsed.clear();
      }
      final previous = {
        for (final s in flow?.steps ?? <FlowStep>[]) s.stepId: s.state,
      };
      for (final step in next?.steps ?? <FlowStep>[]) {
        if (step.kind != 'plan' || previous[step.stepId] == step.state) {
          continue;
        }
        if (step.state == 'done') collapsed.add(step.stepId);
        if (step.state == 'running') collapsed.remove(step.stepId);
      }
      flow = next;
      connected = online;
      if (added) travellingTo = current.stepId;
      layout();
    });
    if (added && online && !still) travel.forward(from: 0);
    motion();
    if (follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) => followCurrent());
    }
  }

  void motion() {
    if (!still && connected && flow?.state == 'running') {
      if (!pulse.isAnimating) pulse.repeat(reverse: true);
    } else {
      pulse.stop();
      travel.stop();
    }
  }

  void layout() {
    final steps = flow?.steps ?? [];
    final byId = {for (final step in steps) step.stepId: step};
    final children = <String?, List<FlowStep>>{};
    for (final step in steps) {
      children.putIfAbsent(step.parentStepId, () => []).add(step);
    }
    visible = [];
    positions = [];
    edges = [];
    final branches = <String, int>{};
    void append(String? parent, int depth) {
      for (final step in children[parent] ?? <FlowStep>[]) {
        visible.add(step);
        final key = '${step.parentStepId}:${step.after.join('|')}';
        final peers = step.tool == null ? 0 : branches[key] ?? 0;
        if (step.tool != null) branches[key] = peers + 1;
        positions.add(
          step.kind == 'bot'
              ? 28
              : 48 + math.min(depth, 3) * 20 + math.min(peers, 2) * 16.0,
        );
        if (!collapsed.contains(step.stepId)) append(step.stepId, depth + 1);
      }
    }

    append(null, 0);
    final indexes = {
      for (var i = 0; i < visible.length; i++) visible[i].stepId: i,
    };
    final previousSibling = <String?, String>{};
    for (var i = 0; i < visible.length; i++) {
      final step = visible[i];
      final sources = step.kind == 'plan'
          ? [previousSibling[step.parentStepId] ?? step.parentStepId]
          : step.after.cast<String?>();
      final from = <int>{};
      for (var id in sources) {
        while (id != null && !indexes.containsKey(id)) {
          id = byId[id]?.parentStepId;
        }
        if (step.parentStepId != null &&
            byId[id]?.parentStepId != step.parentStepId) {
          id = step.parentStepId;
        }
        final index = indexes[id];
        if (index != null && index < i) from.add(index);
      }
      edges.addAll(from.map((index) => (index, i)));
      previousSibling[step.parentStepId] = step.stepId;
    }
  }

  void followCurrent() {
    if (!mounted || !scroll.hasClients || !follow) return;
    final steps = visible;
    var index = steps.lastIndexWhere(
      (s) => s.kind != 'bot' && (s.state == 'running' || s.state == 'waiting'),
    );
    if (index < 0) index = steps.lastIndexWhere((s) => s.state != 'pending');
    final target =
        ((index + 1) * _rowExtent - scroll.position.viewportDimension + 20)
            .clamp(0.0, scroll.position.maxScrollExtent);
    if (still) {
      scroll.jumpTo(target);
    } else {
      unawaited(
        scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  Future<void> select(FlowStep step) async {
    if (step.messageId == null) return;
    if (step.tool == null) {
      await widget.onMessage(step.messageId!);
      return;
    }
    try {
      await c.loadMessages(widget.conversationId, around: step.messageId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          contentPadding: const EdgeInsets.all(12),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: Listenable.merge([c, updates]),
                builder: (context, _) {
                  final message = c.node.messages[widget.conversationId]
                      ?.where((m) => m.messageId == step.messageId)
                      .firstOrNull;
                  return message == null
                      ? const SizedBox.shrink()
                      : StepRow(
                          client: c,
                          message: message,
                          initiallyOpen: true,
                        );
                },
              ),
            ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    updates.removeListener(changed);
    c.removeListener(changed);
    scroll.dispose();
    pulse.dispose();
    travel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = visible;
    final travelIndex = steps.indexWhere((s) => s.stepId == travellingTo);
    final tone = context.tone;
    final conversation = c.node.conversations
        .where((v) => v['conversationId'] == widget.conversationId)
        .firstOrNull;
    final group = c.node.groups
        .where((g) => g['groupId'] == conversation?['groupId'])
        .firstOrNull;
    final owner = c.node.bots
        .where(
          (b) => b['botId'] == (conversation?['botId'] ?? group?['leadBotId']),
        )
        .firstOrNull;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          key: const ValueKey('flowchart-panel'),
          backgroundColor: tone.base,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            titleSpacing: 12,
            title: Text(
              _text('title', c.zh),
              style: const TextStyle(fontSize: 14),
            ),
            actions: [
              if (flow != null && steps.isNotEmpty && flow!.state != 'running')
                Tooltip(
                  message: _text(flow!.state, c.zh),
                  child: Icon(
                    switch (flow!.state) {
                      'done' => Icons.check_circle_outline,
                      'failed' => Icons.error_outline,
                      'unknown' => Icons.help_outline,
                      'cancelled' => Icons.block,
                      _ => Icons.pause_circle_outline,
                    },
                    size: 18,
                    color: _stateColor(context, flow!.state),
                  ),
                ),
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (failed)
                IconButton(
                  tooltip: _text('retry', c.zh),
                  onPressed: load,
                  icon: Icon(Icons.refresh, color: tone.danger),
                ),
              if (!connected && !loading)
                Tooltip(
                  message: _text('disconnected', c.zh),
                  child: const Icon(Icons.cloud_off_outlined, size: 18),
                ),
              IconButton(
                key: const ValueKey('flow-close'),
                tooltip: _text('close', c.zh),
                onPressed: widget.onClose,
                icon: Icon(Icons.close, color: tone.ink),
              ),
              if (widget.reserveControls)
                SizedBox(width: WindowChrome.reserved(context)),
            ],
          ),
          body: steps.isEmpty
              ? Center(
                  child: owner == null
                      ? const CatAvatar(size: 36)
                      : CatAvatar.of(owner, size: 36),
                )
              : Stack(
                  children: [
                    NotificationListener<UserScrollNotification>(
                      onNotification: (n) {
                        if (n.direction != ScrollDirection.idle && follow) {
                          setState(() => follow = false);
                        }
                        return false;
                      },
                      child: ListView.builder(
                        key: const ValueKey('flow-steps'),
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 64),
                        itemExtent: _rowExtent,
                        itemCount:
                            steps.length +
                            ((flow?.queuedBotIds.isNotEmpty ?? false) ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == steps.length) {
                            return Row(
                              children: [
                                for (final id in flow!.queuedBotIds)
                                  if (c.node.bots.any((b) => b['botId'] == id))
                                    Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Tooltip(
                                        message:
                                            '${c.node.bots.firstWhere((b) => b['botId'] == id)['displayName']}, ${_text('pending', c.zh)}',
                                        child: Opacity(
                                          opacity: .4,
                                          child: CatAvatar.of(
                                            c.node.bots.firstWhere(
                                              (b) => b['botId'] == id,
                                            ),
                                            size: 28,
                                          ),
                                        ),
                                      ),
                                    ),
                              ],
                            );
                          }
                          final step = steps[index];
                          final bot = c.node.bots
                              .where((b) => b['botId'] == step.botId)
                              .firstOrNull;
                          final color = _stateColor(context, step.state);
                          final running =
                              connected &&
                              flow!.state == 'running' &&
                              step.state == 'running';
                          final animated =
                              running ||
                              (connected &&
                                  edges.any(
                                    (e) =>
                                        e.$2 == travelIndex &&
                                        e.$1 <= index &&
                                        e.$2 >= index,
                                  ) &&
                                  travel.isAnimating);
                          final animation = Listenable.merge([pulse, travel]);
                          Widget row() => CustomPaint(
                            painter: _FlowEdges(
                              index,
                              positions,
                              edges,
                              tone.line,
                              color,
                              travelIndex,
                              connected && !still ? travel.value : 0,
                            ),
                            child: _FlowRow(
                              step: step,
                              bot: bot,
                              color: color,
                              x: positions[index],
                              pulse: running && !still ? pulse.value : 0,
                              running: running,
                              zh: c.zh,
                              expanded: !collapsed.contains(step.stepId),
                              onTap: step.kind == 'plan'
                                  ? () {
                                      setState(() {
                                        follow = false;
                                        if (!collapsed.remove(step.stepId)) {
                                          collapsed.add(step.stepId);
                                        }
                                        layout();
                                      });
                                    }
                                  : step.messageId == null
                                  ? null
                                  : () => select(step),
                            ),
                          );
                          return RepaintBoundary(
                            key: ValueKey('flow-step-${step.stepId}'),
                            child: animated
                                ? AnimatedBuilder(
                                    animation: animation,
                                    builder: (context, _) => row(),
                                  )
                                : row(),
                          );
                        },
                      ),
                    ),
                    if (!follow)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: IconButton.filledTonal(
                          key: const ValueKey('flow-follow'),
                          tooltip: _text('follow', c.zh),
                          icon: const Icon(Icons.my_location),
                          onPressed: () {
                            setState(() {
                              follow = true;
                              for (final step in flow?.steps ?? <FlowStep>[]) {
                                if (step.kind == 'plan' &&
                                    step.state == 'running') {
                                  collapsed.remove(step.stepId);
                                }
                              }
                              layout();
                            });
                            followCurrent();
                          },
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

const flowIcons = <String, IconData>{
  'plan': Icons.checklist_outlined,
  'thinking': Icons.psychology_outlined,
  'reply': Icons.chat_bubble_outline,
  'browser': Icons.web_asset_outlined,
  'search': Icons.search,
  'read': Icons.description_outlined,
  'write': Icons.description_outlined,
  'code': Icons.code,
  'terminal': Icons.terminal,
  'approval': Icons.shield_outlined,
  'question': Icons.help_outline,
  'tool': Icons.build_outlined,
};

class _FlowRow extends StatelessWidget {
  final FlowStep step;
  final Json? bot;
  final Color color;
  final double x, pulse;
  final bool running, zh, expanded;
  final VoidCallback? onTap;
  const _FlowRow({
    required this.step,
    required this.bot,
    required this.color,
    required this.x,
    required this.pulse,
    required this.running,
    required this.zh,
    required this.expanded,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final active = step.state == 'running' || step.state == 'waiting';
    final label = step.kind == 'bot'
        ? '${bot?['displayName'] ?? step.botId}'
        : step.kind == 'plan'
        ? step.title!
        : step.kind == 'tool'
        ? step.tool!
        : _text(step.kind, zh);
    final mark = switch (step.state) {
      'done' => Icons.check,
      'failed' => Icons.close,
      'cancelled' => Icons.block,
      'waiting' || 'paused' => Icons.pause,
      'unknown' => Icons.question_mark,
      _ => null,
    };
    final ink = color;
    return Semantics(
      label: '$label, ${_text(step.state, zh)}',
      expanded: step.kind == 'plan' ? expanded : null,
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(width: x - 22),
            SizedBox(
              width: 44,
              height: 44,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        width: _nodeExtent,
                        height: _nodeExtent,
                        decoration: ShapeDecoration(
                          color: tone.base,
                          shadows: running
                              ? [
                                  BoxShadow(
                                    color: color.withValues(
                                      alpha: .08 + .1 * pulse,
                                    ),
                                    blurRadius: 8,
                                  ),
                                ]
                              : [],
                          shape: RoundedSuperellipseBorder(
                            borderRadius: BorderRadius.circular(9),
                            side: BorderSide(
                              color: active
                                  ? color.withValues(alpha: .65 + .35 * pulse)
                                  : color.withValues(alpha: .5),
                              width: active ? 1.8 : 1,
                            ),
                          ),
                        ),
                        child: Center(
                          child: step.kind == 'bot' && bot != null
                              ? MediaQuery(
                                  data: MediaQuery.of(context).copyWith(
                                    disableAnimations:
                                        !running ||
                                        MediaQuery.disableAnimationsOf(context),
                                  ),
                                  child: CatAvatar.of(
                                    bot!,
                                    size: 28,
                                    working: running,
                                  ),
                                )
                              : Icon(
                                  flowIcons[step.kind],
                                  size: 20,
                                  color: ink,
                                ),
                        ),
                      ),
                    ),
                  ),
                  if (step.kind == 'read' || step.kind == 'write')
                    Positioned(
                      right: 3,
                      bottom: 3,
                      child: ColoredBox(
                        color: tone.base,
                        child: Icon(
                          step.kind == 'read'
                              ? Icons.visibility_outlined
                              : Icons.edit_outlined,
                          size: 13,
                          color: ink,
                        ),
                      ),
                    ),
                  if (mark != null)
                    Positioned(
                      right: 1,
                      top: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: tone.base,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(mark, size: 14, color: ink),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: active ? tone.ink : tone.ink2),
              ),
            ),
            if (onTap != null)
              Icon(
                step.kind == 'plan' && expanded
                    ? Icons.expand_more
                    : Icons.chevron_right,
                size: 14,
                color: tone.ink3,
              ),
          ],
        ),
      ),
    );
  }
}

class _FlowEdges extends CustomPainter {
  final int row;
  final List<double> positions;
  final List<(int, int)> edges;
  final Color line, active;
  final int travelIndex;
  final double travel;
  _FlowEdges(
    this.row,
    this.positions,
    this.edges,
    this.line,
    this.active,
    this.travelIndex,
    this.travel,
  );
  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final (from, to) in edges) {
      if (from > row || to < row) continue;
      final start = Offset(
        positions[from],
        (from - row) * _rowExtent + (_rowExtent + _nodeExtent) / 2,
      );
      final end = Offset(
        positions[to],
        (to - row) * _rowExtent + (_rowExtent - _nodeExtent) / 2,
      );
      final mid = start.dy + (end.dy - start.dy) / 2;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(start.dx, mid, end.dx, mid, end.dx, end.dy);
      canvas.drawPath(path, paint);
      if (to == travelIndex && travel > 0 && travel < 1) {
        final metric = path.computeMetrics().first;
        final point = metric
            .getTangentForOffset(metric.length * travel)!
            .position;
        canvas.drawCircle(point, 2.5, Paint()..color = active);
      }
    }
  }

  @override
  bool shouldRepaint(_FlowEdges old) =>
      old.positions != positions ||
      old.edges != edges ||
      old.row != row ||
      old.line != line ||
      old.active != active ||
      old.travelIndex != travelIndex ||
      old.travel != travel;
}
