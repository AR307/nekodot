import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/data/node_data.dart';

void main() {
  test('unopened chats keep their sidebar preview, not a message history', () {
    final node = NodeData();
    for (var i = 1; i <= 100; i++) {
      node.update({
        'type': 'event',
        'payload': {
          'seq': i,
          'kind': 'message.upserted',
          'data': {
            'messageId': 'reply-$i',
            'conversationId': 'background',
            'seq': i,
            'createdAt': '2026-11-07T00:00:00Z',
            'kind': 'text',
            'status': 'done',
            'author': {'type': 'bot', 'id': 'dot'},
            'content': {'text': 'Reply $i'},
          },
        },
      });
    }
    expect(node.messages, isEmpty);
    expect(node.latest['background']!.content['text'], 'Reply 100');
    node.retainMessages('background');
    final loaded = node.messages['background'];
    node.retainMessages('background');
    node.releaseMessages('background');
    expect(identical(node.messages['background'], loaded), isTrue);
    node.releaseMessages('background');
    expect(node.messages, isEmpty);
    expect(node.latest['background']!.content['text'], 'Reply 100');
    node.dispose();
  });
  test(
    'Streaming updates only its chat; completed replies update the sidebar',
    () {
      final node = NodeData();
      node.retainMessages('dm');
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
