import 'package:nekodot_native/data/chat_models.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/commands.dart';
import 'package:nekodot_native/features/hermes_settings.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/sessions.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// Actual native UI + Node/Relay + official Hermes and model, not recorded data.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native command adapters and a real model reply', (tester) async {
    if (Platform.isWindows) await DesktopHost.initialize();
    final client = NekodotClient()..prefs.language = 'en';
    final botId = const String.fromEnvironment('QA_SECOND_BOT');
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
      if (text.isNotEmpty) {
        await until(
          () => find
              .byWidgetPredicate(
                (w) =>
                    w is IconButton &&
                    w.tooltip == 'Send' &&
                    w.onPressed != null,
              )
              .evaluate()
              .isNotEmpty,
        );
      }
    }

    await client.loadMessages(conversationId);
    await until(() => client.node.activities[conversationId]?.state == 'idle');
    List<ChatMessage> messages() => client.node.messages[conversationId] ?? [];
    final before = messages().map((row) => row.messageId).toSet();
    final marker = 'NATIVE_COMMAND_${DateTime.now().millisecondsSinceEpoch}';
    bool streamed = false;
    void observe() {
      streamed |= messages().any(
        (row) =>
            !before.contains(row.messageId) &&
            row.author.type == 'bot' &&
            row.status == 'streaming' &&
            '${row.content['text'] ?? ''}'.isNotEmpty,
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
            !before.contains(row.messageId) &&
            row.author.type == 'bot' &&
            row.status == 'done' &&
            '${row.content['text']}'.contains(marker),
      ),
      seconds: 240,
    );
    client.removeListener(observe);
    expect(streamed, isTrue);
    await until(() => client.node.activities[conversationId]?.state == 'idle');
    await tester.pump(const Duration(milliseconds: 400));
    debugPrint('QA: real model reply completed and streamed');
    final modelReplies = messages()
        .where((row) => row.author.type == 'bot')
        .length;
    final userTurns = messages()
        .where((row) => row.author.type == 'user')
        .length;

    Future<void> command(
      String text,
      String expected, {
      String? prefill,
    }) async {
      final old = messages().map((row) => row.messageId).toSet();
      await typeMessage(text);
      await tester.pump(const Duration(milliseconds: 300));
      await tapReady(find.byTooltip('Send'));
      await until(
        () => messages().any(
          (row) =>
              !old.contains(row.messageId) &&
              row.kind == 'system' &&
              '${row.content['text']}'.startsWith(text) &&
              '${row.content['text']}'.contains(expected),
        ),
      );
      await until(
        () => prefill == null
            ? tester.widget<TextField>(input).controller!.text.isEmpty
            : tester.widget<TextField>(input).controller!.text == prefill,
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
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, '/history'),
        matching: find.text('App action'),
      ),
      findsOneWidget,
    );
    await tapReady(find.widgetWithText(ListTile, '/history'));
    await command('/history', marker);
    expect(
      messages().where((row) => row.author.type == 'bot').length,
      modelReplies,
    );
    expect(
      messages().where((row) => row.author.type == 'user').length,
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
      catalog.firstWhere((row) => row['name'] == '/handoff')['availability'],
      'not-integrated',
    );
    await typeMessage('/handoff');
    await until(() => find.byType(ExpansionTile).evaluate().isNotEmpty);
    await tapReady(find.byType(ExpansionTile));
    await until(
      () => find.widgetWithText(ListTile, '/handoff').evaluate().isNotEmpty,
    );
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, '/handoff'))
          .enabled,
      isFalse,
    );
    await typeMessage('');
    expect(
      messages().where((row) => row.author.type == 'bot').length,
      modelReplies,
    );

    final original = (await client.rpc('sessions.list', {
      'botId': botId,
    }))['currentSessionId'];
    final sessionName = 'NativeQA-${DateTime.now().millisecondsSinceEpoch}';
    await command('/new $sessionName', 'New Hermes session:');
    final fresh = (await client.rpc('sessions.list', {
      'botId': botId,
    }))['currentSessionId'];
    expect(fresh, isNot(original));
    final prompt =
        'Harmless test. Do not use tools. Reply exactly $marker-SESSION.';
    await typeMessage(prompt);
    await tapReady(find.byTooltip('Send'));
    await until(
      () => messages().any(
        (row) =>
            row.author.type == 'bot' &&
            row.status == 'done' &&
            '${row.content['text']}'.contains('$marker-SESSION'),
      ),
      seconds: 240,
    );
    await until(() => client.node.activities[conversationId]?.state == 'idle');
    await command('/fork $sessionName-branch', 'Branched Hermes session:');
    final branch = (await client.rpc('sessions.list', {
      'botId': botId,
    }))['currentSessionId'];
    expect(branch, isNot(fresh));
    await command('/history', '$marker-SESSION');
    await command('/undo', 'Hermes context rewound.', prefill: prompt);
    final undone = await client.rpc('sessions.history', {
      'botId': botId,
      'sessionId': branch,
    });
    expect(
      objects(undone['messages']).where((row) => row['role'] == 'user'),
      isEmpty,
    );
    await command('/resume $fresh', 'Resumed Hermes session:');
    final repliesBeforeRetry = messages()
        .where((row) => row.author.type == 'bot')
        .length;
    await command('/retry', 'Hermes context rewound.');
    await until(
      () =>
          messages().where((row) => row.author.type == 'bot').length >
              repliesBeforeRetry &&
          client.node.activities[conversationId]?.state == 'idle',
      seconds: 240,
    );
    await command('/compact --preview', 'Hermes compression (preview)');
    await command('/save', 'Usage: /save');

    await typeMessage('/sessions');
    await tapReady(find.byTooltip('Send'));
    await until(() => find.byType(BotSessionsPage).evaluate().isNotEmpty);
    await until(() => find.text(sessionName).evaluate().isNotEmpty);
    await tapReady(find.text(sessionName));
    await until(() => find.text('Native transcript').evaluate().isNotEmpty);
    await until(() => find.text('Resume here').evaluate().isNotEmpty);
    await tapReady(find.text('Resume here'));
    await until(
      () =>
          find.byType(BotSessionsPage).evaluate().isNotEmpty &&
          find.text('Native transcript').evaluate().isEmpty,
    );
    await tester.pageBack();
    await until(() => input.evaluate().isNotEmpty);
    await command('/reset', 'New Hermes session:');
    final empty = (await client.rpc('sessions.list', {
      'botId': botId,
    }))['currentSessionId'];
    final emptyHistory = await client.rpc('sessions.history', {
      'botId': botId,
      'sessionId': empty,
    });
    expect(objects(emptyHistory['messages']), isEmpty);
    await command('/resume $original', 'Resumed Hermes session:');
    final ids = messages().map((row) => row.messageId).toSet();
    await client.connection.connect();
    await until(() => client.connection.ready);
    await client.synchronize(client.selectedNodeId!);
    await client.loadMessages(conversationId);
    expect(messages().map((row) => row.messageId).toSet(), ids);
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
      'newSessionAndReset': true,
      'branchAndUndo': true,
      'resumeAndRetry': true,
      'nativeSessionPicker': true,
      'compressionPreview': true,
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
