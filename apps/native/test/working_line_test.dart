import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/chat_models.dart';
import 'package:nekodot_native/features/work.dart';

ChatMessage said(String text) => ChatMessage.fromJson({
  'messageId': 'work',
  'conversationId': 'dm',
  'seq': 0,
  'createdAt': '2026-11-06T00:00:00Z',
  'author': {'type': 'bot', 'id': 'bot'},
  'kind': 'commentary',
  'status': 'done',
  'content': {'text': text},
});

void main() {
  final c = NekodotClient();

  test(
    'Reception stays short and progress does not replace acknowledgements',
    () {
      expect(workingLine(c, 'Lumi'), 'Lumi · 回复中');
      expect(isProgressMessage(said('好的，我先打开网页，之后告诉你内容。')), isFalse);
      expect(isProgressMessage(said('正在打开浏览器')), isTrue);
      final mixed = said('好的，我先计算。\n\n正在运行 Python 计算。');
      expect(visibleMessageText(mixed), '好的，我先计算。');
      expect(isProgressMessage(mixed), isFalse);
    },
  );

  test('English reception stays short', () async {
    c.prefs.language = 'en';
    expect(workingLine(c, 'Lumi'), 'Lumi · Reply');
  });
}
