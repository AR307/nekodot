import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/local/location.dart';
import 'package:nekodot_native/local/runtime.dart';
import 'package:nekodot_native/main.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

const runtimeFolder = String.fromEnvironment('QA_RUNTIME_DIR');
const dataFolder = String.fromEnvironment('QA_DATA_DIR');
const workFolder = String.fromEnvironment('QA_WORK_DIR');
const account = String.fromEnvironment('QA_ACCOUNT');

/// Real Hermes computer_use on this Windows desktop: off by default, on through the Bot switch,
/// and interruptible with Stop. The Bot drives a Notepad window opened on a file made for it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('a Bot operates this computer only when allowed', (tester) async {
    final report = <String, Object?>{};
    void note(String key, Object? value) {
      report[key] = value;
      debugPrint('QA $key: $value');
    }

    SharedPreferences.setMockInitialValues({});
    // Other journeys on this machine move the shared pointer; this run owns its folders.
    await LocalLocation(runtimeFolder, dataFolder).save();
    final saved = jsonDecode(await File(account).readAsString()) as Map;
    final client = NekodotClient(vault: MemoryVault());
    final local = localRuntime = LocalRuntime(client);
    addTearDown(local.stop);
    await DesktopHost.initialize();

    Future<void> until(
      bool Function() done, {
      int seconds = 120,
      String what = '',
    }) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!done() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 250));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      expect(done(), isTrue, reason: 'Did not reach: $what');
    }

    runApp(NekodotApp(client: client));
    await until(
      () => find.byKey(const ValueKey('auth-email')).evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(seconds: 2));
    final notice = find.widgetWithText(TextButton, '继续');
    if (notice.evaluate().isNotEmpty) {
      await tester.tap(notice);
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      '${saved['email']}',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      '${saved['password']}',
    );
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await until(
      () =>
          local.phase == LocalPhase.online &&
          client.online &&
          client.node.bots.isNotEmpty,
      seconds: 600,
      what: 'local node online',
    );
    final botId = client.node.bots.first['botId'] as String;
    final conversationId =
        client.node.conversations.first['conversationId'] as String;
    await client.loadMessages(conversationId);
    note('capabilities', client.node.capabilities);

    final row = find
        .byKey(ValueKey('conversation-$conversationId'))
        .hitTestable();
    await tester.pump(const Duration(seconds: 2));
    if (find
        .byKey(const ValueKey('chat-input'))
        .hitTestable()
        .evaluate()
        .isEmpty) {
      await until(() => row.evaluate().isNotEmpty, what: 'conversation row');
      await tester.tap(row);
      await tester.pump(const Duration(seconds: 2));
    }

    Future<List<Json>> ask(
      String text,
      bool Function(List<Json> fresh) done, {
      bool stop = false,
    }) async {
      final before = {
        for (final m in client.node.messages[conversationId] ?? [])
          m['messageId'],
      };
      List<Json> fresh() => [
        for (final m in client.node.messages[conversationId] ?? [])
          if (!before.contains(m['messageId'])) m,
      ];
      // A desktop send button takes focus. Tap the editor as a user would before typing
      // again; integration_test does not register the simulated text-input client.
      await tester.tap(find.byKey(const ValueKey('chat-input')).hitTestable());
      await tester.enterText(
        find.byKey(const ValueKey('chat-input')).hitTestable(),
        text,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chat-input')))
            .controller!
            .text,
        text,
      );
      final sendControl = find
          .byWidgetPredicate((w) => w is IconButton && w.tooltip == '发送')
          .hitTestable()
          .last;
      note(
        'sendEnabled',
        tester.widget<IconButton>(sendControl).onPressed != null,
      );
      note('beforeSend', {
        'online': client.online,
        'activity': client.node.activities[conversationId],
        'draftLength': tester
            .widget<TextField>(find.byKey(const ValueKey('chat-input')))
            .controller!
            .text
            .length,
      });
      await tester.tap(find.byTooltip('发送').hitTestable().last);
      await tester.pump(const Duration(seconds: 1));
      note('afterSendErrors', [
        for (final e in find.byType(ErrorNotice).evaluate())
          (e.widget as ErrorNotice).text,
      ]);
      await until(
        () => fresh().any((m) => m['author']['type'] == 'user'),
        seconds: 30,
        what: 'user message stored',
      );
      final end = DateTime.now().add(const Duration(minutes: 6));
      var stopped = false;
      while (!done(fresh()) && DateTime.now().isBefore(end)) {
        final allow = find.widgetWithText(FilledButton, '允许一次').hitTestable();
        if (allow.evaluate().isNotEmpty) {
          await tester.tap(allow.first);
          note('approved', true);
          await tester.pump(const Duration(seconds: 2));
        }
        final desktopTool = fresh().any(
          (m) => m['kind'] == 'tool' && m['content']['tool'] == 'computer_use',
        );
        if (stop && !stopped && desktopTool) {
          await tester.tap(find.byTooltip('停止').hitTestable().last);
          stopped = true;
        }
        await tester.pump(const Duration(milliseconds: 250));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      expect(
        done(fresh()),
        isTrue,
        reason: 'Desktop request did not finish: $text',
      );
      return fresh();
    }

    bool idle() => client.node.activities[conversationId]?.state == 'idle';
    List<String> tools(List<Json> messages) => [
      for (final m in messages)
        if (m['kind'] == 'tool') '${m['content']['tool']}:${m['status']}',
    ];

    // 1. Off by default: the Bot has no desktop tool and says so.
    await client.rpc('bots.desktopControl', {'botId': botId, 'enabled': false});
    final denied = await ask(
      '只使用 computer_use 工具（不要用终端或文件工具）在屏幕上做任何操作；如果你没有 computer_use 工具，只回复 NO_DESKTOP_TOOL。',
      (fresh) =>
          idle() &&
          fresh.any(
            (m) =>
                m['author']['type'] == 'bot' &&
                m['kind'] == 'text' &&
                m['status'] == 'done',
          ),
    );
    note('offTools', tools(denied));
    note(
      'offReply',
      denied.lastWhere((m) => m['kind'] == 'text')['content']['text'],
    );
    expect(tools(denied).any((t) => t.startsWith('computer_use')), isFalse);

    // 2. Switched on: open a file made for this test in Notepad, type, save, close.
    final enabled = await client.rpc('bots.desktopControl', {
      'botId': botId,
      'enabled': true,
    });
    note('switchedOn', enabled['enabled']);
    final marker = 'NEKODOT_DESKTOP_${DateTime.now().millisecondsSinceEpoch}';
    final target = File('$workFolder\\桌面操作.txt');
    await target.parent.create(recursive: true);
    await target.writeAsString('');
    final done = await ask(
      '请用 computer_use 操作这台电脑：先用终端运行 notepad.exe "${target.path}" 打开这个空文件，'
      '然后用 computer_use 在记事本中输入 $marker ，按 Ctrl+S 保存，再按 Ctrl+W 关闭这个标签页。完成后回复 DESKTOP_DONE。',
      (fresh) =>
          idle() &&
          fresh.any(
            (m) =>
                m['kind'] == 'text' &&
                '${m['content']['text']}'.contains('DESKTOP_DONE'),
          ),
    );
    note('onTools', tools(done));
    final written = await target.readAsString();
    note('typedAndSaved', written.contains(marker));
    expect(written, contains(marker));
    await tester.pump(const Duration(milliseconds: 500));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    final image = await boundary.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$workFolder/desktop-control.png')
        .writeAsBytes(png!.buffer.asUint8List());
    image.dispose();

    // 3. Stop interrupts a desktop task.
    final stopped = await ask(
      '请用 computer_use 截取当前屏幕并列出所有可见窗口，然后逐个描述它们，最后回复 LONG_DONE。',
      (fresh) => idle() && fresh.any((m) => m['author']['type'] == 'bot'),
      stop: true,
    );
    note('stopTools', tools(stopped));
    note('stoppedRun', client.node.activities[conversationId]);

    await File('$workFolder\\desktop-control.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    await local.stop();
  }, timeout: const Timeout(Duration(minutes: 40)));
}
