import '../data/chat_models.dart';
import '../data/json.dart';
import '../data/node_data.dart';
import 'work.dart';

/// Derived view of one conversation; does not own execution or message state.
class ChatPresentation {
  final Json conversation;
  final Json? group, bot;
  final List<Json> members;
  final ConversationActivity activity;
  final List<ChatMessage> messages;
  final String title;
  ChatPresentation._(
    this.conversation,
    this.group,
    this.bot,
    this.members,
    this.activity,
    this.messages,
    this.title,
  );
  factory ChatPresentation(NodeData node, Json conversation) {
    final group = conversation['kind'] == 'group'
        ? node.groups
              .where((x) => x['groupId'] == conversation['groupId'])
              .firstOrNull
        : null;
    final activity =
        node.activities[conversation['conversationId']] ??
        const ConversationActivity.idle();
    final members = node.bots
        .where(
          (b) => group == null
              ? b['botId'] == conversation['botId']
              : (group['botIds'] as List).contains(b['botId']),
        )
        .toList();
    final messages =
        visibleChatMessages(node.messages[conversation['conversationId']] ?? [])
            .where(
              (row) =>
                  (row.taskRole != 'execution' ||
                  const {'approval', 'question', 'secret'}.contains(row.kind)),
            )
            .toList();
    final lastBot = messages
        .where((m) => m.author.type == 'bot')
        .lastOrNull
        ?.author
        .id;
    final bot =
        members
            .where(
              (b) =>
                  b['botId'] ==
                  (activity.botId ??
                      lastBot ??
                      group?['leadBotId'] ??
                      conversation['botId']),
            )
            .firstOrNull ??
        members.firstOrNull;
    final title =
        group?['name'] as String? ?? bot?['displayName'] as String? ?? 'Bot';

    return ChatPresentation._(
      conversation,
      group,
      bot,
      members,
      activity,
      messages,
      title,
    );
  }
  String get state => activity.state;
  bool get running => state != 'idle';
  bool get working => state != 'idle' && state != 'unknown';
  bool get waiting =>
      const {'waiting_approval', 'waiting_question', 'unknown'}.contains(state);
  List<Json> get memberAvatars =>
      members.map((m) => object(m['avatar'])).toList();
}

List<ChatMessage> visibleChatMessages(List<ChatMessage> messages) => messages
    .where(
      (m) =>
          m.kind != 'tool' &&
          !isProgressMessage(m) &&
          !(m.kind == 'commentary' &&
              '${m.content['text'] ?? ''}'.trim().isEmpty),
    )
    .toList();
