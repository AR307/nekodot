import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/commands.dart';
import 'package:nekodot_native/features/hermes_settings.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// Actual native UI + Node/Relay + official Hermes and model, not recorded data.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native command adapters and a real model reply', (tester) async {
    if (Platform.isWindows) await DesktopHost.initialize();
    final client = NekodotClient()..language = 'en';
    final botId = const String.fromEnvironment('QA_SECOND_BOT');
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

    Future<void> until(bool Function() ready, {int seconds = 90}) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 150));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(
        ready(),
        isTrue,
        reason: 'The real Hermes command journey timed out.',
      );
    }

    Future<void> tapReady(Finder finder) async {
      await until(() => finder.hitTestable().evaluate().isNotEmpty);
      await tester.tap(finder.hitTestable().first);
    }

    await until(() => client.online && client.node.bots.length >= 2);
    final conversationId =
        '${client.node.conversations.firstWhere((row) => row['kind'] == 'dm' && row['botId'] == botId)['conversationId']}';
    runApp(
      MaterialApp(
        theme: appTheme(Brightness.light),
        builder: (context, child) => Platform.isWindows
            ? WindowChrome(child: child!)
            : Ambient(child: child!),
        navigatorObservers: [nativeRoutes],
        home: HomePage(client: client),
      ),
    );
    await tapReady(find.byKey(ValueKey('conversation-$conversationId')));
    final input = find.byKey(const ValueKey('chat-input'));
    await until(() => input.evaluate().isNotEmpty);
    Future<void> typeMessage(String text) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(input);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.enterText(input, text);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<TextField>(input).controller!.text, text);
    }

    await client.loadMessages(conversationId);
    await until(
      () => client.node.activities[conversationId]?['state'] == 'idle',
    );
    List<Json> messages() => client.node.messages[conversationId] ?? [];
    final before = messages().map((row) => row['messageId']).toSet();
    final marker = 'NATIVE_COMMAND_${DateTime.now().millisecondsSinceEpoch}';
    bool streamed = false;
    void observe() {
      streamed |= messages().any(
        (row) =>
            !before.contains(row['messageId']) &&
            row['author']['type'] == 'bot' &&
            row['status'] == 'streaming' &&
            '${row['content']['text'] ?? ''}'.isNotEmpty,
      );
    }

    client.addListener(observe);
    await typeMessage(
      'Harmless acceptance test. Do not use tools. Reply with exactly $marker.',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tapReady(find.byTooltip('Send'));
    await until(
      () => messages().any(
        (row) =>
            !before.contains(row['messageId']) &&
            row['author']['type'] == 'bot' &&
            row['status'] == 'done' &&
            '${row['content']['text']}'.contains(marker),
      ),
      seconds: 240,
    );
    client.removeListener(observe);
    expect(streamed, isTrue);
    await until(
      () => client.node.activities[conversationId]?['state'] == 'idle',
    );
    await tester.pump(const Duration(milliseconds: 400));
    debugPrint('QA: real model reply completed and streamed');
    final modelReplies = messages()
        .where((row) => row['author']['type'] == 'bot')
        .length;
    final userTurns = messages()
        .where((row) => row['author']['type'] == 'user')
        .length;

    Future<void> command(String text, String expected) async {
      final old = messages().map((row) => row['messageId']).toSet();
      await typeMessage(text);
      await tester.pump(const Duration(milliseconds: 300));
      await tapReady(find.byTooltip('Send'));
      await until(
        () => messages().any(
          (row) =>
              !old.contains(row['messageId']) &&
              row['kind'] == 'system' &&
              '${row['content']['text']}'.startsWith(text) &&
              '${row['content']['text']}'.contains(expected),
        ),
      );
      await until(
        () => tester.widget<TextField>(input).controller!.text.isEmpty,
      );
    }

    await typeMessage('/his');
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<TextField>(input).controller!.text, '/his');
    debugPrint('QA: command search entered');
    await until(
      () =>
          find.byType(CommandPalette).evaluate().isNotEmpty &&
          find.text('/history').evaluate().isNotEmpty,
    );
    expect(find.text('App action'), findsOneWidget);
    await tapReady(find.widgetWithText(ListTile, '/history'));
    await command('/history', marker);
    expect(
      messages().where((row) => row['author']['type'] == 'bot').length,
      modelReplies,
    );
    expect(
      messages().where((row) => row['author']['type'] == 'user').length,
      userTurns,
    );
    debugPrint(
      'QA: /history read the actual Hermes transcript without a model turn',
    );
    if (Platform.isAndroid) {
      FocusManager.instance.primaryFocus?.unfocus();
      await until(() => tester.view.viewInsets.bottom == 0);
      await binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(milliseconds: 400));
      await binding.takeScreenshot('hermes-commands-history-android');
    }
    await command('/tools', 'Hermes tools (');
    await command('/tasks', 'No active subagents or processes');
    await command('/v', 'Hermes');
    await command('/reload-skills', 'skill');
    await typeMessage('/config');
    await tester.pump(const Duration(milliseconds: 250));
    await tapReady(find.byTooltip('Send'));
    await until(() => find.byType(HermesSettings).evaluate().isNotEmpty);
    final search = find.descendant(
      of: find.byType(HermesSettings),
      matching: find.byType(TextField),
    );
    await until(() => search.evaluate().isNotEmpty);
    await tester.enterText(search, 'compression.enabled');
    await until(() => find.byType(SwitchListTile).evaluate().isNotEmpty);
    expect(find.text('Hermes settings'), findsOneWidget);
    await tester.pageBack();
    await until(() => input.evaluate().isNotEmpty);

    final catalog = objects(
      (await client.rpc('commands.list', {'botId': botId}))['commands'],
    );
    expect(
      catalog.firstWhere((row) => row['name'] == '/new')['availability'],
      'not-integrated',
    );
    await typeMessage('/new');
    await until(() => find.byType(ExpansionTile).evaluate().isNotEmpty);
    await tapReady(find.byType(ExpansionTile));
    await until(
      () => find.widgetWithText(ListTile, '/new').evaluate().isNotEmpty,
    );
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '/new')).enabled,
      isFalse,
    );
    await typeMessage('');
    expect(
      messages().where((row) => row['author']['type'] == 'bot').length,
      modelReplies,
    );
    final ids = messages().map((row) => row['messageId']).toSet();
    await client.connect();
    await until(() => client.ready);
    await client.synchronize(client.selectedNodeId!);
    await client.loadMessages(conversationId);
    expect(messages().map((row) => row['messageId']).toSet(), ids);
    binding.reportData = {
      ...?binding.reportData,
      'realHermes': true,
      'streamedReply': streamed,
      'historyWithoutModelTurn': true,
      'tools': true,
      'agentsAlias': true,
      'versionAlias': true,
      'reloadSkills': true,
      'settingsNavigation': true,
      'unavailableClearlySeparated': true,
      'reconnectWithoutReplay': true,
      'catalog': {
        for (final status in ['available', 'app', 'terminal', 'not-integrated'])
          status: catalog.where((row) => row['availability'] == status).length,
      },
    };
    debugPrint('QA: actual native Hermes command adapters passed');
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 15)));
}
