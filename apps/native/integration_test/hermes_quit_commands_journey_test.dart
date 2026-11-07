import 'package:nekodot_native/data/chat_models.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// Windows exits before the driver returns: the external runner checks both the
/// actual process exit and the real server turn completing after this command.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('quit or background the client while the server keeps working', (
    tester,
  ) async {
    if (Platform.isWindows) await DesktopHost.initialize();
    final client = NekodotClient()..prefs.language = 'en';
    final botId = const String.fromEnvironment('QA_BOT');
    final login = await client.account.request(
      '/auth/login',
      method: 'POST',
      body: {
        'email': const String.fromEnvironment('QA_EMAIL'),
        'password': const String.fromEnvironment('QA_PASSWORD'),
      },
    );
    client.account.token = login['token'] as String;
    client.selectedNodeId = const String.fromEnvironment('QA_NODE');
    await client.bootstrap();
    addTearDown(client.dispose);
    Future<void> until(bool Function() ready) async {
      final end = DateTime.now().add(const Duration(minutes: 3));
      while (!ready() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 150));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(ready(), isTrue, reason: 'Real client quit journey timed out');
    }

    await until(() => client.online);
    final id =
        '${client.node.conversations.firstWhere((r) => r['kind'] == 'dm' && r['botId'] == botId)['conversationId']}';
    runApp(
      MaterialApp(
        theme: appTheme(Brightness.light),
        navigatorObservers: [nativeRoutes],
        home: HomePage(client: client),
      ),
    );
    final conversation = find.byKey(ValueKey('conversation-$id'));
    await until(() => conversation.hitTestable().evaluate().isNotEmpty);
    await tester.tap(conversation.hitTestable().first);
    final input = find.byKey(const ValueKey('chat-input'));
    await until(() => input.evaluate().isNotEmpty);
    Future<void> submit(String text) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(input);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.enterText(input, text);
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.widget<TextField>(input).controller!.text, text);
      final send = find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == 'Send' && w.onPressed != null,
      );
      await until(() => send.hitTestable().evaluate().isNotEmpty);
      await tester.tap(send.hitTestable().first);
    }

    final marker = 'CLIENT_QUIT_${DateTime.now().millisecondsSinceEpoch}';
    await submit('/new $marker');
    await until(() => tester.widget<TextField>(input).controller!.text.isEmpty);
    await submit(
      'Harmless lifecycle test. Run terminal exactly once with python -c "import time; time.sleep(25)" in foreground. After it returns reply exactly $marker. Do not use any other tools.',
    );
    List<ChatMessage> messages() => client.node.messages[id] ?? [];
    await until(
      () => messages().any((m) => m.kind == 'tool' && m.status == 'streaming'),
    );
    final approval = messages()
        .where((m) => m.kind == 'approval' && m.status == 'streaming')
        .firstOrNull;
    if (approval != null) {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 300));
      final allow = find.descendant(
        of: find.byKey(ValueKey(approval.messageId)),
        matching: find.text('Allow once'),
      );
      await tester.scrollUntilVisible(
        allow,
        240,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('chat-messages')),
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 60,
      );
      await tester.tap(allow.last);
      await until(
        () => !messages().any(
          (m) => m.kind == 'approval' && m.status == 'streaming',
        ),
      );
    }
    if (Platform.isWindows) {
      await File(const String.fromEnvironment('QA_QUIT_SIGNAL'))
          .writeAsString(jsonEncode({'conversationId': id, 'marker': marker}));
    }
    debugPrint('QA QUIT READY: $marker');
    await submit('/quit');
    await until(
      () => WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed,
    );
    if (Platform.isAndroid) {
      binding.reportData = {
        'androidBackgrounded': true,
        'marker': marker,
        'conversationId': id,
      };
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
