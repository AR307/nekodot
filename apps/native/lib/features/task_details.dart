import 'package:flutter/material.dart';

import '../data/client.dart';
import 'chat_message.dart';
import 'chat_activity.dart';
import 'chat_presentation.dart';
import 'work.dart';

/// Internal work contributes to one fixed Dot status, never a task navigator.
class DotActivity extends StatelessWidget {
  final NekodotClient client;
  final ChatPresentation view;
  const DotActivity({super.key, required this.client, required this.view});

  @override
  Widget build(BuildContext context) {
    final id = view.conversation['conversationId'];
    final tasks = client.node.tasks.values
        .where(
          (task) =>
              task.conversationId == id &&
              (task.active || task.reportMessageId == null),
        )
        .toList();
    if (tasks.isEmpty && !view.running) return const SizedBox.shrink();
    final names = tasks
        .map((task) => compactActivity(task.title))
        .where((name) => name.isNotEmpty)
        .toSet();
    final line = names.isNotEmpty
        ? names.join(client.tr('、', ', '))
        : !client.online
        ? client.tr('离线', 'Offline')
        : view.activity.connection == 'reconnecting'
        ? client.tr('重连中', 'Reconnecting')
        : view.activity.stalled
        ? client.tr('可能卡住', 'No recent progress')
        : switch (view.state) {
            'waiting_approval' => client.tr('等你确认', 'Needs your OK'),
            'waiting_question' => client.tr('等你回答', 'Needs your answer'),
            'unknown' => client.tr('状态待确认', 'Status unknown'),
            'tool' => client.tr('工具运行中', 'Using tools'),
            _ => client.tr('回复中', 'Replying'),
          };
    final moving =
        client.online &&
        !client.node.syncing &&
        view.activity.connection != 'reconnecting' &&
        !view.activity.stalled &&
        view.state != 'unknown' &&
        tasks.every(
          (task) =>
              task.state != 'unknown' &&
              client.node.taskActivities[task.taskId]?.connection !=
                  'reconnecting',
        ) &&
        ((view.working && !view.waiting) ||
            tasks.any(
              (task) =>
                  task.state == 'running' &&
                  client.node.taskActivities[task.taskId]?.stalled != true,
            ));
    final waitingTask = tasks.where((t) => t.state == 'waiting_approval' || t.state == 'waiting_question').firstOrNull;
    return GestureDetector(
      onTap: waitingTask == null ? null : () => _showControlOverlay(context, waitingTask),
      child: ThinkingRow(
        key: const ValueKey('dot-activity'),
        bot: view.bot,
        line: waitingTask != null ? '⚠️ ${client.tr('需要你的确认 · 点击处理', 'Action required · Tap to view')}' : line,
        moving: moving,
      ),
    );
  }

  void _showControlOverlay(BuildContext context, dynamic task) {
    final msg = (client.node.messages[task.conversationId] ?? []).where((m) => m.taskId == task.taskId && (m.kind == 'question' || m.kind == 'approval')).lastOrNull;
    if (msg == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(blurRadius: 20, color: Colors.black26)],
        ),
        child: ControlCard(client: client, message: msg),
      ),
    );
  }
  }
}
