import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/bot_editor.dart';
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

    // Every menu and select is the same card: icon, words, row height.
    final rowHeight = android ? 44.0 : 36.0;
    double heightOf(String words) => tester
        .getSize(
          find
              .ancestor(
                of: find.text(words).last,
                matching: find.byType(InkWell),
              )
              .first,
        )
        .height;
    await tap(find.byTooltip('新建').first);
    await settle(400);
    expect(heightOf('新建 Bot'), rowHeight);
    await shot('menu-create');
    await tap(find.text('新建 Bot').last);
    await until(
      () => find.byType(BotEditor).evaluate().isNotEmpty,
      what: 'Bot editor',
    );
    final approval = find.byKey(const ValueKey('approval-mode'));
    await until(
      () =>
          approval.evaluate().isNotEmpty &&
          tester.widget<MenuSelect<String>>(approval).onChanged != null,
      what: 'approval select ready',
    );
    await tap(approval);
    await settle(400);
    expect(heightOf('智能审批'), rowHeight);
    await shot('menu-select');
    Navigator.of(tester.element(find.text('智能审批').last)).pop();
    await settle(400);
    await tester.pageBack();
    await settle(600);
    if (!android) {
      await tap(find.byTooltip('账户'));
      await settle(400);
      expect(heightOf('设置'), rowHeight);
      await shot('menu-account');
      Navigator.of(tester.element(find.text('设置').last)).pop();
      await settle(400);
    }
    note('menuRowHeight', rowHeight);

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
    // Ctrl+Enter only starts a new line; Enter while an input method is
    // composing is the input method's; Enter sends.
    final field = tester.widget<TextField>(input).controller!;
    // At rest the composer is a narrow capsule; typing opens it wider.
    final capsule = find.byKey(const ValueKey('composer-card'));
    field.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(700);
    final restWidth = tester.getSize(capsule).width;
    expect(restWidth, lessThanOrEqualTo(320));
    expect(find.byKey(const ValueKey('composer-model')), findsNothing);
    await tap(input);
    await settle(700);
    final openWidth = tester.getSize(capsule).width;
    expect(openWidth, greaterThan(restWidth));
    expect(openWidth, lessThanOrEqualTo(480));
    note('composerWidths', [restWidth, openWidth]);
    expect(find.byKey(const ValueKey('composer-model')), findsNothing);
    expect(
      tester.getCenter(find.byKey(const ValueKey('composer-attach'))).dx,
      greaterThan(tester.getCenter(capsule).dx),
    );
    await shot('composer-actions');
    await tap(input);
    field.value = const TextEditingValue(
      text: '第一行',
      selection: TextSelection.collapsed(offset: 3),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(300);
    expect(field.text, '第一行\n');
    field.value = const TextEditingValue(
      text: 'zhong',
      selection: TextSelection.collapsed(offset: 5),
      composing: TextRange(start: 0, end: 5),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(1500);
    expect(field.text, 'zhong');
    expect(messages().where((m) => !seen.contains(m['messageId'])), isEmpty);
    field.value = const TextEditingValue(
      text: task,
      selection: TextSelection.collapsed(offset: task.length),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await until(
      () => messages().any(
        (m) =>
            !seen.contains(m['messageId']) &&
            m['author']['type'] == 'user' &&
            m['content']['text'] == task,
      ),
      what: 'Enter sent the task',
    );
    note('keys', 'Enter sends; Ctrl+Enter new line; composing Enter kept');

    // While it works, the row above the composer says, in the Bot's own
    // words, what it is doing.
    final name = '${bot['displayName']}';
    final statuses = <String>[];
    final row = find.byKey(const ValueKey('thinking-row'));
    String? rowLine() {
      final texts = find
          .descendant(of: row, matching: find.byType(Text))
          .evaluate();
      return texts.isEmpty ? null : (texts.last.widget as Text).data;
    }

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
      final text = idle() ? null : rowLine();
      if (text != null && statuses.lastOrNull != text) {
        statuses.add(text);
        debugPrint('QA status: $text');
        if (!liveShot && text != '$name 正在思考') {
          liveShot = true;
          await shot('working');
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
    // Every line was the Bot's name and what it was doing, and at least one
    // was a line the Bot wrote itself.
    expect(statuses, isNotEmpty);
    expect(statuses.every((s) => s.startsWith(name)), isTrue);
    final own = [
      for (final m in messages().where(
        (m) => !seen.contains(m['messageId']) && m['kind'] == 'commentary',
      ))
        '${m['content']['text']}'
            .trim()
            .split('\n')
            .first
            .replaceAll(RegExp(r'[*_`#>]+'), '')
            .replaceAll(RegExp(r'[。.：:…!！]+$'), '')
            .trim(),
    ].where((w) => w.isNotEmpty).toList();
    note('ownLines', own);
    expect(
      statuses.any((s) => own.any((w) => s.endsWith(w))),
      isTrue,
      reason: 'the row showed what the Bot wrote',
    );

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

    // A drawing the Bot makes shows as a drawing in the chat and in the
    // viewer, its source a tap away; on Windows the viewer hands it to the
    // system too.
    final before = messages().map((m) => m['messageId']).toSet();
    const drawingTask =
        '用 terminal 工具在你的工作目录里写一个 SVG 文件 badge.svg：240x120，'
        '一个圆角矩形，用从橙色到紫色的线性渐变填充，中间写白色文字 nekodot。'
        '回复里用单独一行 MEDIA:<文件的绝对路径> 把它发给我，再写一句“图发你了”。';
    await tap(input);
    field.value = const TextEditingValue(
      text: drawingTask,
      selection: TextSelection.collapsed(offset: drawingTask.length),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    Json? drawing;
    final drawingEnd = DateTime.now().add(const Duration(seconds: 420));
    while (DateTime.now().isBefore(drawingEnd)) {
      final pending = messages()
          .where((m) => m['kind'] == 'approval' && m['status'] == 'streaming')
          .lastOrNull;
      final allow = pending == null
          ? null
          : find.byKey(ValueKey('choice-${pending['messageId']}-0'));
      if (allow != null && allow.evaluate().isNotEmpty) {
        await tap(allow);
        continue;
      }
      drawing = messages()
          .where(
            (m) =>
                !before.contains(m['messageId']) &&
                m['kind'] == 'text' &&
                m['status'] == 'done' &&
                (m['content']['files'] as List?)?.isNotEmpty == true,
          )
          .lastOrNull;
      if (drawing != null && idle()) break;
      await tester.pump(const Duration(milliseconds: 150));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    expect(drawing, isNotNull, reason: 'the Bot delivered the drawing');
    final delivered = [
      for (final fileId in drawing!['content']['files'] as List)
        await client.rpc('files.get', {'fileId': fileId}),
    ];
    final svgFile = delivered.firstWhere(isSvg);
    note('drawing', {'name': svgFile['name'], 'mime': svgFile['mime']});
    final drawingCard = find.byWidgetPredicate(
      (w) => w is FileCard && w.fileId == svgFile['fileId'],
    );
    final drawn = find.descendant(
      of: drawingCard,
      matching: find.byType(SvgPicture),
    );
    await until(() => drawn.evaluate().isNotEmpty, what: 'drawing in chat');
    await reveal(drawingCard);
    await shot('drawing-chat');
    await tap(drawn);
    final viewerDrawing = find.byKey(const ValueKey('viewer-svg'));
    await until(
      () => viewerDrawing.evaluate().isNotEmpty,
      what: 'drawing in the viewer',
    );
    expect(
      find.descendant(of: viewerDrawing, matching: find.byType(SvgPicture)),
      findsOneWidget,
    );
    expect(find.byType(Dialog), findsOneWidget);
    await shot('viewer-drawing');
    await tap(find.byKey(const ValueKey('viewer-svg-source')));
    final source = find.byKey(const ValueKey('viewer-text'));
    await until(() => source.evaluate().isNotEmpty, what: 'drawing source');
    expect(tester.widget<SelectableText>(source).data, contains('<svg'));
    await shot('viewer-drawing-source');
    if (!android) {
      await tap(find.byKey(const ValueKey('viewer-open')));
      await until(
        () => find.byKey(const ValueKey('open-folder')).evaluate().isNotEmpty,
        what: 'open menu',
      );
      expect(find.byKey(const ValueKey('open-default')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-with')), findsOneWidget);
      await shot('viewer-open-menu');
      await tap(find.byKey(const ValueKey('open-folder')));
      await settle(2500);
      final failed = find.descendant(
        of: find.byType(FileViewer),
        matching: find.byType(ErrorNotice),
      );
      if (failed.evaluate().isNotEmpty) {
        note('openError', tester.widget<ErrorNotice>(failed).text);
      }
      expect(failed, findsNothing);
      final temporary = await getTemporaryDirectory();
      final copies = Directory('${temporary.path}/nekodot-files')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith(safeFileName('${svgFile['name']}')))
          .toList();
      expect(copies, isNotEmpty);
      note(
        'shownInFolder',
        copies.last.path.split(Platform.pathSeparator).last,
      );
    }
    await tap(
      find.descendant(
        of: find.byType(FileViewer),
        matching: find.byTooltip('关闭'),
      ),
    );
    await until(() => find.byType(FileViewer).evaluate().isEmpty);
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
