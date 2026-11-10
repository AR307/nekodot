class FlowStep {
  Map<String, dynamic> toJson() => {
    'stepId': stepId,
    'runId': runId,
    'sessionId': sessionId,
    'botId': botId,
    'kind': kind,
    'state': state,
    'after': after,
    'tool': ?tool,
    'messageId': ?messageId,
    'title': ?title,
    'parentStepId': ?parentStepId,
  };
  final String stepId, runId, sessionId, botId, kind, state;
  final List<String> after;
  final String? tool, messageId, title, parentStepId;
  FlowStep.fromJson(Map<String, dynamic> value)
    : stepId = value['stepId'] as String,
      runId = value['runId'] as String,
      sessionId = value['sessionId'] as String,
      botId = value['botId'] as String,
      kind = value['kind'] as String,
      state = value['state'] as String,
      after = List<String>.from(value['after'] as List),
      tool = value['tool'] as String?,
      messageId = value['messageId'] as String?,
      title = value['title'] as String?,
      parentStepId = value['parentStepId'] as String?;
}

class FlowSnapshot {
  Map<String, dynamic> toJson() => {
    'flowId': flowId,
    'conversationId': conversationId,
    'taskId': ?taskId,
    'state': state,
    'sessionId': ?sessionId,
    'seq': seq,
    'queuedBotIds': queuedBotIds,
    'steps': steps.map((s) => s.toJson()).toList(),
    'reset': true,
  };
  final String flowId, conversationId, state;
  final String? sessionId, taskId;
  String get key => taskId ?? conversationId;
  final int seq;
  final List<String> queuedBotIds;
  final List<FlowStep> steps;
  FlowSnapshot.fromJson(Map<String, dynamic> value, [FlowSnapshot? previous])
    : flowId = value['flowId'] as String,
      conversationId = value['conversationId'] as String,
      sessionId = value['sessionId'] as String?,
      taskId = value['taskId'] as String?,
      state = value['state'] as String,
      seq = value['seq'] as int,
      queuedBotIds = List<String>.from(value['queuedBotIds'] as List),
      steps = <String, FlowStep>{
        if (previous?.flowId == value['flowId'] && value['reset'] != true)
          for (final step in previous!.steps) step.stepId: step,
        for (final row in value['steps'] as List)
          row['stepId'] as String: FlowStep.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
      }.values.toList();
}
