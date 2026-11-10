import 'dart:async';

import 'package:flutter/material.dart';

import '../data/chat_models.dart';
import '../data/client.dart';
import '../data/json.dart';
import '../data/node_data.dart';
import '../data/tasks.dart';
import '../platform/desktop.dart';
import '../ui/design.dart';
import 'chat_message.dart';
import 'chat_presentation.dart';
import 'flowchart.dart';

Future<void> openTaskDetails(
  BuildContext context,
  NekodotClient client,
  DotTask task,
) => Navigator.of(context).push<void>(
  PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: true,
    barrierLabel: client.tr('关闭', 'Close'),
    barrierColor: Colors.black26,
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240),
    reverseTransitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180),
    pageBuilder: (context, _, secondary) {
      final phone =
          context.tone.glass || MediaQuery.sizeOf(context).width < 840;
      return Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: phone ? MediaQuery.sizeOf(context).width : 540,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: context.tone.base,
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(phone ? 0 : 18),
                ),
              ),
              shadows: context.tone.lift,
            ),
            child: ClipRSuperellipse(
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(phone ? 0 : 18),
              ),
              child: InSheet(
                child: TaskDetailsPage(client: client, task: task),
              ),
            ),
          ),
        ),
      );
    },
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

class TaskMark extends StatelessWidget {
  final DotTask task;
  const TaskMark({super.key, required this.task});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = switch (task.state) {
      'completed' => dark ? const Color(0xff66c98c) : const Color(0xff21834a),
      'failed' => context.tone.danger,
      'cancelled' || 'queued' || 'unknown' => context.tone.ink3,
      _ => dark ? const Color(0xff6aaeff) : const Color(0xff2375d4),
    };
    return Icon(
      switch (task.state) {
        'completed' => Icons.check_rounded,
        'failed' => Icons.error_outline,
        'waiting_approval' || 'waiting_question' => Icons.pause_rounded,
        'cancelled' => Icons.stop_circle_outlined,
        'queued' => Icons.schedule,
        _ => Icons.circle_outlined,
      },
      color: color,
      size: 14,
    );
  }
}

class TaskLink extends StatelessWidget {
  final NekodotClient client;
  final DotTask task;
  const TaskLink({super.key, required this.client, required this.task});
  @override
  Widget build(BuildContext context) {
    final bot = client.node.bots
        .where((b) => b['botId'] == task.botId)
        .firstOrNull;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        key: ValueKey('task-${task.taskId}'),
        onPressed: () => openTaskDetails(context, client, task),
        style: TextButton.styleFrom(
          foregroundColor: context.tone.ink2,
          minimumSize: Size(0, context.tone.glass ? 48 : 32),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (bot != null) ...[
              CatAvatar.of(bot, size: 18),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            TaskMark(task: task),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16),
          ],
        ),
      ),
    );
  }
}

class TaskDetailsPage extends StatefulWidget {
  final NekodotClient client;
  final DotTask task;
  const TaskDetailsPage({super.key, required this.client, required this.task});
  @override
  State<TaskDetailsPage> createState() => _TaskDetailsPageState();
}

class _TaskDetailsPageState extends State<TaskDetailsPage> {
  late final NodeData node = widget.client.node;
  late final String nodeId = widget.client.selectedNodeId!;
  String error = '';
  bool loading = true;
  String? focusedMessage;
  final focusedKey = GlobalKey();
  @override
  void initState() {
    super.initState();
    node.retainMessages(widget.task.conversationId);
    unawaited(load());
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final result = await widget.client.rpc('tasks.get', {
        'conversationId': widget.task.conversationId,
        'taskId': widget.task.taskId,
      }, nodeId);
      if (!mounted) return;
      final messages = node.messages[widget.task.conversationId]!;
      for (final value in objects(result['messages'])) {
        final message = ChatMessage.fromJson(value);
        final at = messages.indexWhere((m) => m.messageId == message.messageId);
        if (at < 0) {
          messages.add(message);
        } else {
          messages[at] = message;
        }
      }
      messages.sort((a, b) => a.seq.compareTo(b.seq));
      node.tasks[widget.task.taskId] = DotTask.fromJson(object(result['task']));
      node.changed(widget.task.conversationId);
      widget.client.saveContent(nodeId, widget.task.conversationId);
    } catch (e) {
      if (mounted && !widget.client.isConnectionFailure(e)) {
        setState(() => error = '$e');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> focusMessage(String id) async {
    setState(() => focusedMessage = id);
    await WidgetsBinding.instance.endOfFrame;
    final target = focusedKey.currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(target, alignment: .35);
    }
  }

  @override
  void dispose() {
    node.releaseMessages(widget.task.conversationId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      node.conversation(widget.task.conversationId),
      widget.client.prefs,
    ]),
    builder: (context, child) {
      final task = node.tasks[widget.task.taskId] ?? widget.task;
      final messages = (node.messages[task.conversationId] ?? [])
          .where((m) => m.taskId == task.taskId)
          .toList();
      final items = visibleChatMessages(messages);
      final bot = node.bots.where((b) => b['botId'] == task.botId).firstOrNull;
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 16,
          title: Row(
            children: [
              if (bot != null) ...[
                CatAvatar.of(bot, size: 24),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TaskMark(task: task),
            ],
          ),
          actions: [
            if (task.source == 'chat' || task.source == 'group')
              IconButton(
                icon: const Icon(Icons.account_tree_outlined),
                tooltip: 'Flow',
                onPressed: () => openFlowchart(
                  context,
                  widget.client,
                  task.conversationId,
                  focusMessage,
                  taskId: task.taskId,
                ),
              ),
            IconButton(
              icon: const Icon(Icons.reply_outlined),
              tooltip: widget.client.tr('引用', 'Quote'),
              onPressed: () {
                widget
                    .client
                    .workspace['taskQuote:$nodeId:${task.conversationId}'] = {
                  'taskId': task.taskId,
                  'title': task.title,
                };
                widget.client.saveContent();
                Navigator.of(context).pop();
              },
            ),
            IconButton(
              tooltip: widget.client.tr('关闭', 'Close'),
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
            SizedBox(width: WindowChrome.reserved(context)),
          ],
        ),
        body: Column(
          children: [
            if (loading) const LinearProgressIndicator(minHeight: 2),
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(child: ErrorNotice(error)),
                    IconButton(
                      tooltip: widget.client.tr('重试', 'Retry'),
                      onPressed: load,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView(
                key: ValueKey('task-messages-${task.taskId}'),
                reverse: true,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  for (final item in items.reversed)
                    Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: MessageTile(
                          key: item.messageId == focusedMessage
                              ? focusedKey
                              : ValueKey(item.messageId),
                          client: widget.client,
                          message: item,
                          bot: node.bots
                              .where((b) => b['botId'] == item.author.id)
                              .firstOrNull,
                          showName: task.botIds.length > 1,
                          onRetry: (_) {},
                          onQuote: (_) {
                            widget
                                .client
                                .workspace['taskQuote:$nodeId:${task.conversationId}'] = {
                              'taskId': task.taskId,
                              'title': task.title,
                            };
                            widget.client.saveContent();
                            Navigator.of(context).pop();
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
