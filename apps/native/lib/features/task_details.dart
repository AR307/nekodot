import 'package:flutter/material.dart';

import '../data/client.dart';
import 'chat_activity.dart';
import 'chat_presentation.dart';

/// One fixed Dot status: what the working Dot is thinking, or what it waits
/// for. Never a task navigator.
class DotActivity extends StatelessWidget {
  final NekodotClient client;
  final ChatPresentation view;
  const DotActivity({super.key, required this.client, required this.view});

  @override
  Widget build(BuildContext context) {
    final id = view.conversation['conversationId'] as String;
    final tasks = client.node.tasks.values
        .where(
          (task) =>
              task.conversationId == id &&
              (task.active || task.reportMessageId == null),
        )
        .toList();
    final controls = view.controls;
    if (controls.isNotEmpty) {
      return ThinkingRow(
        key: const ValueKey('dot-activity'),
        bot: view.bot,
        line: controls.any((m) => m.kind == 'approval')
            ? client.tr('等你确认', 'Needs your OK')
            : client.tr('等你回答', 'Needs your answer'),
        moving: false,
      );
    }
    if (tasks.isEmpty && !view.running) return const SizedBox.shrink();
    // The conversation's own run first; in a group, a Dot working on a
    // hand-off speaks through its task.
    final thought =
        view.activity.thought ??
        tasks
            .map((task) => client.node.taskActivities[task.taskId]?.thought)
            .nonNulls
            .lastOrNull;
    final line = !client.online
        ? client.tr('离线', 'Offline')
        : view.activity.connection == 'reconnecting'
        ? client.tr('重连中', 'Reconnecting')
        : view.activity.stalled
        ? client.tr('可能卡住', 'No recent progress')
        : switch (view.state) {
            'waiting_approval' => client.tr('等你确认', 'Needs your OK'),
            'waiting_question' => client.tr('等你回答', 'Needs your answer'),
            'unknown' => client.tr('状态待确认', 'Status unknown'),
            _ when thought != null => thought,
            'tool' => client.tr('工具运行中', 'Using tools'),
            _ => client.tr('思考中', 'Thinking'),
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
    return ThinkingRow(
      key: const ValueKey('dot-activity'),
      bot: view.bot,
      line: line,
      moving: moving,
    );
  }
}
