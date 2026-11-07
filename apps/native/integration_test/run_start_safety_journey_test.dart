import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/chat_models.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/files.dart';
import 'package:nekodot_native/main.dart';
import 'package:nekodot_native/ui/design.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

/// Real Windows client, isolated Relay/Node, Hermes v0.22.6-r1 and a real model.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('relay turns start without re-applying the model, failures are '
      'localized, and a Bot-delivered program is never run on Open', (
    tester,
  ) async {
    const email = String.fromEnvironment('QA_EMAIL');
    const password = String.fromEnvironment('QA_PASSWORD');
    const nodeId = String.fromEnvironment('QA_NODE');
    const dm = String.fromEnvironment('QA_CONVERSATION');
    const group = String.fromEnvironment('QA_GROUP');
    const control = String.fromEnvironment('QA_CONTROL');
    const work = String.fromEnvironment('QA_WORK_DIR');
    const evidence = String.fromEnvironment('QA_EVIDENCE_DIR');
    expect(
      [
        email,
        password,
        nodeId,
        dm,
        group,
        control,
        work,
      ].every((v) => v.isNotEmpty),
      isTrue,
    );
    SharedPreferences.setMockInitialValues({
      'language': 'zh',
      'theme': 'light',
      'notification-requested': true,
    });
    final c = NekodotClient(vault: MemoryVault());
    final capture = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: NekodotApp(client: c),
      ),
    );
    final report = <String, Object?>{};

    Future<void> until(
      bool Function() done, {
      int seconds = 180,
      String what = '',
    }) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!done() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 150));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(done(), isTrue, reason: 'Did not reach: $what');
    }

    Future<void> shot(String name) async {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
        await Directory(evidence).create(recursive: true);
        await File('$evidence/$name.png').writeAsBytes(bytes);
        image.dispose();
      });
    }

    Future<void> command(String path) async {
      await tester.runAsync(() async {
        final client = HttpClient();
        final response = await (await client.postUrl(
          Uri.parse('$control$path'),
        )).close();
        expect(response.statusCode, 200, reason: path);
        client.close();
      });
    }

    List<ChatMessage> messages(String id) => c.node.messages[id] ?? [];
    bool idle(String id) => (c.node.activities[id]?.state ?? 'idle') == 'idle';

    Future<void> open(String id) async {
      final row = find.byKey(ValueKey('conversation-$id'));
      await until(() => row.evaluate().isNotEmpty, what: 'conversation $id');
      await tester.ensureVisible(row);
      await until(
        () => row.hitTestable().evaluate().isNotEmpty,
        what: 'conversation $id ready',
      );
      await tester.tap(row.hitTestable().first);
      await tester.pump(const Duration(milliseconds: 400));
      await until(
        () => find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty,
      );
      await tester.runAsync(() => c.loadMessages(id));
    }

    Future<void> submit(String text) async {
      final field = find.byKey(const ValueKey('chat-input'));
      // A closed dialog keeps the test's focused editable; tap to attach input again.
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, text);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pump();
    }

    Future<ChatMessage> reply(
      String id,
      Set<String> before,
      bool Function(ChatMessage) matches, {
      int seconds = 300,
      String what = '',
    }) async {
      ChatMessage? found;
      await until(
        () {
          found = messages(id)
              .where(
                (m) =>
                    !before.contains(m.messageId) &&
                    m.kind == 'text' &&
                    m.author.type == 'bot' &&
                    m.status != 'streaming' &&
                    matches(m),
              )
              .lastOrNull;
          return found != null && idle(id);
        },
        seconds: seconds,
        what: what,
      );
      return found!;
    }

    Set<String> ids(String id) => messages(id).map((m) => m.messageId).toSet();

    String managementSinceMark() {
      final log = File('$work/management.log').readAsStringSync();
      return log.substring(log.lastIndexOf('--- mark ---'));
    }

    await until(
      () => find.byKey(const ValueKey('auth-email')).evaluate().isNotEmpty,
    );
    await tester.enterText(find.byKey(const ValueKey('auth-email')), email);
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      password,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await until(() => c.connection.ready, what: 'login');
    await tester.runAsync(() => c.selectNode(nodeId));
    await until(
      () =>
          c.online &&
          c.node.conversations.isNotEmpty &&
          c.node.conversations.every(
            (row) => idle(row['conversationId'] as String),
          ),
      seconds: 240,
      what: 'node online and introductions finished',
    );

    // An earlier interrupted run may have left the invalid key from the last step.
    await command('/restore-source');

    // Group relay: both members start their turns; no run re-applies the model.
    await command('/mark');
    await open(group);
    var before = ids(group);
    await submit('@everyone 每位成员各自用实际工具计算 11 * 13，然后只回复结果。不要提及其他成员，不要接力。');
    await until(
      () =>
          messages(group)
                  .where(
                    (m) =>
                        !before.contains(m.messageId) &&
                        m.kind == 'text' &&
                        m.author.type == 'bot' &&
                        m.status == 'done' &&
                        '${m.content['text']}'.contains('143'),
                  )
                  .map((m) => m.author.id)
                  .toSet()
                  .length ==
              2 &&
          idle(group),
      seconds: 420,
      what: 'both members replied',
    );
    expect(
      messages(group)
          .where((m) => !before.contains(m.messageId) && m.status == 'failed'),
      isEmpty,
    );
    final relayCalls = managementSinceMark();
    expect(relayCalls, isNot(contains('/api/model/set')));
    report['relayModelSetCalls'] = 0;
    await shot('group-relay');

    // A program delivered by a Bot is refused by Open, marked, and never runs.
    await open(dm);
    final marker = '$work\\ran-${DateTime.now().millisecondsSinceEpoch}.txt';
    before = ids(dm);
    await submit(
      '用 terminal 工具写一个批处理文件 $work\\files\\run-me.bat（目录不存在就先创建），内容只有一行：'
      '@echo ran> "$marker"。不要运行它。回复里用单独一行 MEDIA:<文件的绝对路径> 把它发给我。',
    );
    final delivery = await reply(
      dm,
      before,
      (m) => (m.content['files'] as List?)?.isNotEmpty == true,
      what: 'run-me.bat delivered',
    );
    final file = await tester.runAsync(
      () => c.rpc('files.get', {
        'fileId': (delivery.content['files'] as List).first,
      }),
    );
    expect('${file!['name']}', endsWith('.bat'));
    final card = find.byWidgetPredicate(
      (w) => w is FileCard && w.fileId == file['fileId'],
    );
    await until(() => card.evaluate().isNotEmpty, what: 'file card');
    await tester.ensureVisible(card);
    await tester.tap(card);
    await until(
      () => find.byKey(const ValueKey('viewer-open')).evaluate().isNotEmpty,
      what: 'file viewer',
    );
    await tester.tap(find.byKey(const ValueKey('viewer-open')));
    await until(
      () => find.byKey(const ValueKey('open-default')).evaluate().isNotEmpty,
      what: 'open menu',
    );
    await tester.tap(find.byKey(const ValueKey('open-default')));
    final refused = find.descendant(
      of: find.byType(FileViewer),
      matching: find.byType(ErrorNotice),
    );
    await until(
      () =>
          refused.evaluate().isNotEmpty &&
          tester.widget<ErrorNotice>(refused).text == '程序和脚本不能直接打开',
      seconds: 30,
      what: 'Open refused',
    );
    await shot('open-refused');
    final temporary = await getTemporaryDirectory();
    final copy = Directory('${temporary.path}\\nekodot-files')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith(safeFileName('${file['name']}')))
        .reduce(
          (a, b) => a.lastModifiedSync().isAfter(b.lastModifiedSync()) ? a : b,
        );
    expect(
      File('${copy.path}:Zone.Identifier').readAsStringSync(),
      contains('ZoneId=3'),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    expect(File(marker).existsSync(), isFalse, reason: 'the program ran');
    report['openRefused'] = '${file['name']}';
    await tester.tap(
      find.descendant(
        of: find.byType(FileViewer),
        matching: find.byTooltip('关闭'),
      ),
    );
    await until(() => find.byType(FileViewer).evaluate().isEmpty);

    // Hermes hangs when a turn starts: the client shows its own short copy.
    before = ids(dm);
    await command('/suspend-gateway');
    await submit('只回复：收到');
    final failed = await reply(
      dm,
      before,
      (m) => m.status == 'failed',
      seconds: 120,
      what: 'run start failure',
    );
    await command('/resume-gateway');
    expect(failed.content['failureCode'], 'run_start');
    await until(
      () => find.text('无法开始，请检查模型来源后重试').evaluate().isNotEmpty,
      what: 'localized run start failure',
    );
    await shot('run-start-failed');
    before = ids(dm);
    await submit('只回复：恢复成功');
    final answer = await reply(
      dm,
      before,
      (_) => true,
      what: 'reply after Hermes resumed',
    );
    expect(answer.status, 'done');
    expect('${answer.content['text']}', contains('恢复成功'));
    await shot('recovered');

    // A source edited in Settings reaches its Bots when saved, not per run.
    await command('/mark');
    await tester.tap(find.byTooltip('设置').hitTestable().first);
    await until(
      () =>
          find.byKey(const ValueKey('settings-sources')).evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('settings-sources')));
    await until(() => find.text('Cursor QA').evaluate().isNotEmpty);
    await tester.tap(find.text('Cursor QA'));
    final keyField = find.byWidgetPredicate(
      (w) => w is TextField && w.obscureText,
    );
    await until(() => keyField.evaluate().isNotEmpty, what: 'source page');
    await tester.enterText(keyField, 'sk-cursor-qa-invalid');
    final save = find.widgetWithText(FilledButton, '保存');
    await tester.tap(save);
    await until(
      () => managementSinceMark().contains('/api/model/set'),
      seconds: 90,
      what: 'source applied to its Bots on save',
    );
    // The page refreshes the model catalog after saving, then leaves or shows the error.
    await until(
      () =>
          save.evaluate().isEmpty ||
          tester.widget<FilledButton>(save).onPressed != null,
      seconds: 90,
      what: 'source page settled',
    );
    await shot('source-saved');
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .popUntil((route) => route.isFirst);
    await tester.pump(const Duration(milliseconds: 600));
    await open(dm);
    await command('/mark');
    before = ids(dm);
    await submit('只回复：A');
    final rejected = await reply(
      dm,
      before,
      (_) => true,
      what: 'run with the invalid key',
    );
    expect(rejected.status, 'failed');
    expect(managementSinceMark(), isNot(contains('/api/model/set')));
    await shot('invalid-key-run');
    await command('/restore-source');
    await command('/mark');
    before = ids(dm);
    await submit('只回复：B');
    final restored = await reply(
      dm,
      before,
      (_) => true,
      what: 'run with the restored key',
    );
    expect(restored.status, 'done');
    expect('${restored.content['text']}', contains('B'));
    expect(managementSinceMark(), isNot(contains('/api/model/set')));
    report['sourceAppliedOnSave'] = true;

    binding.reportData = report;
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
