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
  final List<ChatMessage> messages, turn;
  final List<List<ChatMessage>> items;
  final String title;
  ChatPresentation._(
    this.conversation,
    this.group,
    this.bot,
    this.members,
    this.activity,
    this.messages,
    this.turn,
    this.items,
    this.title,
  );
  factory ChatPresentation(
    NodeData node,
    Json conversation, {
    required bool focus,
  }) {
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
    final messages = (node.messages[conversation['conversationId']] ?? [])
        .where(
          (row) =>
              (!focus || row.kind != 'tool') &&
              // A text segment that ended empty when a tool started has nothing to show.
              !(row.kind == 'commentary' &&
                  '${row.content['text'] ?? ''}'.trim().isEmpty),
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

    final all =
        node.messages[conversation['conversationId']] ?? const <ChatMessage>[];
    final start = all.lastIndexWhere((m) => m.author.type == 'user');
    final turn = all
        .skip(start + 1)
        .where(
          (m) =>
              m.author.type == 'bot' &&
              (bot == null || m.author.id == bot['botId']),
        )
        .toList();
    return ChatPresentation._(
      conversation,
      group,
      bot,
      members,
      activity,
      messages,
      turn,
      groupMessages(messages),
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

bool isWorkGroup(List<ChatMessage> item) => item.any(
  (m) =>
      m.kind == 'tool' ||
      (m.kind == 'approval' &&
          m.status != 'streaming' &&
          const {'once', 'session', 'always'}.contains(m.content['choice'])),
);
List<List<ChatMessage>> groupMessages(List<ChatMessage> messages) {
  // Steps fold together: the tool calls in a row and what the Bot wrote
  // between them, until it writes its reply or asks you something.
  final items = <List<ChatMessage>>[];
  // An approval the user allowed is one of the steps: it runs inside the box.
  bool allowed(ChatMessage m) =>
      m.kind == 'approval' &&
      m.status != 'streaming' &&
      const {'once', 'session', 'always'}.contains(object(m.content)['choice']);
  bool step(ChatMessage m) => m.kind == 'tool' || allowed(m);
  for (final m in messages) {
    if (isProgressMessage(m)) continue;
    final last = items.lastOrNull;
    if (step(m) &&
        last != null &&
        step(last.first) &&
        last.first.author.id == m.author.id) {
      last.add(m);
    } else {
      items.add([m]);
    }
  }
  for (var i = items.length - 1; i >= 0; i--) {
    if (items[i].length > 1 && !isWorkGroup(items[i])) {
      items.replaceRange(i, i + 1, [
        for (final m in items[i]) [m],
      ]);
    }
  }

  return items;
}
