import 'dart:async';

import 'package:flutter/material.dart';

import '../data/chat_models.dart';
import '../data/client.dart';
import '../data/json.dart';
import '../data/node_data.dart';
import '../data/tasks.dart';
import '../ui/design.dart';
import 'chat_message.dart';
import 'chat_presentation.dart';
import 'flowchart.dart';
import 'work.dart';

Color taskColor(DotTask task) => switch (task.state) {
  'completed' => Colors.green,
  'failed' => Colors.red,
  'cancelled' || 'queued' || 'unknown' => Colors.grey,
  _ => Colors.blue,
};

class TaskLink extends StatelessWidget {
  final NekodotClient client;
  final DotTask task;
  const TaskLink({super.key, required this.client, required this.task});
  @override
  Widget build(BuildContext context) {
    final bot = client.node.bots
        .where((b) => b['botId'] == task.botId)
        .firstOrNull;
    return InkWell(
      key: ValueKey('task-${task.taskId}'),
      onTap: () =>
          pushPage(context, TaskDetailsPage(client: client, task: task)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            if (bot != null) CatAvatar.of(bot, size: 22),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                '${bot?['displayName'] ?? ''} · ${compactActivity(task.title)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              switch (task.state) {
                'completed' => Icons.check,
                'failed' => Icons.close,
                'waiting_approval' || 'waiting_question' => Icons.pause,
                'cancelled' => Icons.stop_circle_outlined,
                _ => Icons.circle,
              },
              color: taskColor(task),
              size: 14,
            ),
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
  String? focusedMessage;
  final focusedKey = GlobalKey();
  @override
  void initState() {
    super.initState();
    node.retainMessages(widget.task.conversationId);
    unawaited(load());
  }

  Future<void> load() async {
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
      return Scaffold(
        appBar: AppBar(
          title: Text(task.title),
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
          ],
        ),
        body: ListView(
          reverse: true,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            if (error.isNotEmpty) Text(error),
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
      );
    },
  );
}
