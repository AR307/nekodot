import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/bot_editor.dart';
import 'package:nekodot_native/ui/design.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('create a real Bot after correcting a named model error', (
    tester,
  ) async {
    final client = NekodotClient();
    final login = await client.request(
      '/auth/login',
      method: 'POST',
      body: {
        'email': const String.fromEnvironment('QA_EMAIL'),
        'password': const String.fromEnvironment('QA_PASSWORD'),
      },
    );
    client.token = login['token'] as String;
    client.selectedNodeId = const String.fromEnvironment('QA_NODE');
    await client.bootstrap();
    addTearDown(client.dispose);

    Future<void> until(bool Function() done, {int seconds = 120}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!done() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 200));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(done(), isTrue, reason: 'Real Bot creation did not finish.');
    }

    Future<void> show(Finder finder, {double delta = 220}) async {
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          finder,
          delta,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await Scrollable.maybeOf(tester.element(finder))?.position
          .ensureVisible(tester.renderObject(finder), alignment: .5);
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> fill(String label, String value, {double delta = 220}) async {
      final field = find.descendant(
        of: find.widgetWithText(LabeledField, label),
        matching: find.byType(TextField),
      );
      await show(field, delta: delta);
      await tester.enterText(field, value);
      await tester.pump(const Duration(milliseconds: 200));
    }

    Future<void> save() async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 300));
      await show(find.text('保存'));
      await until(() {
        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '保存'),
        );
        return button.onPressed != null;
      });
      await tester.tap(find.text('保存'));
      await tester.pump(const Duration(milliseconds: 400));
    }

    await until(() => client.online && client.node.bots.isNotEmpty);
    final model = '${client.node.bots.first['model']}';
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final displayName = '创建验收小鱼-$stamp';
    final otherBotId = client.node.bots.first['botId'];
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: appTheme(Brightness.light, glass: true),
        builder: (_, child) => Ambient(child: child!),
        home: const Scaffold(
          body: Center(child: Text('Bot creation acceptance')),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => BotEditor(client: client)),
    );
    await until(
      () =>
          find.byType(BotEditor).evaluate().isNotEmpty &&
          find.byType(Scrollable).evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await fill('名称', displayName);
    await tester.tap(find.text('高级').last);
    await tester.pump(const Duration(milliseconds: 300));
    final handleField = find.descendant(
      of: find.widgetWithText(LabeledField, '@handle'),
      matching: find.byType(TextField),
    );
    await show(handleField);
    expect(tester.widget<TextField>(handleField).controller!.text, displayName);
    debugPrint('QA: Chinese handle follows the name without manual input.');
    await save();
    await until(
      () => find.textContaining('params.model').evaluate().isNotEmpty,
    );
    expect(find.byType(BotEditor), findsOneWidget);
    debugPrint('QA: missing model named; form and automatic handle retained.');
    // Windows has no device screenshot; the Android run takes it.
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await binding.takeScreenshot('bot-create-missing-model');
    }
    await fill('模型', model, delta: -220);
    await save();
    await until(() => find.byType(BotEditor).evaluate().isEmpty);
    await until(
      () => client.node.bots.any((bot) => bot['displayName'] == displayName),
    );
    final bot = client.node.bots.firstWhere(
      (bot) => bot['displayName'] == displayName,
    );
    expect(bot['displayName'], displayName);
    expect(bot['handle'], displayName);
    final conversation = client.node.conversations.firstWhere(
      (row) => row['kind'] == 'dm' && row['botId'] == bot['botId'],
    );
    final conversationId = '${conversation['conversationId']}';
    await client.loadMessages(conversationId);
    debugPrint('QA: native Bot created; checking real Hermes welcome.');
    await until(() {
      final messages = client.node.messages[conversationId] ?? [];
      return messages.any(
        (message) =>
            message['kind'] == 'text' &&
            message['author']['type'] == 'bot' &&
            message['content']['welcome'] == true &&
            message['status'] == 'done' &&
            '${message['content']['text']}'.trim().isNotEmpty,
      );
    }, seconds: 180);
    debugPrint('QA: real Hermes welcome completed.');
    final sessions = await client.rpc('sessions.list', {'botId': bot['botId']});
    expect(sessions['currentSessionId'], isNotNull);
    final group = await client.rpc('groups.create', {
      'name': '默认代号群聊-$stamp',
      'botIds': [otherBotId, bot['botId']],
      'leadBotId': otherBotId,
    });
    final groupId = group['group']['groupId'];
    await until(
      () => client.node.conversations.any((row) => row['groupId'] == groupId),
    );
    final groupConversation = client.node.conversations.firstWhere(
      (row) => row['groupId'] == groupId,
    );
    final groupConversationId = '${groupConversation['conversationId']}';
    await client.loadMessages(groupConversationId);
    await client.rpc('messages.send', {
      'conversationId': groupConversationId,
      'clientMsgId': uid(),
      'text':
          '@${bot['handle']} 只回复 NEKODOT_DEFAULT_HANDLE_GROUP_OK，不要提及其他成员，不要使用工具。',
    });
    await until(
      () => (client.node.messages[groupConversationId] ?? []).any(
        (message) =>
            message['kind'] == 'text' &&
            message['author']['type'] == 'bot' &&
            message['author']['id'] == bot['botId'] &&
            message['status'] == 'done' &&
            '${message['content']['text']}'.trim().isNotEmpty,
      ),
      seconds: 180,
    );
    binding.reportData = {
      'nativeBotCreated': true,
      'chineseDisplayNamePreserved': true,
      'handleDerivedFromChineseNameWithoutManualInput': true,
      'chineseGroupMentionRoutedToCreatedBot': true,
      'missingModelNamedWithoutLosingDraft': true,
      'realHermesWelcomeCompleted': true,
      'model': model,
      'nodeId': client.selectedNodeId,
      'botId': bot['botId'],
      'sessionId': sessions['currentSessionId'],
      'device': 'NekodotNativePhase3 Android emulator',
      'physicalAndroidDeviceTested': false,
    };
    debugPrint('QA: native Bot created and real Hermes welcome completed.');
  });
}
