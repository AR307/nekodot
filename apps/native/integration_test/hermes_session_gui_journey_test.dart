import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/sessions.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// Actual native clients, connected Node/Relay, official Hermes and real model.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('browse, create and switch Bot sessions from the GUI', (
    tester,
  ) async {
    if (Platform.isWindows) await DesktopHost.initialize();
    final c = NekodotClient()..language = 'en';
    const botId = String.fromEnvironment('QA_SECOND_BOT');
    const otherBotId = String.fromEnvironment('QA_BOT');
    final login = await c.request(
      '/auth/login',
      method: 'POST',
      body: {
        'email': const String.fromEnvironment('QA_EMAIL'),
        'password': const String.fromEnvironment('QA_PASSWORD'),
      },
    );
    c.token = login['token'] as String;
    c.selectedNodeId = const String.fromEnvironment('QA_NODE');
    await c.bootstrap();
    addTearDown(c.dispose);

    Future<void> until(bool Function() ready, {int seconds = 90}) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 150));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(ready(), isTrue, reason: 'Real session GUI journey timed out.');
    }

    Future<void> tap(Finder finder) async {
      await until(() => finder.hitTestable().evaluate().isNotEmpty);
      await tester.tap(finder.hitTestable().first);
      await tester.pump(const Duration(milliseconds: 400));
    }

    await until(() => c.online && c.node.bots.length >= 2);
    final dm = c.node.conversations.firstWhere(
      (row) => row['kind'] == 'dm' && row['botId'] == botId,
    );
    final conversationId = '${dm['conversationId']}';
    Future<Json> sessions([String bot = botId]) =>
        c.rpc('sessions.list', {'botId': bot});
    final original = (await sessions())['currentSessionId'];
    final otherBefore = await sessions(otherBotId);
    runApp(
      MaterialApp(
        theme: appTheme(Brightness.light),
        builder: (context, child) => Platform.isWindows
            ? WindowChrome(child: child!)
            : Ambient(child: child!),
        navigatorObservers: [nativeRoutes],
        home: HomePage(client: c),
      ),
    );
    await tap(find.byKey(ValueKey('conversation-$conversationId')));
    final input = find.byKey(const ValueKey('chat-input'));
    await until(() => input.evaluate().isNotEmpty);
    await c.loadMessages(conversationId);
    await until(() => c.node.activities[conversationId]?['state'] == 'idle');
    List<Json> messages() => c.node.messages[conversationId] ?? [];
    final initialMessages = messages().map((r) => r['messageId']).toSet();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final titleA = 'GUI-$stamp-A', titleB = 'GUI-$stamp-B';
    final secretA = 'ORCHID-$stamp', secretB = 'CEDAR-$stamp';
    final draft = 'Unsent session GUI draft $stamp';

    Future<void> open() async {
      await tap(find.byKey(const ValueKey('chat-sessions')));
      await until(
        () => find
            .byKey(const ValueKey('native-session-search'))
            .evaluate()
            .isNotEmpty,
      );
      expect(find.byType(BotSessionsPage), findsOneWidget);
    }

    Future<void> search(String value) async {
      await tester.enterText(
        find.byKey(const ValueKey('native-session-search')),
        value,
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> create(String title) async {
      await tap(find.byKey(const ValueKey('new-native-session')));
      await tester.enterText(
        find.byKey(const ValueKey('native-session-title')),
        title,
      );
      await tap(find.byKey(const ValueKey('create-native-session')));
      await until(() => input.evaluate().isNotEmpty);
    }

    Future<void> send(String text, String expected) async {
      final before = messages().map((r) => r['messageId']).toSet();
      await tester.tap(input);
      await tester.enterText(input, text);
      await tester.pump(const Duration(milliseconds: 300));
      await tap(find.byTooltip('Send'));
      await until(
        () => messages().any(
          (r) =>
              !before.contains(r['messageId']) &&
              r['author']['type'] == 'bot' &&
              r['status'] == 'done' &&
              '${r['content']['text']}'.contains(expected),
        ),
        seconds: 240,
      );
      await until(() => c.node.activities[conversationId]?['state'] == 'idle');
    }

    await tester.enterText(input, draft);
    await open();
    await search('no-such-session-$stamp');
    expect(find.text('No matching sessions'), findsOneWidget);
    await tester.pageBack();
    await until(() => input.evaluate().isNotEmpty);
    expect(tester.widget<TextField>(input).controller!.text, draft);
    expect(messages().map((r) => r['messageId']).toSet(), initialMessages);
    await open();
    await tap(find.byKey(const ValueKey('new-native-session')));
    await tap(find.text('Cancel'));
    expect((await sessions())['currentSessionId'], original);
    await create(titleA);
    final idA = (await sessions())['currentSessionId'] as String;
    expect(idA, isNot(original));
    expect(tester.widget<TextField>(input).controller!.text, draft);
    final empty = await c.rpc('sessions.history', {
      'botId': botId,
      'sessionId': idA,
    });
    expect(objects(empty['messages']), isEmpty);
    await send(
      'Harmless acceptance test. For this session only, the passphrase is '
      '$secretA. Do not use tools or write memory. Reply exactly $secretA.',
      secretA,
    );
    debugPrint('QA session GUI: created A and completed real model turn');
    await open();
    await create(titleB);
    final idB = (await sessions())['currentSessionId'] as String;
    expect(idB, isNot(idA));
    await send(
      'Harmless acceptance test. For this session only, the passphrase is '
      '$secretB. Do not use tools or write memory. Reply exactly $secretB.',
      secretB,
    );
    final beforeRecall = messages().map((r) => r['messageId']).toSet();
    await send(
      'Use Hermes session_search to read my earlier session $idA '
      '(session_id only). What was its passphrase? Reply with only that value. '
      'Do not read files, use other tools or write memory.',
      secretA,
    );
    expect(
      messages().any(
        (r) =>
            !beforeRecall.contains(r['messageId']) &&
            r['kind'] == 'tool' &&
            r['content']['tool'] == 'session_search' &&
            r['content']['error'] != true,
      ),
      isTrue,
    );
    debugPrint(
      'QA session GUI: Bot read its earlier session with session_search',
    );
    final beforeBrowse = messages().map((r) => r['messageId']).toSet();
    await open();
    await search(titleA);
    await tap(find.byKey(ValueKey('native-session-$idA')));
    await until(() => find.text('Native transcript').evaluate().isNotEmpty);
    await until(() => find.text(secretA).evaluate().isNotEmpty);
    expect(find.text(secretB), findsNothing);
    expect((await sessions())['currentSessionId'], idB);
    expect(messages().map((r) => r['messageId']).toSet(), beforeBrowse);
    await tester.pageBack();
    await until(
      () => find.byKey(ValueKey('switch-session-$idA')).evaluate().isNotEmpty,
    );
    await tap(find.byKey(ValueKey('switch-session-$idA')));
    await until(() => input.evaluate().isNotEmpty);
    expect((await sessions())['currentSessionId'], idA);
    await send(
      'What is this session\'s passphrase from our earlier message? '
      'Do not use tools. Reply with only the passphrase.',
      secretA,
    );
    final historyA = await c.rpc('sessions.history', {
      'botId': botId,
      'sessionId': idA,
    });
    expect('${historyA['messages']}', contains(secretA));
    expect('${historyA['messages']}', isNot(contains(secretB)));
    debugPrint('QA session GUI: preview did not switch; GUI resumed A context');

    await open();
    await search('GUI-$stamp');
    expect(find.text('Current'), findsOneWidget);
    expect(find.byKey(ValueKey('native-session-$idA')), findsOneWidget);
    expect(find.byKey(ValueKey('switch-session-$idB')), findsOneWidget);
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(milliseconds: 400));
      await binding.takeScreenshot('hermes-session-gui-android');
    }
    await tester.pageBack();
    await until(() => input.evaluate().isNotEmpty);
    final beforeReconnect = messages().map((r) => r['messageId']).toSet();
    await c.connect();
    await until(() => c.ready);
    await c.synchronize(c.selectedNodeId!);
    await c.loadMessages(conversationId);
    expect((await sessions())['currentSessionId'], idA);
    expect(messages().map((r) => r['messageId']).toSet(), beforeReconnect);
    final otherAfter = await sessions(otherBotId);
    expect(otherAfter['currentSessionId'], otherBefore['currentSessionId']);
    expect(
      objects(otherAfter['sessions']).map((r) => r['session_id']).toSet(),
      objects(otherBefore['sessions']).map((r) => r['session_id']).toSet(),
    );
    // Restore the initial Bot session through the GUI, preserving all evidence.
    await open();
    await search('$original');
    await tap(find.byKey(ValueKey('switch-session-$original')));
    await until(() => input.evaluate().isNotEmpty);
    expect((await sessions())['currentSessionId'], original);
    binding.reportData = {
      ...?binding.reportData,
      'actualNativeClient': true,
      'realHermesAndModel': true,
      'guiEntryWithoutSlashCommands': true,
      'searchAndCancel': true,
      'draftPreserved': true,
      'newSessionHasEmptyContext': true,
      'nativeSessionSearchReadHistory': true,
      'previewWithoutSwitchOrModelTurn': true,
      'switchRecallsCorrectSession': true,
      'otherBotUnchanged': true,
      'reconnectWithoutReplay': true,
      'originalSessionRestored': true,
    };
    debugPrint('QA session GUI: real native journey passed');
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 15)));
}
