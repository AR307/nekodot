import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/bot_editor.dart';
import 'package:nekodot_native/features/chat_message.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/settings.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

/// Real Relay / Node / Hermes journey. Only local credential/preferences storage
/// is isolated from the installed client. No model or network is simulated.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('second UI batch with real conversations and profile creation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final client = NekodotClient(vault: MemoryVault());
    final nav = GlobalKey<NavigatorState>();
    const dm = String.fromEnvironment('QA_CONVERSATION');
    const room = String.fromEnvironment('QA_GROUP');
    const evidence = String.fromEnvironment('QA_EVIDENCE_DIR');
    final android = Platform.isAndroid;
    var dark = false;
    var converted = false;
    final prefix = android ? 'android' : 'windows';
    final input = find.byKey(const ValueKey('chat-input'));
    Future<void> frames([int ms = 400]) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 40));
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }

    Future<void> until(
      bool Function() done,
      String name, {
      int seconds = 180,
    }) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!done() && DateTime.now().isBefore(end)) {
        await frames(100);
      }
      expect(done(), isTrue, reason: name);
      debugPrint('UI_BATCH2 PASS $name');
    }

    Future<void> shot(String name) async {
      await frames(500);
      if (android) {
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
          await tester.pump();
        }
        await binding.takeScreenshot('ui-batch2-$prefix-$name');
      } else {
        final view = tester.binding.renderViews.first;
        final image = await (view.debugLayer! as OffsetLayer).toImage(
          Offset.zero & view.flutterView.physicalSize,
        );
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(evidence).create(recursive: true);
        await File('$evidence/ui-batch2-$prefix-$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      }
    }

    Future<void> tap(Finder finder) async {
      await Scrollable.ensureVisible(
        tester.element(finder.first),
        alignment: .5,
      );
      await frames(100);
      await tester.tap(finder.hitTestable().first);
      await frames();
    }

    Widget app() => MaterialApp(
      navigatorKey: nav,
      debugShowCheckedModeBanner: false,
      navigatorObservers: [nativeRoutes],
      theme: appTheme(
        dark ? Brightness.dark : Brightness.light,
        glass: android,
      ),
      builder: (context, child) =>
          android ? Ambient(child: child!) : WindowChrome(child: child!),
      home: HomePage(client: client),
    );
    if (!android) {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
    }
    await client.login(
      const String.fromEnvironment('QA_EMAIL'),
      const String.fromEnvironment('QA_PASSWORD'),
    );
    await client.selectNode(const String.fromEnvironment('QA_NODE'));
    await until(
      () => client.online && client.node.conversations.isNotEmpty,
      'real node connected',
    );
    await tester.pumpWidget(app());
    await frames();
    await tap(find.byKey(ValueKey('conversation-$dm')));
    await until(() => input.evaluate().isNotEmpty, 'opened real conversation');
    bool idle() =>
        client.node.activities[dm]?.state == null ||
        client.node.activities[dm]?.state == 'idle';
    Future<void> send(String prompt) async {
      await tester.enterText(input, prompt);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await frames(300);
    }

    const uiOnly = bool.fromEnvironment('QA_UI_ONLY');
    if (!uiOnly) {
      final before = (client.node.messages[dm] ?? [])
          .map((m) => m.messageId)
          .toSet();
      var streaming = false;
      void observe() {
        streaming |= (client.node.messages[dm] ?? []).any(
          (m) =>
              !before.contains(m.messageId) &&
              m.status == 'streaming' &&
              m.kind == 'text',
        );
      }

      client.node.conversation(dm).addListener(observe);
      await send('请给我一份 24 条编号的 Flutter 聊天界面可用性检查清单，每条至少三十个汉字，直接输出清单，不需要工具。');
      await until(
        () =>
            (client.node.messages[dm] ?? []).any(
              (m) =>
                  !before.contains(m.messageId) &&
                  m.author.type == 'bot' &&
                  m.kind == 'text' &&
                  m.status == 'done',
            ) &&
            idle(),
        'real streaming response completed',
      );
      client.node.conversation(dm).removeListener(observe);
      expect(streaming, isTrue, reason: 'actual streamed text received');
      await frames();
      await shot('reply');
      await tester.drag(
        find.byKey(const ValueKey('chat-messages')),
        const Offset(0, 500),
      );
      await frames(600);
      final list = tester.widget<ScrollView>(
        find.byKey(const ValueKey('chat-messages')),
      );
      expect(
        list.controller!.position.pixels -
            list.controller!.position.minScrollExtent,
        greaterThan(64),
      );
      final tiles = find.byType(MessageTile).evaluate().where((e) {
        final box = e.renderObject;
        return box is RenderBox &&
            box.attached &&
            box.localToGlobal(Offset.zero).dy < 900 &&
            box.localToGlobal(Offset(0, box.size.height)).dy > 100;
      }).toList();
      final anchorId = (tiles.last.widget as MessageTile).message.messageId;
      Finder anchor() => find.byWidgetPredicate(
        (w) => w is MessageTile && w.message.messageId == anchorId,
      );
      final y = tester.getTopLeft(anchor()).dy;
      final previous = (client.node.messages[dm] ?? [])
          .map((m) => m.messageId)
          .toSet();
      // Represents another connected device sending while this one reads.
      await client.send(dm, '只回复一句：阅读位置验收完成。');
      await until(
        () =>
            (client.node.messages[dm] ?? []).any(
              (m) =>
                  !previous.contains(m.messageId) &&
                  m.author.type == 'bot' &&
                  m.kind == 'text' &&
                  m.status == 'done',
            ) &&
            idle(),
        'new real reply while reading above',
      );
      await frames(800);
      final drift = (tester.getTopLeft(anchor()).dy - y).abs();
      debugPrint('UI_BATCH2 reading drift: $drift px');
      await shot('reading-held');
      expect(drift, lessThan(2));
      expect(find.byKey(const ValueKey('chat-asked')), findsOneWidget);
      await tap(find.byKey(const ValueKey('chat-latest')));
      expect(
        (list.controller!.offset - list.controller!.position.minScrollExtent)
            .abs(),
        lessThan(2),
      );
      await shot('latest');
    }
    await frames();
    final replyId = client.node.messages[dm]!
        .lastWhere((m) => m.author.type == 'bot' && m.kind == 'text')
        .messageId;
    final replyTile = find.byWidgetPredicate(
      (w) => w is MessageTile && w.message.messageId == replyId,
    );
    final replyText = find
        .descendant(of: replyTile, matching: find.byType(RichText))
        .first;
    final history = tester.widget<ScrollView>(
      find.byKey(const ValueKey('chat-messages')),
    );
    history.controller!.jumpTo(history.controller!.position.minScrollExtent);
    await frames();
    final point = tester.getTopLeft(replyText) + const Offset(12, 10);
    if (android) {
      await tester.longPressAt(point);
    } else {
      await tester.tapAt(point, buttons: kSecondaryMouseButton);
      await frames();
      await tap(find.text('Select all'));
      await tester.tapAt(point, buttons: kSecondaryMouseButton);
    }
    await frames();
    await shot('quote-menu');
    await tap(find.text('引用回复'));
    expect(find.byKey(const ValueKey('composer-quote')), findsOneWidget);
    await shot('quote');
    final quotedBefore = (client.node.messages[dm] ?? [])
        .map((m) => m.messageId)
        .toSet();
    await send('请使用终端执行 Python 计算 17*23，再用一句话说明结果，不要写文件。');
    await until(
      () =>
          (client.node.messages[dm] ?? []).any(
            (m) =>
                !quotedBefore.contains(m.messageId) &&
                m.author.type == 'bot' &&
                m.kind == 'text' &&
                m.status == 'done',
          ) &&
          idle(),
      'quoted request completed with real model',
    );
    expect(
      (client.node.messages[dm] ?? []).any(
        (m) => !quotedBefore.contains(m.messageId) && m.kind == 'tool',
      ),
      isTrue,
    );
    expect(
      (client.node.messages[dm] ?? [])
          .lastWhere((m) => m.author.type == 'user')
          .content['text'],
      startsWith('> '),
    );
    expect(find.byKey(const ValueKey('composer-quote')), findsNothing);
    if (android) {
      await binding.handlePopRoute();
      await frames();
    }
    await tap(find.byTooltip('设置').last);
    await shot('settings');
    if (!android) {
      expect(find.byType(SheetFrame), findsOneWidget);
      await tap(find.byKey(const ValueKey('settings-nav-app')));
      await shot('settings-app');
      await tap(find.byKey(const ValueKey('settings-nav-account')));
    }
    await tap(find.widgetWithText(ListTile, '修改密码'));
    await shot('settings-child');
    await binding.handlePopRoute();
    await frames();
    expect(find.byType(SettingsPage), findsOneWidget);
    await binding.handlePopRoute();
    await frames();
    await tap(find.byKey(ValueKey('conversation-$room')));
    await tester.enterText(input, '前文 @qa 后文');
    final controller = tester.widget<TextField>(input).controller!;
    controller.selection = const TextSelection.collapsed(offset: 6);
    await frames();
    expect(find.byKey(const ValueKey('mention-qalead')), findsOneWidget);
    await shot('mention');
    await tap(find.byKey(const ValueKey('mention-qalead')));
    expect(controller.text, '前文 @qalead  后文');
    await tester.tap(input);
    await frames(200);
    await tester.enterText(input, '@');
    controller.selection = const TextSelection.collapsed(offset: 1);
    await frames();
    await shot('mention-everyone');
    await tap(find.byKey(const ValueKey('mention-everyone')));
    expect(controller.text, '@everyone ');
    await tester.enterText(input, '');
    if (android) {
      FocusManager.instance.primaryFocus?.unfocus();
      await binding.handlePopRoute();
      await frames();
    }
    await tap(find.byTooltip('新建'));
    await tap(find.text('新建 Bot').last);
    await until(
      () => find.byKey(const ValueKey('bot-name')).evaluate().isNotEmpty,
      'creation editor opened',
    );
    final name = 'UI ${DateTime.now().millisecondsSinceEpoch}';
    await tester.enterText(find.byKey(const ValueKey('bot-name')), name);
    if (!android) {
      await tester.tapAt(const Offset(12, 100));
      await frames();
      expect(
        find.byType(BotEditor),
        findsOneWidget,
        reason: 'outside click retains form',
      );
    }
    await until(
      () =>
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('model-choice')),
              )
              .onPressed !=
          null,
      'real provider catalog loaded',
    );
    await tap(find.byKey(const ValueKey('model-choice')));
    await tester.enterText(
      find.byKey(const ValueKey('model-search')),
      'gpt-6.1-sol',
    );
    await frames();
    await tap(find.byKey(const ValueKey('model-option-gpt-6.1-sol')));
    await shot('create');
    await tap(find.byKey(const ValueKey('bot-save')));
    expect(
      find.byKey(const ValueKey('bot-creating'), skipOffstage: false),
      findsOneWidget,
    );
    await shot('creating');
    await until(
      () => find.byType(BotEditor).evaluate().isEmpty,
      'real profile creation opened conversation',
    );
    final created = client.node.bots.singleWhere(
      (b) => b['displayName'] == name,
    );
    expect(
      client.node.conversations.any((c) => c['botId'] == created['botId']),
      isTrue,
    );
    await shot('created');
    await tap(find.byTooltip('详情'));
    await tap(find.byTooltip('编辑'));
    await until(
      () => find.widgetWithText(TextButton, '归档').evaluate().isNotEmpty,
      'archive control available',
    );
    await tap(find.widgetWithText(TextButton, '归档'));
    expect(find.text('归档此 Bot？'), findsOneWidget);
    await shot('archive-confirm');
    await tap(find.widgetWithText(TextButton, '取消'));
    expect(
      client.node.bots.singleWhere(
        (b) => b['botId'] == created['botId'],
      )['archived'],
      isFalse,
    );
    await tap(find.widgetWithText(TextButton, '归档'));
    await tap(find.widgetWithText(FilledButton, '归档'));
    await until(
      () => !client.node.bots.any((b) => b['botId'] == created['botId']),
      'confirmed archive persisted',
    );
    final archivedSnapshot = await client.rpc('sync.snapshot');
    expect(
      (archivedSnapshot['bots'] as List).singleWhere(
        (b) => b['botId'] == created['botId'],
      )['archived'],
      isTrue,
    );
    await frames();
    expect(
      find.byKey(const ValueKey('chat-input'), skipOffstage: false),
      findsNothing,
      reason: 'archived conversation cannot accept another message',
    );
    await shot('archived');
    nav.currentState!.popUntil((r) => r.isFirst);
    await frames();
    if (!android) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await frames();
      await tester.enterText(
        find.byKey(const ValueKey('search-palette-input')),
        'QA Team',
      );
      await frames();
      await shot('search');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await frames();
      expect(find.byKey(const ValueKey('chat-input')), findsOneWidget);
    }
    await tap(find.byTooltip('新建'));
    await tap(find.text('新建群组').last);
    final groupName = 'UI Group ${DateTime.now().millisecondsSinceEpoch}';
    await tester.enterText(find.byKey(const ValueKey('bot-name')), groupName);
    await tap(find.widgetWithText(CheckboxListTile, 'QA Lead'));
    await tap(find.widgetWithText(CheckboxListTile, 'QA Writer'));
    await tap(find.byKey(const ValueKey('bot-save')));
    await until(
      () => find.byType(BotEditor).evaluate().isEmpty,
      'created real group',
    );
    final createdGroup = client.node.groups.singleWhere(
      (g) => g['name'] == groupName,
    );
    final groupConversation = client.node.conversations.singleWhere(
      (c) => c['groupId'] == createdGroup['groupId'],
    );
    await tap(
      find.byKey(
        ValueKey('conversation-${groupConversation['conversationId']}'),
      ),
    );
    await tap(find.byTooltip('详情'));
    await tap(find.widgetWithText(TextButton, '归档'));
    expect(find.text('归档此群聊？'), findsOneWidget);
    await shot('group-archive-confirm');
    await tap(find.widgetWithText(TextButton, '取消'));
    expect(
      client.node.groups.singleWhere(
        (g) => g['groupId'] == createdGroup['groupId'],
      )['archived'],
      isFalse,
    );
    await tap(find.widgetWithText(TextButton, '归档'));
    await tap(find.widgetWithText(FilledButton, '归档'));
    await until(
      () => !client.node.groups.any(
        (g) => g['groupId'] == createdGroup['groupId'],
      ),
      'confirmed group archive persisted',
    );
    await frames();
    expect(
      find.byKey(const ValueKey('chat-input'), skipOffstage: false),
      findsNothing,
    );
    nav.currentState!.popUntil((r) => r.isFirst);
    await frames();
    dark = true;
    await tester.pumpWidget(app());
    await frames();
    await tap(find.byTooltip('设置').last);
    await shot('settings-dark');
    await binding.handlePopRoute();
    await frames();
    if (!android) {
      tester.view.physicalSize = const Size(900, 480);
      await frames();
      await tap(find.byTooltip('设置').last);
      await shot('settings-short-window');
      expect(tester.takeException(), isNull);
      await binding.handlePopRoute();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    client.dispose();
    tester.view.reset();
  }, timeout: const Timeout(Duration(minutes: 16)));
}
