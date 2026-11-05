import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/chat.dart';
import 'package:nekodot_native/features/files.dart';
import 'package:nekodot_native/features/work.dart';
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

const email = String.fromEnvironment('QA_EMAIL');
const password = String.fromEnvironment('QA_PASSWORD');
const runtimeFolder = String.fromEnvironment('QA_RUNTIME_DIR');
const dataFolder = String.fromEnvironment('QA_DATA_DIR');
const workFolder = String.fromEnvironment('QA_WORK_DIR');
const evidenceFolder = String.fromEnvironment('QA_EVIDENCE_DIR');
const hold = bool.fromEnvironment('QA_HOLD');

/// While a Bot works on a real task with official Hermes and a real model,
/// the line below your message says what it is doing; its steps fold under
/// that line, an approval shows its command as one line, and files open in a
/// floating viewer over the chat. The Windows run hosts the node; the Android
/// run connects while it holds.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('steps under a status line and files in a floating viewer', (
    tester,
  ) async {
    final android = Platform.isAndroid;
    final report = <String, Object?>{'platform': Platform.operatingSystem};
    void note(String key, Object? value) {
      report[key] = value;
      debugPrint('QA $key: ${jsonEncode(value)}');
    }

    SharedPreferences.setMockInitialValues({});
    final client = NekodotClient(vault: MemoryVault());
    LocalRuntime? local;
    if (!android) {
      await LocalLocation(runtimeFolder, dataFolder).save();
      local = localRuntime = LocalRuntime(client);
      addTearDown(() => local!.stop());
      await DesktopHost.initialize();
      tester.view.physicalSize = const Size(2880, 2000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
    }

    Future<void> until(
      bool Function() done, {
      int seconds = 90,
      String what = '',
    }) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!done() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 200));
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      expect(done(), isTrue, reason: 'Did not reach: $what');
    }

    Future<void> settle([int ms = 500]) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 40));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    // Centred: the chat list runs under the composer, so an item scrolled
    // only to the list's edge can sit behind it.
    Future<void> reveal(Finder finder) =>
        Scrollable.ensureVisible(tester.element(finder.first), alignment: .5);

    Future<void> tap(Finder finder) async {
      await reveal(finder);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(finder.hitTestable().first);
      await settle(450);
    }

    var converted = false;
    Future<void> shot(String name) async {
      await settle(800);
      if (android) {
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
          await tester.pump();
        }
        await binding.takeScreenshot('work-steps-android-$name');
        return;
      }
      await Directory(evidenceFolder).create(recursive: true);
      final view = tester.binding.renderViews.first;
      await tester.runAsync(() async {
        // The root layer already scales by the device ratio.
        final image = await (view.debugLayer! as OffsetLayer).toImage(
          Offset.zero & view.flutterView.physicalSize,
        );
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$evidenceFolder/work-steps-windows-$name.png')
            .writeAsBytes(png!.buffer.asUint8List());
      });
    }

    runApp(NekodotApp(client: client));
    await until(
      () => find.byKey(const ValueKey('auth-email')).evaluate().isNotEmpty,
      what: 'auth page',
    );
    await settle(1500);
    final notice = find.widgetWithText(TextButton, '继续');
    if (notice.evaluate().isNotEmpty) await tap(notice);
    await tester.enterText(find.byKey(const ValueKey('auth-email')), email);
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      password,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tap(find.widgetWithText(FilledButton, '登录'));
    await until(() => client.ready, what: 'signed in');
    await until(
      () =>
          client.online &&
          (local == null || local.phase == LocalPhase.online) &&
          client.node.bots.isNotEmpty,
      seconds: 600,
      what: 'real node online with its Bots',
    );
    note('node', client.selectedNodeId);
    await settle(1500);

    final bot = client.node.bots.first;
    final dm = client.node.conversations.firstWhere(
      (x) => x['kind'] == 'dm' && x['botId'] == bot['botId'],
    );
    final id = dm['conversationId'] as String;
    await tap(find.byKey(ValueKey('conversation-$id')));
    final input = find.byKey(const ValueKey('chat-input'));
    await until(() => input.evaluate().isNotEmpty, what: 'chat open');
    await until(() => client.node.messages[id] != null, what: 'history');
    await settle(800);

    List<Json> messages() => client.node.messages[id] ?? [];
    bool idle() => client.node.activities[id]?['state'] == 'idle';
    String? shown(Finder finder) {
      final found = finder.evaluate();
      if (found.isEmpty) return null;
      return (found.last.widget as Text).data;
    }

    // Files and pictures already in this chat open over it, not as a page.
    final files = [
      for (final m in messages())
        for (final fileId in (m['content']?['files'] as List? ?? []))
          await client.rpc('files.get', {'fileId': fileId}),
    ].where((f) => f['available'] == true).toList();
    // The chat shows its latest messages; a file from an older one is not there.
    final picture = files
        .where((f) => '${f['mime']}'.startsWith('image/'))
        .lastOrNull;
    final document = files
        .where((f) => '${f['mime']}' == 'text/plain')
        .lastOrNull;
    if (picture == null || document == null) {
      note('viewerSkipped', 'no file in the latest messages');
    } else {
      Finder card(Json f) => find.byWidgetPredicate(
        (w) => w is FileCard && w.fileId == f['fileId'],
      );
      // Earlier in the chat: scroll up to them first.
      final list = find
          .descendant(
            of: find.byKey(const ValueKey('chat-messages')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(card(picture), 400, scrollable: list);
      await settle(500);
      await tap(card(picture));
      await until(
        () => find.byKey(const ValueKey('viewer-image')).evaluate().isNotEmpty,
        what: 'picture in the viewer',
      );
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(ChatPage), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(FileViewer),
          matching: find.byType(Dialog),
        ),
        findsOneWidget,
      );
      await shot('viewer-picture');
      await tap(
        find.descendant(
          of: find.byType(FileViewer),
          matching: find.byTooltip('关闭'),
        ),
      );
      await until(() => find.byType(FileViewer).evaluate().isEmpty);
      await tester.scrollUntilVisible(card(document), -200, scrollable: list);
      await tap(card(document));
      await until(
        () => find.byKey(const ValueKey('viewer-text')).evaluate().isNotEmpty,
        what: 'text in the viewer',
      );
      expect(find.byType(Dialog), findsOneWidget);
      await shot('viewer-text');
      await tap(
        find.descendant(
          of: find.byType(FileViewer),
          matching: find.byTooltip('关闭'),
        ),
      );
      await until(() => find.byType(FileViewer).evaluate().isEmpty);
      note('viewerFloats', true);
    }

    // A new conversation with the Bot, so it starts from the rules as they now
    // are: an open conversation keeps the rules it started with.
    await tester.runAsync(
      () => client.rpc('commands.execute', {
        'conversationId': id,
        'botId': bot['botId'],
        'command': '/new',
        'clientMsgId': uid(),
      }),
    );
    await until(idle, seconds: 120, what: 'new conversation');
    await settle(800);

    // A task with steps: the box below the message says what the Bot is
    // doing while it works, with every step folded under it.
    // An earlier run cut off mid-task waits for Stop to be acknowledged.
    if (client.node.activities[id]?['state'] == 'unknown') {
      await tap(find.byTooltip('停止'));
    }
    await until(idle, seconds: 300, what: 'idle before sending');
    final seen = messages().map((m) => m['messageId']).toSet();
    const task =
        '请看一下 https://nekodot.com 首页的大标题写了什么，'
        '再用 terminal 工具（不要用 execute_code）运行 python -c "print(6*7)"。'
        '做完用一句话告诉我标题和计算结果。';
    await tap(input);
    tester.widget<TextField>(input).controller!.text = task;
    await tester.pump();
    await tap(find.byTooltip('发送'));
    final statuses = <String>[];
    final status = find.descendant(
      of: find.byWidgetPredicate((w) => w is WorkBlock && w.live),
      matching: find.byKey(const ValueKey('work-status')),
    );
    final thinking = find.byKey(const ValueKey('thinking-status'));
    var liveShot = false, approvals = 0;
    Json? reply() => messages()
        .where(
          (m) =>
              !seen.contains(m['messageId']) &&
              m['author']['type'] == 'bot' &&
              m['kind'] == 'text' &&
              m['status'] == 'done',
        )
        .lastOrNull;
    final end = DateTime.now().add(const Duration(seconds: 420));
    while ((reply() == null || !idle()) && DateTime.now().isBefore(end)) {
      final working = !idle();
      final text = !working
          ? null
          : status.evaluate().isNotEmpty
          ? (find
                        .descendant(
                          of: status.first,
                          matching: find.byType(Text),
                        )
                        .evaluate()
                        .first
                        .widget
                    as Text)
                .data
          : shown(thinking);
      {
        if (text != null && statuses.lastOrNull != text) {
          statuses.add(text);
          debugPrint('QA status: $text');
          if (!liveShot && text.startsWith('正在')) {
            liveShot = true;
            await shot('working');
          }
        }
      }
      final pending = messages()
          .where((m) => m['kind'] == 'approval' && m['status'] == 'streaming')
          .lastOrNull;
      final allow = pending == null
          ? null
          : find.byKey(ValueKey('choice-${pending['messageId']}-0'));
      if (allow != null && allow.evaluate().isNotEmpty) {
        final fold = find.descendant(
          of: find.byWidgetPredicate(
            (w) =>
                w is MessageTile &&
                w.message['messageId'] == pending!['messageId'],
          ),
          matching: find.byKey(const ValueKey('command-fold')),
        );
        if (approvals++ == 0 &&
            object(pending!['content'])['command'] != null) {
          // The command shows as one line until opened.
          expect(fold, findsOneWidget);
          expect(
            tester
                .widget<Text>(
                  find.descendant(of: fold, matching: find.byType(Text)).first,
                )
                .maxLines,
            1,
          );
          await reveal(fold);
          await shot('approval-folded');
          await tap(fold);
          // Opened, the whole command is there to read and select.
          expect(
            find.descendant(of: fold, matching: find.byType(SelectableText)),
            findsNothing,
          );
          expect(
            find.descendant(
              of: find.byWidgetPredicate(
                (w) =>
                    w is MessageTile &&
                    w.message['messageId'] == pending['messageId'],
              ),
              matching: find.byType(SelectableText),
            ),
            findsOneWidget,
          );
          await shot('approval-open');
        }
        await tap(allow);
        continue;
      }
      await tester.pump(const Duration(milliseconds: 150));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    note('statuses', statuses);
    expect(reply(), isNotNull, reason: 'Bot replied');
    final steps = messages()
        .where((m) => !seen.contains(m['messageId']) && m['kind'] == 'tool')
        .toList();
    note('steps', [
      for (final s in steps)
        {'tool': s['content']['tool'], 'context': s['content']['context']},
    ]);
    expect(steps, isNotEmpty);
    expect(
      steps.any((s) => '${s['content']['context'] ?? ''}'.isNotEmpty),
      isTrue,
    );
    // While it worked, the line said what it was doing, not dots.
    expect(
      statuses.any((s) => s != '思考中…'),
      isTrue,
      reason: 'a status other than thinking',
    );
    expect(find.byType(ThinkingDots), findsNothing);

    // Done: one line with the count, the steps folded until opened.
    final box = find.byWidgetPredicate(
      (w) =>
          w is WorkBlock &&
          w.steps.any((s) => s['messageId'] == steps.first['messageId']),
    );
    await until(() => box.evaluate().isNotEmpty, what: 'work box');
    final summary = find.descendant(
      of: box,
      matching: find.byKey(const ValueKey('work-status')),
    );
    final line = shown(
      find.descendant(of: summary, matching: find.byType(Text)),
    )!;
    note('summary', line);
    expect(line, contains('个步骤'));
    expect(
      find.descendant(of: box, matching: find.byType(StepRow)),
      findsNothing,
    );
    await reveal(box);
    await shot('done-folded');
    await tap(summary);
    expect(
      find.descendant(of: box, matching: find.byType(StepRow)),
      findsNWidgets(steps.length),
    );
    final labels = [
      for (final row
          in find
              .descendant(of: box, matching: find.byType(StepRow))
              .evaluate())
        stepLabel(client, object((row.widget as StepRow).message['content'])),
    ];
    note('labels', labels);
    expect(labels.any((l) => l.startsWith('{')), isFalse);
    await reveal(box);
    await shot('done-open');
    expect(tester.takeException(), isNull);

    if (!android && hold) {
      // A new name each run, so an earlier marker never releases this one.
      final release = File(
        '$workFolder/hold-release-${DateTime.now().millisecondsSinceEpoch}',
      );
      debugPrint('QA holding for Android; create ${release.path} to finish');
      await until(
        () => release.existsSync(),
        seconds: 1800,
        what: 'hold released',
      );
    }
    note('done', true);
    if (!android && evidenceFolder.isNotEmpty) {
      await File('$evidenceFolder/work-steps-windows.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    }
    debugPrint('QA REPORT ${jsonEncode(report)}');
  }, timeout: const Timeout(Duration(minutes: 60)));
}
