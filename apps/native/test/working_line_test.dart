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
ChatMessage step(String tool, {String context = '', bool running = false}) =>
    ChatMessage.fromJson({
      'messageId': 'work',
      'conversationId': 'dm',
      'seq': 0,
      'createdAt': '2026-11-06T00:00:00Z',
      'author': {'type': 'bot', 'id': 'bot'},
      'kind': 'tool',
      'status': running ? 'streaming' : 'done',
      'content': {'tool': tool, 'preview': '', 'context': context},
    });

void main() {
  final c = NekodotClient();

  test('The line above the composer is the Bot’s own words', () {
    expect(workingLine(c, 'Lumi', []), 'Lumi 正在思考');
    expect(
      workingLine(c, 'Lumi', [
        said('正在查看推文。'),
        step('browser_navigate', context: 'https://x.com', running: true),
      ]),
      'Lumi 正在查看推文',
    );
    // Between steps it keeps the last thing it said.
    expect(
      workingLine(c, 'Lumi', [said('正在查看推文'), step('browser_navigate')]),
      'Lumi 正在查看推文',
    );
    // One line may announce several steps.
    expect(
      workingLine(c, 'Lumi', [
        said('正在查看推文'),
        step('browser_navigate'),
        step('terminal', context: 'python -c "print(1)"', running: true),
      ]),
      'Lumi 正在查看推文',
    );
    // Before it has said anything, the running step reads as Hermes labels it.
    expect(
      workingLine(c, 'Lumi', [
        step('terminal', context: 'python -c "print(1)"', running: true),
      ]),
      'Lumi 正在运行命令 python -c "print(1)"',
    );
    expect(workingLine(c, 'Lumi', [said('我先读一下首页')]), 'Lumi 正在思考');
    expect(isProgressMessage(said('好的，我先打开网页，之后告诉你内容。')), isFalse);
    expect(isProgressMessage(said('正在打开浏览器')), isTrue);
    final mixed = said('好的，我先计算。\n\n正在运行 Python 计算。');
    expect(visibleMessageText(mixed), '好的，我先计算。');
    expect(workingLine(c, 'Lumi', [mixed]), 'Lumi 正在运行 Python 计算');
    expect(isProgressMessage(mixed), isFalse);
  });

  test('English reads as a sentence', () async {
    c.prefs.language = 'en';
    expect(
      workingLine(c, 'Lumi', [said('Checking the tweets.')]),
      'Lumi is checking the tweets',
    );
    expect(
      workingLine(c, 'Lumi', [
        step('web_search', context: 'nekodot', running: true),
      ]),
      'Lumi is searching the web nekodot',
    );
    expect(workingLine(c, 'Lumi', [said('Done reading')]), 'Lumi is thinking');
  });
}
