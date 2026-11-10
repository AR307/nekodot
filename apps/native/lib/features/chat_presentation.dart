import '../data/chat_models.dart';
import '../data/client.dart';
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
  bool get thinking {
    final tail = messages.lastOrNull;
    return (state == 'thinking' || state == 'tool') &&
        (tail?.status != 'streaming' ||
            tail?.kind == 'tool' ||
            (tail != null && isProgressMessage(tail)));
  }

  String? status(NekodotClient c) => !c.online
      ? c.tr('离线', 'Offline')
      : activity.connection == 'reconnecting'
      ? c.tr('重连中', 'Reconnecting')
      : activity.stalled
      ? c.tr('可能卡住', 'No recent progress')
      : switch (state) {
          'thinking' => c.tr('回复中', 'Replying'),
          'tool' => c.tr('工具运行中', 'Using tools'),
          'waiting_approval' => c.tr('等你确认', 'Needs your OK'),
          'waiting_question' => c.tr('等你回答', 'Needs your answer'),
          'unknown' => c.tr('执行中断，待确认', 'Execution interrupted'),
          _ => null,
        };
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
