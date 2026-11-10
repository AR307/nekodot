import 'package:flutter/material.dart';

import '../data/chat_models.dart';
import '../data/client.dart';
import '../data/json.dart';
import '../data/tasks.dart';
import '../ui/design.dart';
import 'task_details.dart';
import 'work.dart';

/// A presentation of the native activity, never inferred from message prose.
class ChatActivity {
  final NekodotClient client;
  final String conversationId;
  final DotTask? task;
  const ChatActivity(this.client, this.conversationId, [this.task]);

  ConversationActivity get activity =>
      (task == null
          ? client.node.activities[conversationId]
          : client.node.taskActivities[task!.taskId]) ??
      const ConversationActivity.idle();
  String get state => task?.state ?? activity.state;
  bool get connected =>
      client.online &&
      !client.node.syncing &&
      activity.connection != 'reconnecting';
  bool get moving =>
      connected &&
      !activity.stalled &&
      const {'thinking', 'tool', 'running'}.contains(state);
  Json? get bot => client.node.bots
      .where((bot) => bot['botId'] == (activity.botId ?? task?.botId))
      .firstOrNull;

  String get label {
    final c = client;
    if (!c.online) return c.tr('离线', 'Offline');
    if (!connected) return c.tr('重连中', 'Reconnecting');
    if (activity.stalled) return c.tr('可能卡住', 'No recent progress');
    switch (state) {
      case 'waiting_approval':
        return c.tr('等你确认', 'Needs your OK');
      case 'waiting_question':
        return c.tr('等你回答', 'Needs your answer');
      case 'queued':
        return c.tr('排队中', 'Queued');
      case 'unknown':
        return c.tr('状态待确认', 'Status unknown');
      case 'completed':
        return c.tr('已完成', 'Done');
      case 'failed':
        return c.tr('失败', 'Failed');
      case 'cancelled':
        return c.tr('已停止', 'Stopped');
    }
    if (task == null) return c.tr('回复中', 'Replying');
    final step = c.node.flows[task!.taskId]?.steps
        .where((step) => step.state == 'running' && step.kind != 'plan')
        .lastOrNull;
    if (step?.tool != null) return stepLabel(c, {'tool': step!.tool});
    if (step?.kind == 'reply') return c.tr('回复中', 'Replying');
    if (state == 'tool') return c.tr('工具运行中', 'Using tools');
    return c.tr('思考中', 'Thinking');
  }
}

/// Lives directly above the input, outside the message and attachment lists.
class ChatActivityDock extends StatefulWidget {
  final NekodotClient client;
  final String conversationId;
  const ChatActivityDock({
    super.key,
    required this.client,
    required this.conversationId,
  });
  @override
  State<ChatActivityDock> createState() => _ChatActivityDockState();
}

class _ChatActivityDockState extends State<ChatActivityDock> {
  String? selected;
  @override
  Widget build(BuildContext context) {
    final c = widget.client, id = widget.conversationId;
    final tasks = c.node.tasks.values
        .where(
          (task) =>
              task.conversationId == id &&
              (task.source == 'chat' || task.source == 'group') &&
              (task.active || task.reportMessageId == null),
        )
        .toList();
    final task =
        tasks.where((task) => task.taskId == selected).firstOrNull ??
        tasks.where((task) => task.state.startsWith('waiting_')).firstOrNull ??
        tasks.where((task) => task.active).lastOrNull ??
        tasks.lastOrNull;
    final activity = ChatActivity(c, id, task);
    if (task == null && activity.state == 'idle') {
      return const SizedBox.shrink();
    }
    final tone = context.tone;
    final style = Theme.of(context).textTheme.bodyMedium!
        .copyWith(fontSize: 13, color: tone.ink2);
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(10),
    );
    final height = tone.glass ? 48.0 : 40.0;
    return Material(
      key: const ValueKey('chat-activity-dock'),
      color: tone.base,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: const ValueKey('chat-activity-current'),
              customBorder: shape,
              onTap: task == null
                  ? null
                  : () => openTaskDetails(context, c, task),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: height),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      if (activity.bot case final bot?)
                        CatAvatar.of(bot, size: 24)
                      else
                        const CatAvatar(size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: activity.moving
                            ? ShiningText(text: activity.label, style: style)
                            : Text(
                                activity.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: style,
                              ),
                      ),
                      if (task != null) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            task.title,
                            textAlign: TextAlign.end,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style.copyWith(color: tone.ink3),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right, size: 16, color: tone.ink3),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (tasks.length > 1)
            PopupMenuButton<String>(
              key: const ValueKey('chat-activity-select'),
              tooltip: c.tr('详情', 'Details'),
              initialValue: task?.taskId,
              constraints: const BoxConstraints(minWidth: 260, maxWidth: 340),
              onSelected: (value) => setState(() => selected = value),
              itemBuilder: (context) => [
                for (final item in tasks)
                  PopupMenuItem(
                    value: item.taskId,
                    height: 56,
                    child: Builder(
                      builder: (context) {
                        final row = ChatActivity(c, id, item);
                        return Row(
                          children: [
                            if (row.bot case final bot?)
                              CatAvatar.of(bot, size: 24)
                            else
                              const CatAvatar(size: 24),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    row.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: style.copyWith(color: tone.ink3),
                                  ),
                                ],
                              ),
                            ),
                            if (item.taskId == task?.taskId)
                              const Icon(Icons.check, size: 16),
                          ],
                        );
                      },
                    ),
                  ),
              ],
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: height,
                  minHeight: height,
                ),
                child: Row(
                  children: [
                    Text('${tasks.length}', style: style),
                    const Icon(Icons.unfold_more, size: 16),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
