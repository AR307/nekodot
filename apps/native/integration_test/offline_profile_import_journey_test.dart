import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/bot_editor.dart';
import 'package:nekodot_native/features/chat.dart';
import 'package:nekodot_native/features/files.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

// A real exported Hermes profile, selected from disk rather than an existing
// chat file card: local staging must be uploaded before bots.create.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('locally staged profile archive imports through candidate UI', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'language': 'zh',
      'theme': 'light',
      'notification-requested': true,
    });
    final c = NekodotClient(vault: MemoryVault());
    const node = String.fromEnvironment('QA_NODE');
    const dm = String.fromEnvironment('QA_CONVERSATION');
    var stage = 'login';
    Future<void> until(bool Function() ready, {int seconds = 180}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(ready(), isTrue, reason: stage);
    }

    await tester.pumpWidget(NekodotApp(client: c));
    await until(
      () => find.byKey(const ValueKey('auth-email')).evaluate().isNotEmpty,
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      const String.fromEnvironment('QA_EMAIL'),
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      const String.fromEnvironment('QA_PASSWORD'),
    );
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await until(() => c.connection.ready);
    await tester.runAsync(() => c.selectNode(node));
    await until(() => c.online && find.byType(HomePage).evaluate().isNotEmpty);
    await tester.tap(find.byKey(ValueKey('conversation-$dm')));
    await until(() => c.node.messages[dm]?.isNotEmpty == true);
    final botId =
        c.node.conversations.firstWhere(
              (v) => v['conversationId'] == dm,
            )['botId']
            as String;
    final name = 'Offline import ${DateTime.now().millisecondsSinceEpoch}';
    final memory = await tester.runAsync(
      () => c.rpc('memory.get', {'botId': botId}),
    );
    stage = 'export real native profile';
    var operation = (await tester.runAsync(
      () => c.rpc('commands.execute', {
        'botId': botId,
        'conversationId': dm,
        'command': '/export',
        'clientMsgId': uid(),
      }),
    ))!;
    while (operation['status'] == 'running') {
      await tester.pump(const Duration(milliseconds: 200));
      operation = (await tester.runAsync(
        () =>
            c.rpc('operations.get', {'operationId': operation['operationId']}),
      ))!;
    }
    expect(operation['status'], 'done');
    await tester.runAsync(() => c.loadMessages(dm));
    final exported = c.node.messages[dm]!.lastWhere(
      (m) =>
          '${m.content['text']}'.contains('Hermes profile exported') &&
          (m.content['files'] as List?)?.isNotEmpty == true,
    );
    final bytes = await tester.runAsync(
      () =>
          downloadFile(c, (exported.content['files'] as List).single as String),
    );
    final path =
        '${const String.fromEnvironment('QA_EVIDENCE_DIR')}/cold/local-import.tar.gz';
    final archive = (await tester.runAsync(() async {
      await File(path).writeAsBytes(bytes!);
      return pickChatFile(c, dm, (_) {}, localPath: path);
    }))!;
    expect(archive['fileId'], isNull);
    stage = 'import staged archive in GUI';
    Navigator.of(tester.element(find.byType(ChatPage).last)).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            BotEditor(client: c, importProfile: true, initialArchive: archive),
      ),
    );
    await until(
      () => find.byKey(const ValueKey('bot-name')).evaluate().isNotEmpty,
    );
    await tester.enterText(find.byKey(const ValueKey('bot-name')), name);
    final scroll = find
        .descendant(
          of: find.byType(BotEditor),
          matching: find.byType(Scrollable),
        )
        .first;
    final chooser = find.byKey(const ValueKey('model-choice'));
    await tester.scrollUntilVisible(chooser, 220, scrollable: scroll);
    await until(() => tester.widget<OutlinedButton>(chooser).onPressed != null);
    await tester.tap(chooser);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const ValueKey('model-search')),
      'gpt-6.1-sol',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('model-option-gpt-6.1-sol')));
    await tester.pump(const Duration(milliseconds: 300));
    final save = find.byKey(const ValueKey('bot-save'));
    await tester.scrollUntilVisible(save, 220, scrollable: scroll);
    await tester.tap(save);
    await until(
      () => c.node.bots.any((b) => b['displayName'] == name),
      seconds: 360,
    );
    final imported = c.node.bots.firstWhere((b) => b['displayName'] == name);
    expect(archive['fileId'], isNotNull);
    final actual = await tester.runAsync(
      () => c.rpc('memory.get', {'botId': imported['botId']}),
    );
    String memoryText(Json value) =>
        '${objects(value['documents']).firstWhere((d) => d['name'] == 'MEMORY.md')['content']}';
    expect(memoryText(actual!), memoryText(memory!));
    final importedDm =
        c.node.conversations.firstWhere(
              (v) => v['botId'] == imported['botId'],
            )['conversationId']
            as String;
    stage = 'real welcome after imported profile';
    Navigator.of(tester.element(find.byType(ChatPage).last)).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(client: c, conversationId: importedDm),
      ),
    );
    await until(() => c.node.messages[importedDm] != null);
    await until(
      () => c.node.activities[importedDm]?.state == 'idle',
      seconds: 360,
    );
    await tester.runAsync(() => c.loadMessages(importedDm));
    expect(
      c.node.messages[importedDm]!.any(
        (m) => m.author.type == 'bot' && m.status == 'done',
      ),
      isTrue,
    );
    final report = {
      'localArchiveUploaded': true,
      'nativeProfileImported': true,
      'memoryRetained': true,
      'actualModelWelcome': true,
      'botId': imported['botId'],
    };
    await tester.runAsync(() async {
      await File(
        '${const String.fromEnvironment('QA_EVIDENCE_DIR')}/windows-profile-import.json',
      ).writeAsString(jsonEncode(report));
    });
    binding.reportData = report;
  }, timeout: const Timeout(Duration(minutes: 12)));
}
