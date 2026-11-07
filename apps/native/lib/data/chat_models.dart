import 'json.dart';

class MessageAuthor {
  final String type;
  final String? id;
  MessageAuthor.fromJson(Json value)
    : type = value['type'] as String,
      id = value['id'] as String?;
}

/// One stored representation of a product message. Native tool/card payloads
/// remain structured data; the envelope is parsed once at the receive boundary.
class ChatMessage {
  final String messageId, conversationId, kind, status, createdAt;
  final int seq;
  final MessageAuthor author;
  Json content;
  ChatMessage.fromJson(Json value)
    : messageId = value['messageId'] as String,
      conversationId = value['conversationId'] as String,
      kind = value['kind'] as String,
      status = value['status'] as String,
      createdAt = value['createdAt'] as String,
      seq = value['seq'] as int,
      author = MessageAuthor.fromJson(object(value['author'])),
      content = object(value['content']);
}

class GroupActivity {
  final int count, max;
  GroupActivity.fromJson(Json value)
    : count = value['count'] as int,
      max = value['max'] as int;
}

class ConversationActivity {
  final String state;
  final String? botId, connection, detail;

  /// Hermes has sent nothing for this run for a while; it is not stopped.
  final bool stalled;
  final GroupActivity? chain;
  const ConversationActivity.idle()
    : state = 'idle',
      botId = null,
      connection = null,
      detail = null,
      stalled = false,
      chain = null;
  ConversationActivity.fromJson(Json value)
    : state = value['state'] as String,
      botId = value['botId'] as String?,
      connection = value['connection'] as String?,
      detail = value['detail'] as String?,
      stalled = value['stalled'] == true,
      chain = value['chain'] == null
          ? null
          : GroupActivity.fromJson(object(value['chain']));
}

class CommandAction {
  final String botId;
  final String? page, prefill, action;
  final String argument;
  final ({String filename, String content})? export;
  CommandAction.fromJson(Json value)
    : botId = value['botId'] as String,
      page = value['native']?['page'] as String?,
      prefill = value['native']?['prefill'] as String?,
      action = value['native']?['action'] as String?,
      argument = value['native']?['argument'] as String? ?? '',
      export = value['native']?['export'] == null
          ? null
          : (
              filename: value['native']['export']['filename'] as String,
              content: value['native']['export']['content'] as String,
            );
}

class CommandOperation {
  final String operationId, status, detail;
  final List<CommandAction> results;
  CommandOperation.fromJson(Json value)
    : operationId = value['operationId'] as String,
      status = value['status'] as String,
      detail = value['detail'] as String,
      results = objects(value['results']).map(CommandAction.fromJson).toList();
}
