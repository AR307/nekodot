import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/hermes_settings.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// Run against the isolated real Node/Relay and official Hermes, never fake-hermes.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native profile settings, isolation and a real model reply', (
    tester,
  ) async {
    if (Platform.isWindows) await DesktopHost.initialize();
    final client = NekodotClient()..language = 'en';
    final botId = const String.fromEnvironment('QA_BOT');
    final secondBotId = const String.fromEnvironment('QA_SECOND_BOT');
    final conversationId = const String.fromEnvironment('QA_CONVERSATION');
    // Authenticate in memory without replacing the user's saved product login.
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
        reason: 'Real native settings journey did not complete.',
      );
    }

    Future<void> tapReady(Finder finder) async {
      await until(() => finder.hitTestable().evaluate().isNotEmpty);
      await tester.tap(finder.hitTestable());
    }

    Future<Json> settings(String id) =>
        client.rpc('hermes.settings.get', {'botId': id});
    bool compression(Json value) =>
        objects(value['fields']).firstWhere(
          (field) => field['key'] == 'compression.enabled',
        )['value'] ==
        true;
    await until(() => client.online && client.node.bots.length >= 2);
    final firstBefore = await settings(botId);
    final secondBefore = await settings(secondBotId);
    expect(objects(firstBefore['fields']), isNotEmpty);
    expect(
      objects(firstBefore['fields'])
          .where((field) => field['sensitive'] == true),
      everyElement(containsPair('value', null)),
    );

    void openHome() => runApp(
      MaterialApp(
        key: UniqueKey(),
        theme: appTheme(Brightness.light),
        builder: (context, child) => Platform.isWindows
            ? WindowChrome(child: child!)
            : Ambient(child: child!),
        navigatorObservers: [nativeRoutes],
        home: HomePage(client: client),
      ),
    );
    openHome();
    await until(
      () => find
          .byKey(ValueKey('conversation-$conversationId'))
          .evaluate()
          .isNotEmpty,
    );
    await tapReady(find.byKey(ValueKey('conversation-$conversationId')));
    await until(() => find.byTooltip('Details').evaluate().isNotEmpty);
    await tapReady(find.byTooltip('Details').first);
    await until(
      () => find.widgetWithText(Tab, 'Settings').evaluate().isNotEmpty,
    );
    await tapReady(find.widgetWithText(Tab, 'Settings'));
    await until(() => find.byType(HermesSettings).evaluate().isNotEmpty);
    final search = find.descendant(
      of: find.byType(HermesSettings),
      matching: find.byType(TextField),
    );
    await until(() => search.evaluate().isNotEmpty);
    await tester.enterText(search, 'compression.enabled');
    await tester.pump(const Duration(milliseconds: 500));
    await until(() => find.byType(SwitchListTile).evaluate().length == 1);
    await tapReady(find.byType(SwitchListTile));
    await until(
      () =>
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value !=
          compression(firstBefore),
    );
    expect(compression(await settings(botId)), !compression(firstBefore));
    expect(compression(await settings(secondBotId)), compression(secondBefore));
    debugPrint('QA: real Hermes setting saved; second profile unchanged');

    if (defaultTargetPlatform == TargetPlatform.android) {
      FocusManager.instance.primaryFocus?.unfocus();
      await until(() => tester.view.viewInsets.bottom == 0);
      await binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(milliseconds: 400));
      await binding.takeScreenshot('hermes-settings-native-android');
    }
    await tester.tap(search);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(search, 'model_context_length');
    await tester.pump(const Duration(milliseconds: 500));
    debugPrint(
      'QA: model search entered=${tester.widget<TextField>(search).controller!.text == 'model_context_length'} '
      'modelRow=${find.text('model_context_length').evaluate().length} '
      'readonlyHint=${find.textContaining('Change this in Bot model settings').evaluate().length}',
    );
    await until(
      () => find
          .textContaining('Change this in Bot model settings')
          .evaluate()
          .isNotEmpty,
    );
    expect(
      find.textContaining('Change this in Bot model settings'),
      findsOneWidget,
    );

    await tester.tap(search);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(search, 'terminal.vercel_runtime');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(ListTile, 'terminal.vercel_runtime'));
    await until(() => find.byType(AlertDialog).evaluate().isNotEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('setting-select')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('node24').last);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await until(() => find.byType(AlertDialog).evaluate().isEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    await until(() => find.textContaining('\nnode24').evaluate().isNotEmpty);
    await tester.tap(find.widgetWithText(ListTile, 'terminal.vercel_runtime'));
    await until(() => find.byType(AlertDialog).evaluate().isNotEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('setting-select')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('—').last);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await until(() => find.byType(AlertDialog).evaluate().isEmpty);
    await tester.pump(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(seconds: 1));
    final afterCancel = await settings(botId);
    expect(
      objects(afterCancel['fields']).firstWhere(
        (field) => field['key'] == 'terminal.vercel_runtime',
      )['value'],
      'node24',
      reason: 'Cancelling a clear selection must not change Hermes settings.',
    );
    debugPrint('QA: cancelling a select edit preserved the real Hermes value');
    await tester.tap(find.widgetWithText(ListTile, 'terminal.vercel_runtime'));
    await until(() => find.byType(AlertDialog).evaluate().isNotEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('setting-select')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('—').last);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await until(() => find.byType(AlertDialog).evaluate().isEmpty);
    await until(() => find.textContaining('\nNot set').evaluate().isNotEmpty);
    expect(
      objects((await settings(botId))['fields']).firstWhere(
        (field) => field['key'] == 'terminal.vercel_runtime',
      )['value'],
      isNull,
    );

    openHome();
    await tester.pump(const Duration(milliseconds: 500));
    await tapReady(find.byKey(ValueKey('conversation-$conversationId')));
    await until(
      () => find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty,
    );
    await client.loadMessages(conversationId);
    await until(
      () => client.node.activities[conversationId]?['state'] == 'idle',
      seconds: 240,
    );
    final before = (client.node.messages[conversationId] ?? [])
        .map((m) => m['messageId'])
        .toSet();
    final marker = 'NATIVE_SETTINGS_${DateTime.now().millisecondsSinceEpoch}';
    bool streamed = false;
    void observe() {
      streamed |= (client.node.messages[conversationId] ?? []).any(
        (m) =>
            !before.contains(m['messageId']) &&
            m['author']['type'] == 'bot' &&
            m['status'] == 'streaming' &&
            '${m['content']['text'] ?? ''}'.isNotEmpty,
      );
    }

    client.addListener(observe);
    await tester.enterText(
      find.byKey(const ValueKey('chat-input')),
      'This is a harmless acceptance test. Do not use tools. Reply with exactly $marker.',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tapReady(find.byTooltip('Send'));
    await until(
      () => (client.node.messages[conversationId] ?? []).any(
        (m) =>
            !before.contains(m['messageId']) &&
            m['author']['type'] == 'bot' &&
            m['status'] == 'done' &&
            '${m['content']['text']}'.contains(marker),
      ),
      seconds: 240,
    );
    client.removeListener(observe);
    expect(
      streamed,
      isTrue,
      reason: 'The real reply must stream, not arrive only as a snapshot.',
    );
    if (defaultTargetPlatform == TargetPlatform.android) {
      FocusManager.instance.primaryFocus?.unfocus();
      await until(() => tester.view.viewInsets.bottom == 0);
      await binding.takeScreenshot('hermes-chat-native-android');
    }
    final messageIds = (client.node.messages[conversationId] ?? [])
        .map((m) => m['messageId'])
        .toSet();
    await client.connect();
    await until(() => client.ready);
    await client.synchronize(client.selectedNodeId!);
    await client.loadMessages(conversationId);
    expect(
      (client.node.messages[conversationId] ?? [])
          .map((m) => m['messageId'])
          .toSet(),
      messageIds,
    );
    expect(compression(await settings(botId)), !compression(firstBefore));
    binding.reportData = {
      ...?binding.reportData,
      'realHermes': true,
      'schemaFields': objects(firstBefore['fields']).length,
      'saved': true,
      'profileIsolation': true,
      'streamedReply': streamed,
      'reconnectWithoutReplay': true,
      'cancelPreservedValue': true,
      'explicitClearSaved': true,
    };
    debugPrint('QA: actual native settings and real model journey passed');
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 15)));
}
