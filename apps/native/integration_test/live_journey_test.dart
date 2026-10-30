import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/main.dart';
import 'package:nekodot_native/ui/design.dart';

/// Opt-in real HTTPS/model/screen journey. Credentials come only from a private
/// --dart-define-from-file passed to the test build, never from this source.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const email = String.fromEnvironment('QA_EMAIL');
  const password = String.fromEnvironment('QA_PASSWORD');
  const conversationId = String.fromEnvironment('QA_CONVERSATION');
  const nodeId = String.fromEnvironment('QA_NODE');
  const withScreen = bool.fromEnvironment('QA_SCREEN', defaultValue: true);
  const inspect = bool.fromEnvironment('QA_INSPECT');
  const inputTest = bool.fromEnvironment('QA_SCREEN_INPUT');

  testWidgets('native login, real streaming reply, screen and Android back', (
    tester,
  ) async {
    expect(
      email.isNotEmpty && password.isNotEmpty,
      isTrue,
      reason: 'Supply a dedicated private QA account.',
    );
    expect(
      conversationId.isNotEmpty && nodeId.isNotEmpty,
      isTrue,
      reason: 'Select an isolated QA node and conversation.',
    );
    final client = NekodotClient();
    await client.vault.delete(key: 'nekodot-session');
    Future<void> until(bool Function() ready, {int seconds = 60}) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      final reported = <String>{};
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        for (final element in find.byType(ErrorNotice).evaluate()) {
          final message = (element.widget as ErrorNotice).text;
          if (message.isNotEmpty && reported.add(message)) {
            debugPrint('QA visible error: $message');
          }
        }
      }
      if (!ready()) {
        for (final element in find.byType(ErrorNotice).evaluate()) {
          debugPrint(
            'QA visible error: ${(element.widget as ErrorNotice).text}',
          );
        }
      }
      expect(
        ready(),
        isTrue,
        reason: 'Native journey did not reach its expected state.',
      );
    }

    runApp(NekodotApp(client: client));
    await until(
      () => find.byKey(const ValueKey('auth-email')).evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(seconds: 2));
    final notice = find.widgetWithText(TextButton, '继续');
    if (notice.evaluate().isNotEmpty) {
      await tester.tap(notice);
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.enterText(find.byKey(const ValueKey('auth-email')), email);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      password,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('auth-email')))
          .controller!
          .text,
      email,
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, '登录'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await until(() => client.ready);
    await client.selectNode(nodeId);
    debugPrint('QA: authenticated real remote account');
    await until(() => client.online && client.node.conversations.isNotEmpty);
    final conversation = find.byKey(ValueKey('conversation-$conversationId'));
    await tester.scrollUntilVisible(
      conversation,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(conversation);
    await tester.pump(const Duration(seconds: 1));
    await until(
      () => find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty,
    );
    final input = find.byKey(const ValueKey('chat-input'));
    const marker = 'NEKODOT_NATIVE_LIVE_OK';
    await client.loadMessages(conversationId);
    final before = (client.node.messages[conversationId] ?? [])
        .map((m) => m['messageId'])
        .toSet();
    bool streamed = false;
    void observeReply() {
      streamed |= (client.node.messages[conversationId] ?? []).any(
        (m) =>
            !before.contains(m['messageId']) &&
            m['author']['type'] == 'bot' &&
            m['kind'] == 'text' &&
            m['status'] == 'streaming' &&
            '${m['content']['text']}'.isNotEmpty,
      );
    }

    client.addListener(observeReply);
    await tester.enterText(
      input,
      'This is a harmless native-client acceptance test. Do not use tools. Reply with exactly $marker.',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await until(
      () => (client.node.messages[conversationId] ?? []).any(
        (m) => !before.contains(m['messageId']),
      ),
    );
    await until(
      () => (client.node.messages[conversationId] ?? []).any(
        (m) =>
            !before.contains(m['messageId']) &&
            m['author']['type'] == 'bot' &&
            m['kind'] == 'text' &&
            m['status'] == 'done' &&
            '${m['content']['text']}'.contains(marker),
      ),
      seconds: 180,
    );
    expect(client.node.activities[conversationId]?['state'], 'idle');
    client.removeListener(observeReply);
    expect(
      streamed,
      isTrue,
      reason: 'The actual Node must deliver streaming text, not only a final snapshot.',
    );
    debugPrint('QA: real model response completed');
    await tester.pump(const Duration(seconds: 2));
    if (inspect) await tester.pump(const Duration(seconds: 15));

    if (withScreen) {
      await tester.tap(find.byTooltip('屏幕'));
      await tester.pump(const Duration(seconds: 1));
      await until(
        () =>
            find.widgetWithText(FilledButton, '启动屏幕').evaluate().isNotEmpty ||
            find.widgetWithText(FilledButton, '接管').evaluate().isNotEmpty,
      );
      final startScreen = find.widgetWithText(FilledButton, '启动屏幕');
      if (startScreen.evaluate().isNotEmpty) {
        await tester.tap(startScreen);
        await tester.pump();
      }
      await until(
        () => find
            .byType(RawImage)
            .evaluate()
            .any((e) => (e.widget as RawImage).image != null),
        seconds: 90,
      );
      expect(find.text('Bot 控制中'), findsOneWidget);
      debugPrint('QA: native RFB image decoded');
      await tester.pump(const Duration(seconds: 2));
      if (inspect) await tester.pump(const Duration(seconds: 30));
      await tester.tap(find.byTooltip('键盘'));
      await tester.pump(const Duration(milliseconds: 400));
      final keyboard = find.byKey(const ValueKey('screen-keyboard'));
      expect(tester.widget<TextField>(keyboard).enabled, isFalse);
      await tester.tap(find.widgetWithText(FilledButton, '接管'));
      await until(() => find.text('你正在控制').evaluate().isNotEmpty);
      if (inputTest) {
        // Prepare a harmless focused form on the dedicated Bot display first.
        await tester.ensureVisible(keyboard);
        await tester.enterText(keyboard, 'NEKODOT_NATIVE_INPUT_OK');
        await tester.ensureVisible(find.widgetWithText(TextButton, '输入'));
        await tester.tap(find.widgetWithText(TextButton, '输入'));
        await tester.pump(const Duration(seconds: 3));
        debugPrint('QA: native keyboard input submitted');
        if (inspect) await tester.pump(const Duration(seconds: 30));
      }
      await tester.tap(find.widgetWithText(FilledButton, '交还'));
      await until(() => find.text('Bot 控制中').evaluate().isNotEmpty);
      await tester.pageBack();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('chat-input')), findsOneWidget);
    }
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));
    expect(conversation, findsOneWidget);
    binding.reportData = {
      'login': true,
      'streamedReply': true,
      'screen': withScreen,
      'inputSubmitted': inputTest,
    };
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
