import 'package:nekodot_native/features/chat_message.dart';
import 'package:nekodot_native/data/chat_models.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/extensions.dart';
import 'package:nekodot_native/features/files.dart';
import 'package:nekodot_native/features/secrets.dart';
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

/// What a Bot puts in the chat, on a real node with official Hermes and a
/// real model: a question, a secret request, a file and a picture; the words
/// select freely and copy; plugins sit under the plus; the sidebar resizes.
/// The Windows run hosts the node; the Android run connects while it holds.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('chat cards, pictures, selection and layout on a real node', (
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

    // Clicks into the field, then puts the words in it. The test keyboard
    // loses its connection once another field in the chat has come and gone,
    // so the words go through the field's own controller.
    Future<void> type(Finder field, String text) async {
      await tap(field);
      tester.widget<TextField>(field).controller!.text = text;
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, text);
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
        await binding.takeScreenshot('chat-cards-android-$name');
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
        await File('$evidenceFolder/chat-cards-windows-$name.png')
            .writeAsBytes(png!.buffer.asUint8List());
      });
    }

    // Copies land here instead of on this computer's clipboard.
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = object(call.arguments)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

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
    await until(() => client.connection.ready, what: 'signed in');
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

    // Skills and plugins sit under the plus, nowhere else.
    await tap(find.byTooltip('新建'));
    expect(find.text('添加插件'), findsOneWidget);
    await shot('create-menu');
    await tap(find.text('添加插件'));
    await until(
      () => find.byType(ExtensionsPage).evaluate().isNotEmpty,
      what: 'plugins open',
    );
    await until(
      () => find
          .descendant(
            of: find.byType(ExtensionsPage),
            matching: find.byType(ListTile),
          )
          .evaluate()
          .isNotEmpty,
      what: 'skills listed',
    );
    expect(find.widgetWithText(Segment<String>, 'Skills'), findsOneWidget);
    await shot('plugins');
    await tap(
      find.descendant(
        of: find.byType(Segment<String>),
        matching: find.text('插件'),
      ),
    );
    await settle(1200);
    if (android) {
      await tester.pageBack();
      expect(find.byTooltip('Skills'), findsNothing);
      expect(find.byTooltip('插件'), findsNothing);
    } else {
      await tap(find.byTooltip('关闭'));
      await tap(find.byTooltip('账户'));
      expect(find.text('Skills 与插件'), findsNothing);
      expect(find.text('设置'), findsOneWidget);
      Navigator.of(tester.element(find.text('设置').last)).pop();
    }
    await settle(600);
    note('pluginsUnderPlus', true);

    // The line between the sidebar and the chat moves and stays where it
    // was let go.
    if (!android) {
      final split = find.byKey(const ValueKey('sidebar-split'));
      final before = tester.getCenter(split).dx;
      final drag = await tester.startGesture(
        tester.getCenter(split),
        kind: PointerDeviceKind.mouse,
      );
      for (var step = 0; step < 12; step++) {
        await drag.moveBy(const Offset(-10, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await drag.up();
      await settle(500);
      final after = tester.getCenter(split).dx;
      final saved = (await SharedPreferences.getInstance()).getDouble(
        'sidebar-width',
      );
      note('sidebar', {'before': before, 'after': after, 'saved': saved});
      expect(after, closeTo(before - 120, 2));
      expect(saved, closeTo(client.prefs.sidebarWidth!, .01));
      await shot('sidebar-narrower');
    }

    final bot = client.node.bots.first;
    final dm = client.node.conversations.firstWhere(
      (x) => x['kind'] == 'dm' && x['botId'] == bot['botId'],
    );
    final id = dm['conversationId'] as String;
    await tap(find.byKey(ValueKey('conversation-$id')));
    final input = find.byKey(const ValueKey('chat-input'));
    await until(() => input.evaluate().isNotEmpty, what: 'chat open');
    await until(() => client.node.messages[id] != null, what: 'history');

    List<ChatMessage> messages() => client.node.messages[id] ?? [];
    bool idle() => client.node.activities[id]?.state == 'idle';
    ChatMessage? fresh(Set<Object?> seen, bool Function(ChatMessage) where) =>
        messages()
            .where((m) => !seen.contains(m.messageId) && where(m))
            .lastOrNull;
    Finder tile(ChatMessage m) => find.byWidgetPredicate(
      (w) => w is MessageTile && w.message.messageId == m.messageId,
    );
    // An approval or a question opens over the chat from the Dot's line.
    Finder control(ChatMessage m) => find.byWidgetPredicate(
      (w) => w is ControlCard && w.message.messageId == m.messageId,
    );

    // Waits for the Bot, allowing once whatever it asks to run on the way,
    // through the approval card's first choice.
    var approvals = 0;
    Future<void> working(
      bool Function() done, {
      int seconds = 300,
      required String what,
    }) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!done() && DateTime.now().isBefore(end)) {
        final pending = messages()
            .where((m) => m.kind == 'approval' && m.status == 'streaming')
            .lastOrNull;
        final allow = pending == null
            ? null
            : find.byKey(ValueKey('choice-${pending.messageId}-0'));
        final dot = find.byKey(const ValueKey('dot-activity'));
        if (allow != null &&
            allow.evaluate().isEmpty &&
            dot.evaluate().isNotEmpty) {
          await tap(dot);
        }
        if (allow != null && allow.evaluate().isNotEmpty) {
          final choices = object(pending!.content)['choices'] as List?;
          expect(
            find.descendant(
              of: control(pending),
              matching: find.byType(OutlinedButton),
            ),
            findsNWidgets(choices?.length ?? 2),
          );
          expect(
            find.descendant(of: allow, matching: find.text('允许一次')),
            findsOneWidget,
          );
          if (approvals++ == 0) {
            await shot('approval');
            note('approval', object(pending.content));
          }
          await tap(allow);
          await until(
            () => messages().any(
              (m) =>
                  m.messageId == pending.messageId && m.status != 'streaming',
            ),
            what: 'approval resolved',
          );
          continue;
        }
        await tester.pump(const Duration(milliseconds: 200));
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      expect(done(), isTrue, reason: 'Did not reach: $what');
    }

    Future<Set<Object?>> send(String text) async {
      await working(idle, what: 'idle before sending');
      final seen = messages().map((m) => m.messageId).toSet();
      await type(input, text);
      await tap(find.byTooltip('发送'));
      final end = DateTime.now().add(const Duration(seconds: 40));
      bool arrived() => messages().any(
        (m) =>
            !seen.contains(m.messageId) &&
            m.author.type == 'user' &&
            m.content['text'] == text.trim(),
      );
      while (!arrived() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 200));
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      if (!arrived()) {
        await shot('send-failed');
        note('sendFailed', {
          'input': tester.widget<TextField>(input).controller?.text,
          'activity': client.node.activities[id],
          'online': client.online,
          'errors': [
            for (final e in find.byType(ErrorNotice).evaluate())
              (e.widget as ErrorNotice).text,
          ],
          'tooltips': [
            for (final e in find.byType(Tooltip).evaluate())
              (e.widget as Tooltip).message,
          ],
        });
      }
      expect(arrived(), isTrue, reason: 'message sent');
      return seen;
    }

    // A question: its words, then lettered choices; one tap answers it.
    var seen = await send(
      '请调用 clarify 工具问我一个选择题：这周的周报用哪种格式？只给两个选项：表格、要点列表。'
      '我选完之后，只回复一句“好的，就用……”，不要做别的事。',
    );
    await until(
      () =>
          fresh(seen, (m) => m.kind == 'question' && m.status == 'streaming') !=
          null,
      seconds: 300,
      what: 'a native question',
    );
    final question = fresh(seen, (m) => m.kind == 'question')!;
    final choices = object(question.content)['choices'] as List;
    note('question', object(question.content));
    final first = find.byKey(ValueKey('choice-${question.messageId}-0'));
    expect(tile(question), findsNothing);
    await tap(find.byKey(const ValueKey('dot-activity')));
    await until(() => first.evaluate().isNotEmpty, what: 'choices shown');
    expect(
      find.descendant(of: control(question), matching: find.byType(ChoiceRow)),
      findsNWidgets(choices.length),
    );
    expect(
      find.descendant(of: first, matching: find.text('A')),
      findsOneWidget,
    );
    await shot('question');
    await tap(first);
    await until(
      () => messages().any(
        (m) => m.messageId == question.messageId && m.status != 'streaming',
      ),
      seconds: 120,
      what: 'question answered',
    );
    await working(idle, what: 'reply after the answer');
    expect(control(question), findsNothing);
    await shot('question-answered');
    note('questionAnswered', '${choices.first}');

    if (!android) {
      // A secret: its name, one field with its submit, and reuse; the value
      // is encrypted here and never reaches the chat.
      const value = 'nekodot-qa-etherscan-20261105';
      final spec = {
        'service': 'Etherscan API key',
        // A new purpose each run: a saved exact match is reused without a card.
        'purpose': '查询合约源码 ${DateTime.now().millisecondsSinceEpoch}',
        'fields': [
          {'name': 'ETHERSCAN_API_KEY', 'label': 'API key', 'kind': 'password'},
        ],
        'target': {
          'kind': 'file',
          'path': '$workFolder/etherscan.env',
          'format': 'env',
        },
      };
      seen = await send(
        '先读 nekodot-secrets 技能，然后用 terminal 运行 '
        "hermes secret request --spec '${jsonEncode(spec)}'，用保密卡片向我要这个 key，"
        '不要在聊天里问。卡片发出来后就结束这一轮。我交付之后，用 Python 检查那个 env 文件里 '
        'ETHERSCAN_API_KEY 不为空（只打印 true 或 false，不要打印值），成功就回复 SECRET_CARD_OK。',
      );
      await until(
        () =>
            fresh(
              seen,
              (m) => m.kind == 'secret' && m.content['state'] == 'pending',
            ) !=
            null,
        seconds: 300,
        what: 'a secret card',
      );
      final secret = fresh(seen, (m) => m.kind == 'secret')!;
      final card = find.byWidgetPredicate(
        (w) =>
            w is SecretCard &&
            w.content['requestId'] == secret.content['requestId'],
      );
      final field = find.byKey(
        const ValueKey('secret-field-ETHERSCAN_API_KEY'),
      );
      await until(() => field.evaluate().isNotEmpty, what: 'secret field');
      expect(
        find.descendant(of: card, matching: find.byType(TextField)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Etherscan API key')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('secret-save')), findsOneWidget);
      expect(find.text('取消请求'), findsNothing);
      // The same card as a question, and nothing around it.
      expect(
        find.descendant(of: card, matching: find.byType(ChatCard)),
        findsOneWidget,
      );
      await reveal(card);
      await shot('secret');
      await type(field, value);
      await tap(find.byKey(const ValueKey('secret-save')));
      await shot('secret-filled');
      await tap(find.byKey(const ValueKey('secret-submit')));
      await until(
        () => messages().any(
          (m) =>
              m.kind == 'secret' &&
              m.content['requestId'] == secret.content['requestId'] &&
              m.content['state'] == 'applied',
        ),
        seconds: 120,
        what: 'secret applied',
      );
      await working(
        () =>
            fresh(
              seen,
              (m) =>
                  m.kind == 'text' &&
                  m.author.type == 'bot' &&
                  m.status == 'done' &&
                  '${m.content['text']}'.contains('SECRET_CARD_OK'),
            ) !=
            null,
        what: 'Bot used the delivered key',
      );
      expect(jsonEncode(messages()).contains(value), isFalse);
      final saved = await client.rpc('secrets.list', {'botId': bot['botId']});
      expect(
        objects(saved['credentials'])
            .any((c) => c['service'] == 'Etherscan API key'),
        isTrue,
      );
      await reveal(card);
      await shot('secret-done');
      note('secret', 'applied, saved for reuse, Bot confirmed');
    }

    // A file and a picture: each stands on its own under the words; the
    // picture shows itself.
    seen = await send(
      '请在你的工作目录里做两个文件发给我：1）notes.txt，写两行今天的待办；'
      '2）只用 Python 标准库（zlib 和 struct，不要装别的包）生成一张 360x220 的彩色渐变 PNG，存为 chart.png。'
      '回复里各用单独一行 MEDIA:<文件的绝对路径> 把两个文件发给我。'
      '最后写两段话：第一段写“两个文件都发你了”，第二段写“图片直接显示在上面”。',
    );
    await working(
      () =>
          fresh(
            seen,
            (m) =>
                m.kind == 'text' &&
                m.status == 'done' &&
                (m.content['files'] as List?)?.length == 2,
          ) !=
          null,
      seconds: 400,
      what: 'two files delivered',
    );
    await working(idle, seconds: 120, what: 'files turn over');
    final delivered = fresh(
      seen,
      (m) => m.kind == 'text' && (m.content['files'] as List?)?.length == 2,
    )!;
    final files = [
      for (final fileId in delivered.content['files'] as List)
        await client.rpc('files.get', {'fileId': fileId}),
    ];
    note('files', [
      for (final f in files) {'name': f['name'], 'mime': f['mime']},
    ]);
    final picture = files.firstWhere(
      (f) => '${f['mime']}'.startsWith('image/'),
    );
    final document = files.firstWhere(
      (f) => !'${f['mime']}'.startsWith('image/'),
    );
    Finder fileCard(Json f) =>
        find.byWidgetPredicate((w) => w is FileCard && w.fileId == f['fileId']);
    await until(
      () => find
          .descendant(of: fileCard(picture), matching: find.byType(Image))
          .evaluate()
          .isNotEmpty,
      what: 'picture shown inline',
    );
    // Decoding takes a moment; until then the picture's place is held.
    Size shown() => tester.getSize(
      find.descendant(of: fileCard(picture), matching: find.byType(Image)),
    );
    await until(
      () => (shown().width / shown().height - 360 / 220).abs() < .05,
      what: 'picture decoded at its own proportions',
    );
    note('pictureSize', '${shown().width}x${shown().height}');
    expect(
      find.descendant(of: fileCard(document), matching: find.byType(Image)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: fileCard(document),
        matching: find.text('${document['name']}'),
      ),
      findsOneWidget,
    );
    for (final f in files) {
      expect(
        find.ancestor(of: fileCard(f), matching: find.byType(SelectionArea)),
        findsNothing,
        reason: 'a file is not inside the words',
      );
    }
    expect(
      find.descendant(
        of: tile(delivered),
        matching: find.textContaining('MEDIA:', findRichText: true),
      ),
      findsNothing,
    );
    await reveal(tile(delivered));
    await shot('files');

    // The words select across paragraphs and copy as they are shown.
    final words = withoutDeliveries('${delivered.content['text']}');
    final paragraphs = words
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    note('paragraphs', paragraphs);
    expect(paragraphs.length, greaterThanOrEqualTo(2));
    String head(String p) => p.substring(0, p.length.clamp(0, 4));
    final top = find
        .descendant(
          of: tile(delivered),
          matching: find.textContaining(
            head(paragraphs.first),
            findRichText: true,
          ),
        )
        .first;
    final bottom = find
        .descendant(
          of: tile(delivered),
          matching: find.textContaining(
            head(paragraphs.last),
            findRichText: true,
          ),
        )
        .last;
    copied = null;
    if (android) {
      await tester.longPress(top);
      await settle(800);
      await tap(find.text('Select all'));
      await shot('selected');
      await tap(find.text('Copy'));
    } else {
      final drag = await tester.startGesture(
        tester.getTopLeft(top) + const Offset(1, 6),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      final end = tester.getBottomRight(bottom) - const Offset(2, 4);
      for (var step = 1; step <= 10; step++) {
        await drag.moveTo(Offset.lerp(tester.getTopLeft(top), end, step / 10)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await drag.up();
      await settle(400);
      await shot('selected');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settle(400);
    }
    note('selectionCopied', copied);
    expect(copied, contains(head(paragraphs.first)));
    expect(copied, contains(head(paragraphs.last)));

    copied = null;
    final copy = find.byKey(ValueKey('copy-${delivered.messageId}'));
    await tap(copy);
    expect(copied, words);
    expect(
      find.descendant(of: copy, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
    await shot('copied');
    note('copyButton', true);

    if (!android) {
      await client.prefs.update(appearance: 'dark');
      await settle(800);
      await reveal(tile(delivered));
      await shot('files-dark');
      await client.prefs.update(appearance: 'system');
    }
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
      await File('$evidenceFolder/chat-cards-windows.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    }
    debugPrint('QA REPORT ${jsonEncode(report)}');
  }, timeout: const Timeout(Duration(minutes: 60)));
}
