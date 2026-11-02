import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// The real OS save dialogs are operated externally; no file picker is mocked.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('save native transcripts through Windows system dialogs', (
    tester,
  ) async {
    expect(Platform.isWindows, isTrue);
    await DesktopHost.initialize();
    final client = NekodotClient()..language = 'en';
    final botId = const String.fromEnvironment('QA_BOT');
    final directory = const String.fromEnvironment('QA_SAVE_DIR');
    expect(directory, isNotEmpty);
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
    Future<void> until(bool Function() ready) async {
      final end = DateTime.now().add(const Duration(minutes: 4));
      while (!ready() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 150));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(ready(), isTrue, reason: 'Real Windows save journey timed out');
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
      await until(
        () => tester.widget<TextField>(input).controller!.text.isEmpty,
      );
    }

    final original = (await client.rpc('sessions.list', {
      'botId': botId,
    }))['currentSessionId'];
    final marker = 'WINDOWS_EXPORT_${DateTime.now().millisecondsSinceEpoch}';
    await submit('/new $marker');
    await submit('Do not use tools. Reply exactly $marker.');
    await until(
      () => (client.node.messages[id] ?? []).any(
        (m) =>
            m['author']['type'] == 'bot' &&
            m['kind'] == 'text' &&
            m['status'] == 'done' &&
            '${m['content']['text']}'.contains(marker),
      ),
    );
    final saved = <String>[];
    for (final format in ['json', 'md', 'html']) {
      final name = '原生会话-$format.$format';
      await submit('/save $format $name');
      debugPrint('QA SAVE DIALOG: $format');
      final file = File('$directory/$name');
      await until(file.existsSync);
      final text = await file.readAsString();
      expect(text, contains(marker));
      if (format == 'json') jsonDecode(text);
      if (format == 'html') expect(text, contains('<html'));
      saved.add(format);
      await tester.pump(const Duration(milliseconds: 300));
    }
    await submit('/resume $original');
    binding.reportData = {
      'realHermes': true,
      'windowsSystemSave': saved,
      'chineseFilenames': true,
      'nativeExportContentsChecked': true,
    };
    debugPrint(
      'QA: Windows actual system dialogs saved JSON, Markdown and HTML',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 15)));
}
