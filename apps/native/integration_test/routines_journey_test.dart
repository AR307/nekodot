import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/chat.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/routines.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// Opt-in candidate UI against a real isolated Node, native Hermes and model.
/// Public webhook calls use the URL supplied by the real Relay. No replay server.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('chat creation, secure delivery, public execution and controls', (
    tester,
  ) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final client = NekodotClient();
    final nodeId = const String.fromEnvironment('QA_NODE');
    final botId = const String.fromEnvironment('QA_BOT');
    final conversationId = const String.fromEnvironment('QA_CONVERSATION');
    final name = 'Candidate routine ${DateTime.now().millisecondsSinceEpoch}';
    const marker = 'ROUTINE_NATIVE_UI_OK';

    Future<void> until(bool Function() ready, {int seconds = 180}) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(ready(), isTrue, reason: 'Real routine UI journey timed out.');
    }

    Future<void> tap(Finder finder) async {
      if (finder.evaluate().isEmpty) {
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.scrollUntilVisible(
          finder,
          250,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await until(() {
        if (finder.evaluate().isEmpty) return false;
        final widget = tester.widget(finder);
        return widget is! ButtonStyleButton || widget.onPressed != null;
      });
      await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 350));
    }

    Future<void> inspect(String stage) async {
      debugPrint('QA routine view: $stage');
      if (const bool.fromEnvironment('QA_INSPECT')) {
        await tester.pump(const Duration(seconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 20)),
        );
      }
    }

    // Do not overwrite the installed user's login credentials with a QA session.
    await tester.runAsync(() async {
      final session = await client.request(
        '/auth/login',
        method: 'POST',
        body: {
          'email': const String.fromEnvironment('QA_EMAIL'),
          'password': const String.fromEnvironment('QA_PASSWORD'),
        },
      );
      client.token = session['token'] as String;
      await client.bootstrap();
      await client.selectNode(nodeId);
    });
    await until(() => client.online && client.node.conversations.isNotEmpty);
    runApp(
      MaterialApp(
        theme: appTheme(Brightness.light),
        navigatorObservers: [nativeRoutes],
        builder: (context, child) =>
            Theme.of(context).platform == TargetPlatform.windows
            ? WindowChrome(child: child!)
            : Ambient(child: child!),
        home: HomePage(client: client),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tap(find.byKey(ValueKey('conversation-$conversationId')));
    await until(
      () => find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty,
    );
    await tester.enterText(
      find.byKey(const ValueKey('chat-input')),
      '请阅读 nekodot-routines skill，通过 hermes routine create 真正创建一个纯 webhook 例行任务。'
      '名字必须为 "$name"，事件类型仅 scan，不要创建 cron。固定提示必须是：'
      '“只回复 message 字段的内容并在末尾加 $marker。不要使用工具。事件：{__raw__}”。'
      '创建后引导我打开卡片保密交付，不要向我索取密钥。',
    );
    await tester.pump();
    await tap(find.byTooltip('发送'));
    Json? routine;
    await until(() {
      final card = (client.node.messages[conversationId] ?? [])
          .where((m) => m['kind'] == 'routine' && m['content']['name'] == name)
          .firstOrNull;
      if (card != null) {
        routine = object(card['content']);
      }
      return routine != null &&
          client.node.activities[conversationId]?['state'] == 'idle';
    }, seconds: 300);
    final routineId = '${routine!['routineId']}';
    final target = {'botId': botId, 'routineId': routineId};
    await tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is RoutineCard && widget.content['routineId'] == routineId,
      ),
    );
    await until(() => find.text('确认接入并保密交付').evaluate().isNotEmpty);
    await inspect('details');
    await tap(find.widgetWithText(OutlinedButton, '复制 URL'));
    final url = (await tester.runAsync(
      () => Clipboard.getData(Clipboard.kTextPlain),
    ))!.text!;
    expect(Uri.parse(url).scheme, 'https');
    await tap(find.widgetWithText(FilledButton, '确认接入并保密交付'));
    await until(() => find.text('暂停 Webhook').evaluate().isNotEmpty);
    await tap(find.widgetWithText(OutlinedButton, '复制密钥'));
    final oldSecret = (await tester.runAsync(
      () => Clipboard.getData(Clipboard.kTextPlain),
    ))!.text!;
    expect(oldSecret.length > 30, isTrue);
    expect(
      jsonEncode(client.node.messages[conversationId]).contains(oldSecret),
      isFalse,
    );
    await tester.runAsync(() => Clipboard.setData(ClipboardData(text: url)));
    debugPrint('QA secure delivery and clipboard verified');

    await tap(find.widgetWithText(OutlinedButton, '测试唤醒'));
    await until(
      () => find.widgetWithText(FilledButton, '发送').evaluate().isNotEmpty,
    );
    await tap(find.widgetWithText(FilledButton, '发送'));
    await until(() => find.byType(AlertDialog).evaluate().isEmpty);
    await until(() => find.byType(LinearProgressIndicator).evaluate().isEmpty);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('routine-test-receipt')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('routine-test-receipt')),
          )
          .data,
      startsWith('HTTP 202'),
    );
    Json state = {};
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(deadline)) {
      state = (await tester.runAsync(
        () => client.rpc('routines.get', target),
      ))!;
      if (objects(state['executions']).any((e) => e['state'] != 'running')) {
        break;
      }
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
    }
    final execution = objects(state['executions']).first;
    expect(execution['state'], 'completed');
    expect('${execution['text']}'.contains(marker), isTrue);
    expect('${execution['sessionId']}'.isNotEmpty, isTrue);
    await tap(find.byTooltip('刷新'));
    await tester.pump(const Duration(seconds: 2));
    await tap(find.byKey(ValueKey(execution['executionId'])));
    await tester.scrollUntilVisible(
      find.byWidgetPredicate(
        (w) =>
            w is SelectableText &&
            (w.data?.startsWith('Hermes session:') ?? false),
      ),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await inspect('completed');

    await tap(find.widgetWithText(OutlinedButton, '暂停 Webhook'));
    await until(() => find.text('恢复 Webhook').evaluate().isNotEmpty);
    Future<http.Response> fire(String secret) => http.post(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $secret',
        'Content-Type': 'application/json',
        'X-Request-ID': uid(),
      },
      body: jsonEncode({'event_type': 'scan', 'message': 'paused acceptance'}),
    );
    expect((await tester.runAsync(() => fire(oldSecret)))!.statusCode, 403);
    await tap(find.widgetWithText(OutlinedButton, '更换密钥'));
    await tap(find.widgetWithText(FilledButton, '更换'));
    await tap(find.widgetWithText(OutlinedButton, '恢复 Webhook'));
    await until(() => find.text('暂停 Webhook').evaluate().isNotEmpty);
    expect((await tester.runAsync(() => fire(oldSecret)))!.statusCode, 401);
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => client.loadMessages(conversationId));
    expect(
      (client.node.messages[conversationId] ?? []).any(
        (m) =>
            m['kind'] == 'routine' &&
            m['content']['routineId'] == routineId &&
            m['content']['card'] == 'credentials',
      ),
      isTrue,
    );
    expect(
      (client.node.messages[conversationId] ?? []).any(
        (m) => m['content']['routine']?['sessionId'] == execution['sessionId'],
      ),
      isTrue,
    );
    expect(find.byType(ChatPage), findsOneWidget);
    await inspect('chat-result');
    binding.reportData = {
      'realModel': true,
      'publicHttps': true,
      'secureDelivery': true,
      'paused': true,
      'rotated': true,
      'nativeSession': execution['sessionId'],
    };
    await tester.pumpWidget(const SizedBox.shrink());
    client.dispose();
  });
}
