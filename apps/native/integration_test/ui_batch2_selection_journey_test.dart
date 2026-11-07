import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/bot_editor.dart';
import 'package:nekodot_native/features/chat_composer.dart';
import 'package:nekodot_native/features/chat_message.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/settings.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';
import 'package:nekodot_native/ui/message_markdown.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

/// Actual candidate widgets, Relay, Node, Hermes and model. Only the login
/// store/preferences are isolated; no HTTP, model, or status is simulated.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('English quote and empty/loading/error real journey', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final client = NekodotClient(vault: MemoryVault());
    final nav = GlobalKey<NavigatorState>();
    const dm = String.fromEnvironment('QA_CONVERSATION');
    const evidence = String.fromEnvironment('QA_EVIDENCE_DIR');
    final android = Platform.isAndroid;
    final platform = android ? 'android' : 'windows';
    var dark = false, converted = false;
    final input = find.byKey(const ValueKey('chat-input'));
    Future<void> frames([int ms = 300]) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 40));
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }

    Future<void> until(bool Function() done, String name) async {
      final end = DateTime.now().add(const Duration(seconds: 180));
      while (!done() && DateTime.now().isBefore(end)) {
        await frames(100);
      }
      expect(done(), isTrue, reason: name);
      debugPrint('UI_SELECTION PASS $platform $name');
    }

    Future<void> shot(String name, {bool settle = true}) async {
      if (settle) await frames();
      expect(tester.takeException(), isNull, reason: 'layout: $name');
      if (android) {
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
          await tester.pump();
        }
        await binding.takeScreenshot('ui-selection-$platform-$name');
      } else {
        final view = tester.binding.renderViews.first;
        final image = await (view.debugLayer! as OffsetLayer).toImage(
          Offset.zero & view.flutterView.physicalSize,
        );
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(evidence).create(recursive: true);
        await File('$evidence/ui-selection-$platform-$name.png')
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
      tester.view.physicalSize = const Size(1280, 840);
      tester.view.devicePixelRatio = 1;
    }
    await client.prefs.update(locale: 'en');
    await client.login(
      const String.fromEnvironment('QA_EMAIL'),
      const String.fromEnvironment('QA_PASSWORD'),
    );
    await client.selectNode(const String.fromEnvironment('QA_NODE'));
    await until(
      () => client.online && client.node.conversations.isNotEmpty,
      'real connection',
    );
    await tester.pumpWidget(app());
    await shot('english-home');

    // Empty search is produced by an actual search, not injected page state.
    if (android) {
      await tester.enterText(
        find.byKey(const ValueKey('home-search')),
        'no-such-ui-result-98765',
      );
    } else {
      await tap(find.byTooltip('Search (Ctrl+K)'));
      await tester.enterText(
        find.byType(TextField).last,
        'no-such-ui-result-98765',
      );
    }
    await shot('empty-search');
    if (android) {
      await tester.enterText(find.byKey(const ValueKey('home-search')), '');
      FocusManager.instance.primaryFocus?.unfocus();
    } else {
      await binding.handlePopRoute();
    }
    await frames();
    await tap(find.byTooltip('Create'));
    await tap(find.text('New Bot').last);
    await until(
      () => find.byType(BotEditor).evaluate().isNotEmpty,
      'empty creation form',
    );
    await shot('empty-form');
    await tester.enterText(
      find.byKey(const ValueKey('bot-name')),
      'UI validation retained',
    );
    await tap(find.byKey(const ValueKey('bot-save')));
    expect(find.byType(BotEditor), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('bot-name')))
          .controller!
          .text,
      'UI validation retained',
    );
    await shot('validation-failure');
    await until(
      () =>
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('model-choice')),
              )
              .onPressed !=
          null,
      'actual model catalog',
    );
    await tap(find.byKey(const ValueKey('model-choice')));
    await tester.enterText(
      find.byKey(const ValueKey('model-search')),
      'no-such-model-98765',
    );
    await shot('empty-model-search');
    await tap(find.text('Cancel'));

    // Close only this client's real socket. Keep services and other clients up.
    client.connection.active = false;
    await client.connection.disconnect();
    await tap(find.byTooltip('Refresh models'));
    expect(find.text('Relay is disconnected'), findsOneWidget);
    await shot('disconnected-catalog');
    dark = true;
    await tester.pumpWidget(app());
    await frames(1000);
    await shot('dark-disconnected-catalog');
    client.connection.active = true;
    await client.connection.connect();
    await until(() => client.online, 'actual reconnection');
    await Scrollable.ensureVisible(
      tester.element(find.byTooltip('Refresh models')),
      alignment: .5,
    );
    await frames();
    await tester.tap(find.byTooltip('Refresh models'));
    await tester.pump();
    expect(find.text('Loading models…'), findsOneWidget);
    await shot('loading-catalog', settle: false);
    await until(
      () =>
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('model-choice')),
              )
              .onPressed !=
          null,
      'retry restored catalog',
    );
    expect(find.text('Relay is disconnected'), findsNothing);
    await shot('catalog-recovered');
    await binding.handlePopRoute();
    await frames();

    await tap(find.byTooltip('Settings').last);
    await shot('english-settings');
    if (!android) {
      await tap(find.byKey(const ValueKey('settings-nav-app')));
      await shot('english-app-settings');
      await tap(find.byKey(const ValueKey('settings-nav-account')));
    }
    await tap(find.widgetWithText(ListTile, 'Change password'));
    await shot('english-settings-child');
    await binding.handlePopRoute();
    await frames();
    expect(find.byType(SettingsPage), findsOneWidget);
    await binding.handlePopRoute();
    await frames();
    await tap(find.byKey(ValueKey('conversation-$dm')));
    await until(() => input.evaluate().isNotEmpty, 'actual conversation');
    bool idle() =>
        client.node.activities[dm]?.state == null ||
        client.node.activities[dm]?.state == 'idle';
    Future<void> send(String prompt) async {
      await tester.enterText(input, prompt);
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await frames();
    }

    Future<void> reply(Set<String> before, String name) => until(
      () =>
          idle() &&
          (client.node.messages[dm] ?? []).any(
            (m) =>
                !before.contains(m.messageId) &&
                m.author.type == 'bot' &&
                m.kind == 'text' &&
                m.status == 'done',
          ),
      name,
    );
    final before = (client.node.messages[dm] ?? [])
        .map((m) => m.messageId)
        .toSet();
    await send(
      'Reply in English with one short sentence about clear writing. No tools needed.',
    );
    await reply(before, 'real English model response');
    final replyId = client.node.messages[dm]!
        .lastWhere((m) => m.author.type == 'bot' && m.kind == 'text')
        .messageId;
    final tile = find.byWidgetPredicate(
      (w) => w is MessageTile && w.message.messageId == replyId,
    );
    final markdown = find.descendant(
      of: tile,
      matching: find.byType(MessageMarkdown),
    );
    final text = find
        .descendant(of: markdown, matching: find.byType(RichText))
        .first;
    final list = tester.widget<ScrollView>(
      find.byKey(const ValueKey('chat-messages')),
    );
    list.controller!.jumpTo(list.controller!.position.minScrollExtent);
    await frames();
    await shot('before-selection');
    final point = tester.getTopLeft(text) + const Offset(3, 8);
    final bubble = find.byKey(const ValueKey('selection-quote-bubble'));
    Future<void> dragSelect() async {
      final drag = await tester.startGesture(
        point,
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveTo(point + const Offset(25, 0));
      await frames(100);
      await drag.moveTo(point + const Offset(140, 0));
      await frames(100);
      expect(
        (tester.getTopLeft(text).dy + 8 - point.dy).abs(),
        lessThan(1),
        reason: 'selecting text must not move the message',
      );
      expect(bubble, findsNothing);
      await drag.up();
      await frames();
      await shot('after-selection');
      expect(bubble, findsOneWidget);
    }

    if (android) {
      await tester.longPressAt(point + const Offset(12, 0));
      await frames();
      await shot('touch-quote-menu');
      await tap(find.text('Quote in reply'));
    } else {
      await dragSelect();
      await shot('quote-bubble-dark');
      await tester.tapAt(
        point + const Offset(55, 0),
        buttons: kSecondaryMouseButton,
      );
      await frames();
      expect(find.text('Copy'), findsOneWidget);
      expect(bubble, findsNothing);
      await shot('native-copy-menu');
      await tester.tapAt(const Offset(500, 60));
      await frames();
      await dragSelect();
      await tester.tap(bubble);
    }
    await frames();
    final quote = tester.widget<QuoteChip>(find.byType(QuoteChip)).text;
    expect(quote.trim(), isNotEmpty);
    await shot('quoted-composer');
    final quotedBefore = client.node.messages[dm]!
        .map((m) => m.messageId)
        .toSet();
    await send(
      'Use the terminal tool to calculate 19*23 in Python. Then reply in English with the result in one sentence. Do not write any file.',
    );
    await reply(quotedBefore, 'quoted real tool request');
    expect(
      client.node.messages[dm]!.any(
        (m) => !quotedBefore.contains(m.messageId) && m.kind == 'tool',
      ),
      isTrue,
    );
    final sent =
        client.node.messages[dm]!
                .lastWhere((m) => m.author.type == 'user')
                .content['text']
            as String;
    expect(sent, startsWith('> $quote'));
    expect(find.byType(QuoteChip), findsNothing);
    await shot('real-tool-result');
    dark = false;
    await tester.pumpWidget(app());
    await frames(1000);
    await shot('english-light-chat');
    if (!android) {
      list.controller!.jumpTo(list.controller!.position.minScrollExtent);
      await frames();
      final latestId = client.node.messages[dm]!
          .lastWhere((m) => m.author.type == 'bot' && m.kind == 'text')
          .messageId;
      final latestTile = find.byWidgetPredicate(
        (w) => w is MessageTile && w.message.messageId == latestId,
      );
      final latestText = find
          .descendant(
            of: find.descendant(
              of: latestTile,
              matching: find.byType(MessageMarkdown),
            ),
            matching: find.byType(RichText),
          )
          .first;
      final at = tester.getTopLeft(latestText) + const Offset(16, 8);
      await tester.tapAt(at, kind: PointerDeviceKind.mouse);
      await frames(80);
      await tester.tapAt(at, kind: PointerDeviceKind.mouse);
      await frames();
      expect(bubble, findsOneWidget);
      await shot('quote-double-click-light');
      await tester.drag(
        find.byKey(const ValueKey('chat-messages')),
        const Offset(0, 130),
      );
      await frames();
      expect(bubble, findsNothing);
      list.controller!.jumpTo(list.controller!.position.minScrollExtent);
      tester.view.physicalSize = const Size(900, 480);
      await shot('english-short-window');
    }
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });
}
