import 'json.dart';

class DotTask {
  final String taskId, conversationId, botId, title, source, inputMessageId;
  final String state, executionId, createdAt, updatedAt;
  final List<String> botIds;
  final String? resultMessageId,
      reportMessageId,
      routineId,
      routineExecutionId,
      groupChainId;
  DotTask.fromJson(Json value)
    : taskId = value['taskId'] as String,
      conversationId = value['conversationId'] as String,
      botId = value['botId'] as String,
      botIds = List<String>.from(value['botIds'] ?? [value['botId']]),
      title = value['title'] as String,
      source = value['source'] as String,
      inputMessageId = value['inputMessageId'] as String,
      state = value['state'] as String,
      executionId = value['executionId'] as String,
      createdAt = value['createdAt'] as String,
      updatedAt = value['updatedAt'] as String,
      resultMessageId = value['resultMessageId'] as String?,
      reportMessageId = value['reportMessageId'] as String?,
      routineId = value['routineId'] as String?,
      routineExecutionId = value['routineExecutionId'] as String?,
      groupChainId = value['groupChainId'] as String?;
  bool get active =>
      !const {'completed', 'failed', 'cancelled'}.contains(state);
  Json toJson() => {
    'taskId': taskId,
    'conversationId': conversationId,
    'botId': botId,
    'botIds': botIds,
    'title': title,
    'source': source,
    'inputMessageId': inputMessageId,
    'state': state,
    'executionId': executionId,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'resultMessageId': ?resultMessageId,
    'reportMessageId': ?reportMessageId,
    'routineId': ?routineId,
    'routineExecutionId': ?routineExecutionId,
    'groupChainId': ?groupChainId,
  };
}
