import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/bot_editor.dart';
import 'package:nekodot_native/features/files.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// The candidate App operates the real isolated Hermes host, never production.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native host commands, detached answers and profile import', (
    tester,
  ) async {
    if (Platform.isWindows) await DesktopHost.initialize();
    final c = NekodotClient()..language = 'en';
    final botId = const String.fromEnvironment('QA_SECOND_BOT');
    final login = await c.request(
      '/auth/login',
      method: 'POST',
      body: {
        'email': const String.fromEnvironment('QA_EMAIL'),
        'password': const String.fromEnvironment('QA_PASSWORD'),
      },
    );
    c.token = login['token'];
    c.selectedNodeId = const String.fromEnvironment('QA_NODE');
    await c.bootstrap();
    addTearDown(c.dispose);
    Future<void> until(bool Function() ready, {int seconds = 120}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 150));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(ready(), isTrue, reason: 'Real host-command journey timed out');
    }

    Future<void> tap(Finder target) async {
      await until(() => target.evaluate().isNotEmpty);
      await tester.ensureVisible(target.first);
      await until(() => target.hitTestable().evaluate().isNotEmpty);
      await tester.tap(target.hitTestable().first);
    }

    await until(() => c.online && c.node.bots.length >= 2);
    final bot = c.node.bots.firstWhere((r) => r['botId'] == botId);
    final conversationId =
        '${c.node.conversations.firstWhere((r) => r['kind'] == 'dm' && r['botId'] == botId)['conversationId']}';
    runApp(
      MaterialApp(
        theme: appTheme(Brightness.light),
        navigatorObservers: [nativeRoutes],
        builder: (context, child) => Platform.isWindows
            ? WindowChrome(child: child!)
            : Ambient(child: child!),
        home: HomePage(client: c),
      ),
    );
    await tap(find.byKey(ValueKey('conversation-$conversationId')));
    final input = find.byKey(const ValueKey('chat-input'));
    await until(() => input.evaluate().isNotEmpty);
    await c.loadMessages(conversationId);
    await until(() => c.node.activities[conversationId]?['state'] == 'idle');
    List<Json> messages() => c.node.messages[conversationId] ?? [];
    Future<Json> command(String text, String expected) async {
      final before = messages().map((r) => r['messageId']).toSet();
      await tap(input);
      await tester.enterText(input, text);
      await tester.pump(const Duration(milliseconds: 250));
      await until(
        () => find
            .byWidgetPredicate(
              (w) =>
                  w is IconButton && w.tooltip == 'Send' && w.onPressed != null,
            )
            .evaluate()
            .isNotEmpty,
      );
      await tap(find.byTooltip('Send'));
      await until(
        () => messages().any(
          (r) =>
              !before.contains(r['messageId']) &&
              r['kind'] == 'system' &&
              '${r['content']['text']}'.startsWith(text) &&
              '${r['content']['text']}'.contains(expected),
        ),
        seconds: 300,
      );
      await until(
        () => tester.widget<TextField>(input).controller!.text.isEmpty,
      );
      return messages().firstWhere(
        (r) =>
            !before.contains(r['messageId']) &&
            r['kind'] == 'system' &&
            '${r['content']['text']}'.startsWith(text),
      );
    }

    final session = (await c.rpc('sessions.list', {
      'botId': botId,
    }))['currentSessionId'];
    final originalHistory = await c.rpc('sessions.history', {
      'botId': botId,
      'sessionId': session,
    });
    final marker = 'SIDE_QA_${DateTime.now().millisecondsSinceEpoch}';
    await command(
      '/bg Reply exactly $marker-BG. Do not use tools.',
      '$marker-BG',
    );
    await command(
      '/btw Reply exactly $marker-BTW. Do not use tools.',
      '$marker-BTW',
    );
    final afterHistory = await c.rpc('sessions.history', {
      'botId': botId,
      'sessionId': session,
    });
    expect(afterHistory['messages'], originalHistory['messages']);
    expect(c.node.activities[conversationId]?['state'], 'idle');
    debugPrint(
      'QA HOST: real background/btw models left the main context unchanged',
    );

    await command('/tools disable terminal', 'profile tools: terminal');
    await command('/new Tools-disabled QA', 'New Hermes session:');
    final disabled = await command('/tools', 'Hermes tools (');
    expect('${disabled['content']['text']}', isNot(contains('\nterminal:')));
    await command('/tools enable terminal', 'profile tools: terminal');
    await command('/new Tools-enabled QA', 'New Hermes session:');
    final enabled = await command('/tools', 'Hermes tools (');
    expect('${enabled['content']['text']}', contains('\nterminal:'));
    final settings = await c.rpc('hermes.settings.get', {'botId': botId});
    final cwd = objects(settings['fields'])
        .firstWhere((r) => r['key'] == 'terminal.cwd')['value'];
    try {
      await c.rpc('hermes.settings.set', {
        'botId': botId,
        'key': 'terminal.cwd',
        'value': const String.fromEnvironment('QA_WORKTREE_PATH'),
      });
      await command('/new Worktree QA', 'New Hermes session:');
      await command('/worktree list', 'worktree-qa');
      await command(
        '/worktree new native-qa-${DateTime.now().millisecondsSinceEpoch}',
        'Hermes workspace switched to',
      );
      await command('/worktree list', 'native-qa-');
    } finally {
      await c.rpc('hermes.settings.set', {
        'botId': botId,
        'key': 'terminal.cwd',
        'value': cwd,
      });
      await command('/resume $session', 'Resumed Hermes session:');
    }
    debugPrint(
      'QA HOST: actual tool enable/disable and isolated worktree creation passed',
    );

    await command('/logs 3', 'Hermes profile gateway log');
    await command('/update check', 'Hermes update check');
    final backup = await command(
      '/snapshot create',
      'Hermes native backup created',
    );
    final backupId = (backup['content']['files'] as List).single as String;
    final backupBytes = await downloadFile(c, backupId);
    expect(backupBytes.take(2), [0x50, 0x4b]);
    debugPrint(
      'QA HOST: official logs, update check and actual ZIP backup downloaded',
    );

    final memory = await c.rpc('memory.get', {'botId': botId});
    final memoryBefore = objects(memory['documents'])
        .firstWhere((r) => r['name'] == 'MEMORY.md')['content'];
    final exported = await command('/export', 'Hermes profile exported');
    final fileId = (exported['content']['files'] as List).single as String;
    final bytes = await downloadFile(c, fileId);
    expect(bytes.take(2), [0x1f, 0x8b]);
    final card = find.byWidgetPredicate(
      (w) => w is FileCard && w.fileId == fileId,
    );
    await until(() => card.evaluate().isNotEmpty);
    await tap(card);
    await until(() => find.byType(FilePage).evaluate().isNotEmpty);
    await tap(find.text('Import as a new Bot'));
    await until(() => find.byType(BotEditor).evaluate().isNotEmpty);
    final editorScroll = find
        .descendant(
          of: find.byType(BotEditor),
          matching: find.byType(Scrollable),
        )
        .first;
    Future<void> fill(String label, String value) async {
      final field = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is LabeledField && w.label == label,
        ),
        matching: find.byType(TextField),
      );
      await tester.scrollUntilVisible(field, 180, scrollable: editorScroll);
      await tester.enterText(field, value);
    }

    final name = 'Imported command QA ${DateTime.now().millisecondsSinceEpoch}';
    await fill('Name', name);
    await fill('@handle', 'importqa${DateTime.now().millisecondsSinceEpoch}');
    await fill(
      'Role',
      'Isolated profile import acceptance. Keep native learned memories.',
    );
    await fill('Model', '${bot['model']}');
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.scrollUntilVisible(save, 180, scrollable: editorScroll);
    await until(() => tester.widget<FilledButton>(save).onPressed != null);
    final existingBotIds = c.node.bots.map((r) => r['botId']).toSet();
    await tap(find.text('Save'));
    await until(
      () => c.node.bots.any(
        (r) => !existingBotIds.contains(r['botId']) && r['displayName'] == name,
      ),
    );
    final imported = c.node.bots.firstWhere((r) => r['displayName'] == name);
    final importedMemory = await c.rpc('memory.get', {
      'botId': imported['botId'],
    });
    expect(
      objects(importedMemory['documents'])
          .firstWhere((r) => r['name'] == 'MEMORY.md')['content'],
      memoryBefore,
    );
    final importedDm =
        c.node.conversations.firstWhere(
              (r) => r['kind'] == 'dm' && r['botId'] == imported['botId'],
            )['conversationId']
            as String;
    await until(
      () => c.node.activities[importedDm]?['state'] == 'idle',
      seconds: 240,
    );
    await c.loadMessages(importedDm);
    expect(
      c.node.messages[importedDm]!.where(
        (r) => r['author']['type'] == 'bot' && r['status'] == 'done',
      ),
      isNotEmpty,
    );
    debugPrint(
      'QA HOST: profile export card imported through App; memories and real welcome verified',
    );
    await tester.pageBack();
    await until(() => input.evaluate().isNotEmpty);
    if (Platform.isAndroid) {
      FocusManager.instance.primaryFocus?.unfocus();
      await until(() => tester.view.viewInsets.bottom == 0);
      await binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(milliseconds: 300));
      await binding.takeScreenshot('hermes-host-commands-android');
    }
    binding.reportData = {
      ...?binding.reportData,
      'realHermes': true,
      'backgroundAndBtwRealModel': true,
      'mainContextUnchanged': true,
      'nativeToolEnableDisable': true,
      'isolatedWorktreeCreatedAndSelected': true,
      'logsAndUpdateCheck': true,
      'nativeBackupDownloaded': true,
      'profileExportImportThroughNativeApp': true,
      'importedMemoryPreserved': true,
      'importedBotRealWelcome': true,
    };
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 20)));
}
