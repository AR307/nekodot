import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/data/node_data.dart';

void main() {
  test(
    'Streaming updates only its chat; completed replies update the sidebar',
    () {
      final node = NodeData();
      var chat = 0, otherChat = 0, sidebar = 0, metadata = 0;
      node.conversation('dm').addListener(() => chat++);
      node.conversation('other').addListener(() => otherChat++);
      node.summaries.addListener(() => sidebar++);
      node.addListener(() => metadata++);
      final message = {
        'messageId': 'reply',
        'conversationId': 'dm',
        'seq': 1,
        'createdAt': '2026-11-06T00:00:00Z',
        'kind': 'text',
        'status': 'streaming',
        'author': {'type': 'bot', 'id': 'dot'},
        'content': {'text': ''},
      };
      node.update({
        'type': 'event',
        'payload': {'seq': 1, 'kind': 'message.upserted', 'data': message},
      });
      final before = sidebar;
      node.update({
        'type': 'live',
        'payload': {
          'kind': 'delta',
          'conversationId': 'dm',
          'messageId': 'reply',
          'offset': 0,
          'text': '**Hello**',
        },
      });
      expect(node.messages['dm']!.single.content['text'], '**Hello**');
      expect(chat, 2);
      expect(sidebar, before);
      expect([otherChat, metadata], [0, 0]);
      node.update({
        'type': 'event',
        'payload': {
          'seq': 2,
          'kind': 'message.upserted',
          'data': {
            ...message,
            'status': 'done',
            'content': {'text': '**Hello**'},
          },
        },
      });
      expect(node.messages['dm']!.single.status, 'done');
      expect(sidebar, before + 1);
      expect([otherChat, metadata], [0, 0]);
      node.dispose();
    },
  );
}
