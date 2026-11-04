import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/bot_editor.dart';
import 'package:nekodot_native/local/location.dart';
import 'package:nekodot_native/local/runtime.dart';
import 'package:nekodot_native/main.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the installed client's saved login untouched.
class MemoryVault extends FlutterSecureStorage {
  final values = <String, String>{};
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values.remove(key);
}

const relay = String.fromEnvironment('RELAY_URL');
const phase = String.fromEnvironment('QA_PHASE', defaultValue: 'first');
const runtimeFolder = String.fromEnvironment('QA_RUNTIME_DIR');
const dataFolder = String.fromEnvironment('QA_DATA_DIR');
const workFolder = String.fromEnvironment('QA_WORK_DIR');
const account = String.fromEnvironment('QA_ACCOUNT');

/// `first` and `retry` start from a new account and empty folders; `retry` cancels mid-install.
const fresh = phase == 'first' || phase == 'retry';
const evidenceFolder = String.fromEnvironment('QA_EVIDENCE_DIR');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('install, pair and use a node on this Windows computer', (
    tester,
  ) async {
    final report = <String, Object?>{
      'phase': phase,
      'started': DateTime.now().toIso8601String(),
    };
    void note(String key, Object? value) {
      report[key] = value;
      debugPrint('QA $key: $value');
    }

    SharedPreferences.setMockInitialValues({});
    final accountFile = File(account);
    final credentials = fresh
        ? {
            'email':
                'local-${DateTime.now().millisecondsSinceEpoch}@example.test',
            'password':
                'local-desktop-${DateTime.now().microsecondsSinceEpoch}',
          }
        : {
            for (final entry in (jsonDecode(
              await accountFile.readAsString(),
            ) as Map).entries)
              if (entry.value is String) '${entry.key}': entry.value as String,
          };
    await LocalLocation(runtimeFolder, dataFolder).save();
    if (fresh) {
      await accountFile.writeAsString(jsonEncode(credentials));
    }
    final client = NekodotClient(vault: MemoryVault());
    final local = localRuntime = LocalRuntime(client);
    addTearDown(() => local.stop());
    await DesktopHost.initialize();

    final seen = <String>{};
    void trace() {
      for (final step in local.steps) {
        final line = '${step.id}:${step.state}';
        if (step.state != 'pending' && seen.add(line)) {
          debugPrint(
            'QA step $line ${DateTime.now().toIso8601String()} ${step.detail}',
          );
        }
      }
    }

    local.addListener(trace);

    Future<void> until(
      bool Function() done, {
      int seconds = 120,
      String what = '',
      bool stopOnFailure = true,
    }) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!done() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 250));
        await Future<void>.delayed(const Duration(milliseconds: 150));
        if (stopOnFailure && local.phase == LocalPhase.failed) break;
      }
      if (!done()) {
        for (final element in find.byType(ErrorNotice).evaluate()) {
          debugPrint(
            'QA visible error: ${(element.widget as ErrorNotice).text}',
          );
        }
        debugPrint(
          'QA local phase ${local.phase} ${local.failedStep}: ${local.error}',
        );
      }
      expect(done(), isTrue, reason: 'Did not reach: $what');
    }

    Future<Map<String, dynamic>> qa(String path, {Object? body}) async {
      final uri = Uri.parse('$relay$path');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${client.token}',
      };
      final response = body == null
          ? await http.get(uri, headers: headers)
          : await http.post(uri, headers: headers, body: jsonEncode(body));
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    Future<String> ownedProcesses() async {
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-Command',
        "@(Get-CimInstance Win32_Process | Where-Object { \$_.ExecutablePath -like '$runtimeFolder\\*' }).Count",
      ]);
      return '${result.stdout}'.trim();
    }

    // Windows has no driver screenshot channel; render the root layer of this debug build.
    Future<void> shot(String name) async {
      await Directory(evidenceFolder).create(recursive: true);
      await tester.pump(const Duration(milliseconds: 500));
      final view = tester.binding.renderViews.first;
      await tester.runAsync(() async {
        final image = await (view.debugLayer! as OffsetLayer).toImage(
          Offset.zero & view.size,
          pixelRatio: view.flutterView.devicePixelRatio,
        );
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$evidenceFolder/local-desktop-$phase-$name.png')
            .writeAsBytes(png!.buffer.asUint8List());
      });
    }

    runApp(NekodotApp(client: client));
    await until(
      () => find.byKey(const ValueKey('auth-email')).evaluate().isNotEmpty,
      what: 'auth page',
    );
    await tester.pump(const Duration(seconds: 2));
    final notice = find.widgetWithText(TextButton, '继续');
    if (notice.evaluate().isNotEmpty) {
      await tester.tap(notice);
      await tester.pump(const Duration(seconds: 1));
    }
    if (fresh) {
      await tester.tap(find.widgetWithText(TextButton, '创建账号'));
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      credentials['email']!,
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      credentials['password']!,
    );
    await tester.pump(const Duration(milliseconds: 300));
    if (fresh) {
      await tester.tap(find.widgetWithText(OutlinedButton, '获取验证码'));
      await until(
        () => find.textContaining('验证码已发出').evaluate().isNotEmpty,
        what: 'code sent',
      );
      final code = (await qa('/qa/code'))['code'] as String;
      await tester.enterText(find.widgetWithText(TextField, '6 位验证码'), code);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(FilledButton, '验证并继续'));
    } else {
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
    }
    await until(() => client.ready, what: 'signed in');
    note('signedIn', DateTime.now().toIso8601String());

    if (fresh) {
      await until(
        () => find.byTooltip('添加电脑').evaluate().isNotEmpty,
        what: 'empty team',
      );
      await tester.tap(find.byTooltip('添加电脑').last);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const ValueKey('run-here')));
      await tester.pump(const Duration(seconds: 1));
      await until(
        () => find.textContaining(runtimeFolder).evaluate().isNotEmpty,
        what: 'chosen folders shown',
      );
      await until(() {
        final button = find.byKey(const ValueKey('start-local'));
        return button.evaluate().isNotEmpty &&
            tester.widget<FilledButton>(button).onPressed != null;
      }, what: 'folders accepted');
      await shot('folders');
      final started = DateTime.now();
      await tester.tap(find.byKey(const ValueKey('start-local')));
      if (phase == 'retry') {
        const download = bool.fromEnvironment('QA_CANCEL_DOWNLOAD');
        const stage = download ? 'node' : 'python-deps';
        await until(
          () => local.steps.any(
            (s) =>
                s.id == stage &&
                s.state == 'running' &&
                (!download || s.detail.endsWith('%')),
          ),
          seconds: 900,
          what: 'requested install stage running',
        );
        if (!download) await tester.pump(const Duration(seconds: 20));
        await tester.ensureVisible(find.byKey(const ValueKey('cancel-local')));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byKey(const ValueKey('cancel-local')));
        await until(
          () => local.phase == LocalPhase.failed,
          seconds: 120,
          what: 'cancelled install',
          stopOnFailure: false,
        );
        final kept = [
          for (final s in local.steps)
            if (s.state == 'done') s.id,
        ];
        note('cancelledAt', local.failedStep);
        note('cancelError', local.error);
        note('keptAfterCancel', kept);
        await shot('cancelled');
        await tester.ensureVisible(find.byKey(const ValueKey('start-local')));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byKey(const ValueKey('start-local')));
        await until(
          () => local.phase != LocalPhase.failed,
          seconds: 10,
          what: 'retry started',
          stopOnFailure: false,
        );
        note('resumedSkips', [
          for (final s in local.steps)
            if (s.state == 'done') s.id,
        ]);
      }
      await until(
        () => local.steps.where((s) => s.state == 'done').length >= 2,
        seconds: 900,
        what: 'install under way',
      );
      await shot('installing');
      await until(
        () =>
            local.phase == LocalPhase.online &&
            client.selectedNodeId == local.nodeId &&
            client.online,
        seconds: 5400,
        what: 'local node online and selected',
      );
      note('installMinutes', DateTime.now().difference(started).inSeconds / 60);
      await tester.pump(const Duration(seconds: 2));
      await shot('online');
      note('nodeId', local.nodeId);
      final paired = (objects(client.me?['nodes']))
          .firstWhere((n) => n['nodeId'] == local.nodeId);
      note('pairedPlatform', paired['platform']);

      final configured = await qa(
        '/qa/configure',
        body: {'nodeId': local.nodeId},
      );
      note('sourceConfigured', configured['ok']);
      final model = (await qa('/qa/model'))['model'] as String;
      await tester.pump(const Duration(seconds: 2));
      await until(
        () => find.byTooltip('新建 Bot').evaluate().isNotEmpty,
        what: 'new Bot entry',
      );
      await tester.tap(find.byTooltip('新建 Bot').last);
      await until(
        () => find.byType(BotEditor).evaluate().isNotEmpty,
        what: 'Bot editor',
      );
      Future<void> fill(String label, String value) async {
        final field = find.descendant(
          of: find.widgetWithText(LabeledField, label),
          matching: find.byType(TextField),
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, value);
        await tester.pump(const Duration(milliseconds: 200));
      }

      await fill('名称', '本机小助手');
      await fill('角色设定', '在用户自己的 Windows 电脑上帮忙整理文件，回答简洁。');
      await until(
        () => find.widgetWithText(LabeledField, '模型').evaluate().isNotEmpty,
        what: 'model field',
      );
      await fill('模型', model);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 300));
      final save = find.widgetWithText(FilledButton, '保存');
      await tester.ensureVisible(save);
      await until(
        () => tester.widget<FilledButton>(save).onPressed != null,
        what: 'save enabled',
      );
      await tester.tap(save);
      await until(
        () => client.node.bots.isNotEmpty,
        seconds: 300,
        what: 'Bot created',
      );
      note('botId', client.node.bots.first['botId']);
    }

    // Every phase: chat with real tools against real files on this computer.
    await until(
      () =>
          local.phase == LocalPhase.online &&
          client.online &&
          client.node.conversations.isNotEmpty,
      seconds: 600,
      what: 'local node online with its conversation',
    );
    final conversationId =
        client.node.conversations.first['conversationId'] as String;
    await client.loadMessages(conversationId);
    final history = [
      for (final m in client.node.messages[conversationId] ?? [])
        m['messageId'],
    ];
    note('historyBefore', history.length);
    if (!fresh) {
      final recorded =
          (jsonDecode(await accountFile.readAsString()) as Map)['messages']
              as List?;
      note('historyKept', recorded == null || recorded.every(history.contains));
      note(
        'sameNode',
        local.nodeId ==
            (jsonDecode(await accountFile.readAsString()) as Map)['nodeId'],
      );
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final marker = 'NEKODOT_LOCAL_${phase.toUpperCase()}_$stamp';
    final target = '$workFolder\\本机验收-$phase.txt';
    await Directory(workFolder).create(recursive: true);
    final source = File('$workFolder\\来源-$phase.txt');
    await source.writeAsString('第一行：$marker\n第二行：这是用户电脑上的真实文件。\n');
    // Let navigation transitions settle before tapping, then send through the real composer.
    await tester.pump(const Duration(seconds: 3));
    if (find
        .byKey(const ValueKey('chat-input'))
        .hitTestable()
        .evaluate()
        .isEmpty) {
      final row = find
          .byKey(ValueKey('conversation-$conversationId'))
          .hitTestable();
      await until(() => row.evaluate().isNotEmpty, what: 'conversation row');
      await tester.tap(row);
      await tester.pump(const Duration(seconds: 2));
    }
    final input = find.byKey(const ValueKey('chat-input')).hitTestable();
    await until(() => input.evaluate().isNotEmpty, what: 'chat input');
    final before = history.toSet();
    await tester.enterText(
      input,
      '请用文件工具读取 ${source.path} ，然后把它的第一行原样写进新文件 $target ，最后回复你写入的那一行。',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await shot('composer');
    // A fresh Bot is usually still introducing itself here; the send must steer that run.
    final welcome = (client.node.messages[conversationId] ?? [])
        .where((m) => m['content']['welcome'] == true)
        .lastOrNull;
    note('sentDuringWelcome', {
      'activity': client.node.activities[conversationId]?['state'],
      'welcome': welcome?['status'],
    });
    await tester.tap(find.byTooltip('发送').hitTestable().last);
    await until(
      () => (client.node.messages[conversationId] ?? []).any(
        (m) =>
            !before.contains(m['messageId']) && m['author']['type'] == 'user',
      ),
      seconds: 30,
      what: 'user message sent',
    );
    bool replied() => (client.node.messages[conversationId] ?? []).any(
      (m) =>
          !before.contains(m['messageId']) &&
          m['author']['type'] == 'bot' &&
          m['kind'] == 'text' &&
          m['status'] == 'done' &&
          '${m['content']['text']}'.contains(marker),
    );
    var approvals = 0;
    final deadline = DateTime.now().add(const Duration(minutes: 10));
    while (!replied() && DateTime.now().isBefore(deadline)) {
      final allow = find.text('允许一次');
      if (allow.evaluate().isNotEmpty) {
        await tester.ensureVisible(allow.first);
        await tester.tap(allow.first);
        approvals++;
        await tester.pump(const Duration(seconds: 2));
      }
      await tester.pump(const Duration(milliseconds: 250));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    note('approvals', approvals);
    await tester.pump(const Duration(seconds: 2));
    await shot('chat');

    expect(replied(), isTrue, reason: 'real model reply with the written line');
    final tools = (client.node.messages[conversationId] ?? [])
        .where((m) => !before.contains(m['messageId']) && m['kind'] == 'tool')
        .map((m) => '${m['content']['tool']}:${m['status']}')
        .toList();
    note('tools', tools);
    final written = await File(target).readAsString();
    note('fileWritten', written.contains(marker));
    expect(written, contains(marker));

    // A second message from the same composer, once the first turn is idle, is its own turn.
    await until(
      () => client.node.activities[conversationId]?['state'] == 'idle',
      what: 'first turn idle',
    );
    final second = 'NEKODOT_SECOND_$stamp';
    final beforeSecond = {
      for (final m in client.node.messages[conversationId] ?? [])
        m['messageId'],
    };
    await tester.tap(input);
    await tester.enterText(input, '只回复这一行，不要使用工具：$second');
    await tester.pump(const Duration(milliseconds: 500));
    final sendButton = tester.widget<IconButton>(
      find
          .byWidgetPredicate((w) => w is IconButton && w.tooltip == '发送')
          .hitTestable()
          .last,
    );
    note('secondSendEnabled', sendButton.onPressed != null);
    await tester.tap(find.byTooltip('发送').hitTestable().last);
    await until(
      () => (client.node.messages[conversationId] ?? []).any(
        (m) =>
            !beforeSecond.contains(m['messageId']) &&
            m['author']['type'] == 'bot' &&
            m['kind'] == 'text' &&
            m['status'] == 'done' &&
            '${m['content']['text']}'.contains(second),
      ),
      seconds: 180,
      what: 'second message answered',
    );
    note('secondAnswered', true);

    // Stop and start keep the same node, history and no repeated execution.
    final messages = [
      for (final m in client.node.messages[conversationId] ?? [])
        m['messageId'],
    ];
    await local.stop();
    note('processesAfterStop', await ownedProcesses());
    await until(
      () =>
          objects(
            client.me?['nodes'],
          ).any((n) => n['nodeId'] == local.nodeId && n['online'] == false) ||
          !client.node.online,
      seconds: 60,
      what: 'node offline after stop',
    );
    await local.start();
    await until(
      () => local.phase == LocalPhase.online && client.online,
      seconds: 600,
      what: 'restarted',
    );
    await client.loadMessages(conversationId);
    final after = [
      for (final m in client.node.messages[conversationId] ?? [])
        m['messageId'],
    ];
    note('restartKeepsHistory', messages.every(after.contains));
    note('restartAddsNothing', after.length == messages.length);
    await accountFile.writeAsString(
      jsonEncode({...credentials, 'nodeId': local.nodeId, 'messages': after}),
    );

    note('finished', DateTime.now().toIso8601String());
    binding.reportData = report;
    await File('$workFolder\\journey-$phase.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    if (const bool.fromEnvironment('QA_HOLD')) {
      // Left running so the harness can end the app abruptly and check the owned process tree.
      await File('$workFolder\\hold-ready').writeAsString('${local.nodeId}');
      final release = File('$workFolder\\hold-release');
      final end = DateTime.now().add(const Duration(hours: 1));
      while (!release.existsSync() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 500));
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      note('heldOnline', local.phase == LocalPhase.online && client.online);
    }
    await local.stop();
    note('processesAfterQuit', await ownedProcesses());
  }, timeout: const Timeout(Duration(hours: 2)));
}
