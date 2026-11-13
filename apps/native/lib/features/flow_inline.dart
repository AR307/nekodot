import 'package:flutter/material.dart';

import '../data/client.dart';
import '../data/flow.dart';
import '../ui/design.dart';
import 'flowchart.dart';
import 'work.dart';

/// The steps of what a Dot is doing, inside the conversation: one line until
/// it is opened, then each step beneath it. A step with a result opens it in
/// place. It stands where there is no room for a panel beside the
/// conversation.
class FlowFold extends StatefulWidget {
  final NekodotClient client;
  final String conversationId;
  final FlowMessageFocus onMessage;
  const FlowFold({
    super.key,
    required this.client,
    required this.conversationId,
    required this.onMessage,
  });
  @override
  State<FlowFold> createState() => _FlowFoldState();
}

class _FlowFoldState extends State<FlowFold> {
  bool open = false, failed = false;

  /// Steps whose result is open beneath them.
  final shown = <String>{};
  NekodotClient get c => widget.client;
  late final updates = c.node.conversation(widget.conversationId);

  Future<void> load() async {
    try {
      await c.loadFlow(widget.conversationId);
      if (mounted) setState(() => failed = false);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  void toggle() {
    setState(() => open = !open);
    if (open) load();
  }

  Future<void> select(FlowStep step) async {
    final id = step.messageId;
    if (id == null) return;
    if (step.tool == null) {
      await widget.onMessage(id);
      return;
    }
    if (shown.remove(step.stepId)) {
      setState(() {});
      return;
    }
    try {
      await c.loadMessages(widget.conversationId, around: id);
      if (mounted) setState(() => shown.add(step.stepId));
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  Widget mark(BuildContext context, String state) {
    final tone = context.tone;
    return SizedBox(
      width: 18,
      height: 18,
      child: Center(
        child: switch (state) {
          'running' => const Breathing(size: 8),
          'done' => Icon(Symbols.check, size: 18, color: tone.ink3),
          'failed' => Icon(Symbols.close, size: 18, color: tone.danger),
          'cancelled' => Icon(Symbols.block, size: 16, color: tone.ink3),
          'waiting' ||
          'paused' => Icon(Symbols.pause, size: 18, color: tone.ink),
          'unknown' => Icon(Symbols.question_mark, size: 16, color: tone.ink3),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([c, updates]),
    builder: (context, _) {
      final flow = c.node.flow(widget.conversationId);
      final steps = flow?.steps ?? const <FlowStep>[];
      if (flow == null || steps.every((s) => s.kind == 'bot')) {
        return const SizedBox.shrink();
      }
      final tone = context.tone, text = Theme.of(context).textTheme;
      final bots = {for (final b in c.node.bots) '${b['botId']}': b};
      final several = steps.map((s) => s.botId).toSet().length > 1;
      // In order, each step under the one it belongs to. With one Dot at
      // work its own row says nothing, so its steps start at the edge.
      final children = <String?, List<FlowStep>>{};
      for (final step in steps) {
        children.putIfAbsent(step.parentStepId, () => []).add(step);
      }
      final rows = <(FlowStep, int)>[];
      void append(String? parent, int depth) {
        for (final step in children[parent] ?? const <FlowStep>[]) {
          final silent = step.kind == 'bot' && !several;
          if (!silent) rows.add((step, depth));
          append(step.stepId, silent ? depth : depth + 1);
        }
      }

      append(null, 0);
      final plan =
          steps
              .where((s) => s.kind == 'plan' && s.state == 'running')
              .lastOrNull ??
          steps.where((s) => s.kind == 'plan').lastOrNull;
      final title = c.node.tasks[flow.taskId]?.title ?? plan?.title ?? 'Flow';
      final owner = bots[steps.first.botId];
      final online = c.online && !c.node.syncing;

      Widget row((FlowStep, int) entry) {
        final (step, depth) = entry;
        final bot = bots[step.botId];
        final label = step.kind == 'bot'
            ? '${bot?['displayName'] ?? ''}'
            : step.kind == 'plan'
            ? step.title!
            : step.kind == 'tool'
            ? step.tool!
            : flowStepName(step.kind, c.zh);
        final message = shown.contains(step.stepId)
            ? c.node.messages[widget.conversationId]
                  ?.where((m) => m.messageId == step.messageId)
                  .firstOrNull
            : null;
        final active = step.state == 'running' || step.state == 'waiting';
        return Column(
          key: ValueKey('flow-fold-step-${step.stepId}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: step.kind == 'plan' || step.messageId == null
                  ? null
                  : () => select(step),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 12 + depth.clamp(0, 3) * 16.0,
                    right: 12,
                  ),
                  child: Row(
                    children: [
                      step.kind == 'bot' && bot != null
                          ? CatAvatar.of(bot, size: 20)
                          : Icon(
                              flowIcons[step.kind],
                              size: 18,
                              color: active ? tone.ink : tone.ink3,
                            ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(
                            fontSize: 14,
                            color: active ? tone.ink : tone.ink2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      mark(context, online ? step.state : 'unknown'),
                    ],
                  ),
                ),
              ),
            ),
            if (message != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: StepRow(
                  client: c,
                  message: message,
                  initiallyOpen: true,
                ),
              ),
          ],
        );
      }

      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Container(
              key: const ValueKey('flow-fold'),
              clipBehavior: Clip.antiAlias,
              decoration: ShapeDecoration(
                color: tone.surface,
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: tone.line, width: Tone.hair),
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: SizeMotion(
                  duration: Motion.fold.duration,
                  curve: Motion.fold,
                  alignment: Alignment.topCenter,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        key: const ValueKey('flow-fold-toggle'),
                        onTap: toggle,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                if (owner != null) ...[
                                  CatAvatar.of(owner, size: 20),
                                  const SizedBox(width: 10),
                                ],
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.titleMedium?.copyWith(
                                      fontSize: 14,
                                      color: tone.ink,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (failed)
                                  Icon(
                                    Symbols.refresh,
                                    size: 18,
                                    color: tone.danger,
                                  )
                                else
                                  mark(
                                    context,
                                    online ? flow.state : 'unknown',
                                  ),
                                const SizedBox(width: 4),
                                Icon(
                                  open
                                      ? Symbols.expand_less
                                      : Symbols.expand_more,
                                  size: 20,
                                  color: tone.ink3,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (open) ...[
                        for (final entry in rows) row(entry),
                        if (flow.queuedBotIds.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                            child: Row(
                              children: [
                                for (final id in flow.queuedBotIds)
                                  if (bots[id] != null)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: Opacity(
                                        opacity: .45,
                                        child: CatAvatar.of(
                                          bots[id]!,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                Text(
                                  flowStepName('pending', c.zh),
                                  style: text.bodySmall?.copyWith(
                                    color: tone.ink3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 4),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
