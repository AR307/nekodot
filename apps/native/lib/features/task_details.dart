import 'package:flutter/material.dart';

import '../data/client.dart';
import 'chat_presentation.dart';
import 'chat_timeline.dart';
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
    final names = tasks.map((task) => compactActivity(task.title)).toSet();
    final line = names.isEmpty
        ? workingLine(client, '${view.bot?['displayName'] ?? view.title}')
        : '${view.title} · ${names.join(client.tr('、', ', '))}';
    final moving =
        client.online &&
        (view.working || tasks.any((task) => task.active)) &&
        view.activity.connection != 'reconnecting' &&
        view.state != 'unknown' &&
        tasks.every(
          (task) =>
              task.state != 'unknown' &&
              client.node.taskActivities[task.taskId]?.connection !=
                  'reconnecting',
        );
    return Padding(
      key: const ValueKey('dot-activity'),
      padding: const EdgeInsets.only(bottom: 8),
      child: ThinkingRow(bot: view.bot, line: line, moving: moving),
    );
  }
}
