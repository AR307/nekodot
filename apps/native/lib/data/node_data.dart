import 'chat_models.dart';

import 'package:flutter/foundation.dart';

import 'json.dart';
import 'flow.dart';

class NodeData extends ChangeNotifier {
  final summaries = ValueNotifier<int>(0);
  final _conversations = <String, ValueNotifier<int>>{};
  ValueNotifier<int> conversation(String id) =>
      _conversations.putIfAbsent(id, () => ValueNotifier<int>(0));
  void changed(String id, {bool summary = false}) {
    conversation(id).value++;
    if (summary) summaries.value++;
  }

  List<Json> bots = [], groups = [], conversations = [];

  /// What the node can do: host (server/desktop), Bot screens and desktop control.
  Json capabilities = {};
  final Map<String, List<ChatMessage>> messages = {};
  final _messageReaders = <String, int>{};
  final viewports = <String, ({int oldestSeq, int since, double offset})>{};

  void retainMessages(String id) {
    _messageReaders[id] = (_messageReaders[id] ?? 0) + 1;
    messages.putIfAbsent(id, () => []);
  }

  void releaseMessages(String id) {
    final remaining = (_messageReaders[id] ?? 1) - 1;
    if (remaining > 0) {
      _messageReaders[id] = remaining;
    } else {
      _messageReaders.remove(id);
      messages.remove(id);
    }
  }

  /// Each conversation's newest words as the node last reported them, so the
  /// list can preview a conversation whose messages are not loaded.
  Map<String, ChatMessage> latest = {};
  final Map<String, ConversationActivity> activities = {};
  final Map<String, Json> screens = {};
  final Map<String, FlowSnapshot> flows = {};
  int seq = 0;
  bool online = false, syncing = false;
  final List<Json> buffer = [];
  void notifySnapshot() {
    notifyListeners();
    summaries.value++;
    for (final c in _conversations.values) {
      c.value++;
    }
  }

  void snapshot(Json data) {
    bots = objects(data['bots']);
    groups = objects(data['groups']);
    conversations = objects(data['conversations']);
    latest = {
      for (final message in objects(data['latest']))
        message['conversationId'] as String: ChatMessage.fromJson(message),
    };
    seq = data['headSeq'] as int;
    capabilities = object(data['node'] ?? {});
    flows.clear();
    for (final value in objects(data['flows'])) {
      final flow = FlowSnapshot.fromJson(value);
      flows[flow.conversationId] = flow;
    }
  }

  void update(Json frame) {
    final p = object(frame['payload']);
    if (frame['type'] == 'event') {
      if ((p['seq'] as int) <= seq) return;
      seq = p['seq'] as int;
      final data = object(p['data']);
      switch (p['kind']) {
        case 'flow.changed':
          final id = data['conversationId'] as String;
          final previous = flows[id];
          if (previous == null || previous.seq < (data['seq'] as int)) {
            flows[id] = FlowSnapshot.fromJson(data, previous);
            changed(id);
          }
        case 'bot.upserted':
          _upsert(bots, data, 'botId');
          notifyListeners();
        case 'group.upserted':
          _upsert(groups, data, 'groupId');
          notifyListeners();
        case 'conversation.upserted':
          _upsert(conversations, data, 'conversationId');
          notifyListeners();
        case 'bot.archived':
          bots.removeWhere((x) => x['botId'] == data['botId']);
          notifyListeners();
        case 'group.archived':
          groups.removeWhere((x) => x['groupId'] == data['groupId']);
          notifyListeners();
        case 'message.upserted':
          final message = ChatMessage.fromJson(data);
          final list = messages[message.conversationId];
          if (list != null) {
            final index = list.indexWhere(
              (m) => m.messageId == message.messageId,
            );
            if (index < 0) {
              list.add(message);
            } else {
              list[index] = message;
            }
          }
          if ((message.kind == 'text' || message.kind == 'commentary') &&
              '${message.content['text'] ?? ''}'.trim().isNotEmpty &&
              message.seq >= (latest[message.conversationId]?.seq ?? 0)) {
            latest[message.conversationId] = message;
          }
          changed(data['conversationId'] as String, summary: true);
      }
    } else if (p['kind'] == 'activity') {
      activities[p['conversationId'] as String] = ConversationActivity.fromJson(
        p,
      );
      changed(p['conversationId'] as String, summary: true);
    } else if (p['kind'] == 'screen') {
      final s = object(p['status']);
      screens[s['botId'] as String] = s;
      notifyListeners();
    } else if (p['kind'] == 'delta') {
      final m = messages[p['conversationId']]
          ?.where((x) => x.messageId == p['messageId'])
          .firstOrNull;
      if (m == null || m.status != 'streaming') return;
      final content = object(m.content),
          text = content['text'] as String,
          offset = p['offset'] as int;
      if (offset > text.length) return;
      final delta = p['text'] as String, skip = text.length - offset;
      if (skip < delta.length) {
        m.content = {...content, 'text': text + delta.substring(skip)};
        changed(p['conversationId'] as String);
      }
    }
  }

  void _upsert(List<Json> list, Json data, String key) {
    final i = list.indexWhere((x) => x[key] == data[key]);
    if (i < 0) {
      list.add(data);
    } else {
      list[i] = data;
    }
  }

  @override
  void dispose() {
    summaries.dispose();
    for (final c in _conversations.values) {
      c.dispose();
    }
    super.dispose();
  }
}
