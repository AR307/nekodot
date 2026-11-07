import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/bot_details.dart';
import 'package:nekodot_native/features/files.dart';
import 'package:nekodot_native/features/flowchart.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/platform/notifications.dart';
import 'package:nekodot_native/ui/design.dart';
import 'package:nekodot_native/ui/foreground_notice.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

/// Exercises real model-produced files and notifications through the candidate UI.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('responsive reading, settings and foreground delivery', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'notification-requested': true});
    final client = NekodotClient(vault: MemoryVault());
    final notifications = NativeNotifications(client);
    final signalLog = client.notifications.stream.listen((signal) async {
      debugPrint(
        'UI_REFRESH notification kind=${signal['kind']} active=${client.connection.active} lifecycle=${WidgetsBinding.instance.lifecycleState} visible=${client.visibleConversation == signal['conversationId']} focus=${DesktopHost.supported ? await windowManager.isFocused() : true}',
      );
    });
    addTearDown(() async {
      notifications.dispose();
      await signalLog.cancel();
      client.dispose();
      if (Platform.isWindows) await windowManager.setAlwaysOnTop(false);
    });
    final nav = GlobalKey<NavigatorState>();
    final phone = Platform.isAndroid;
    final platform = phone ? 'android' : 'windows';
    const dm = String.fromEnvironment('QA_CONVERSATION');
    const readingOnly = bool.fromEnvironment('QA_READING_ONLY');
    const evidence = String.fromEnvironment('QA_EVIDENCE_DIR');
    var converted = false;
    Future<void> frames([int ms = 350]) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 40));
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }

    Future<void> until(bool Function() done, String name) async {
      final end = DateTime.now().add(const Duration(minutes: 3));
      while (!done() && DateTime.now().isBefore(end)) {
        await frames(100);
      }
      expect(done(), isTrue, reason: name);
      debugPrint('UI_REFRESH PASS $platform $name');
    }

    Future<void> shot(String name) async {
      await frames();
      expect(tester.takeException(), isNull, reason: name);
      if (phone) {
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
          await tester.pump();
        }
        await binding.takeScreenshot('ui-refresh-$platform-$name');
      } else {
        final view = tester.binding.renderViews.first;
        final image = await (view.debugLayer! as OffsetLayer).toImage(
          Offset.zero & view.flutterView.physicalSize,
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(evidence).create(recursive: true);
        await File('$evidence/ui-refresh-$platform-$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
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

    if (!phone) {
      await windowManager.ensureInitialized();
      await windowManager.restore();
      await windowManager.show();
      await windowManager.setAlwaysOnTop(true);
      await windowManager.focus();
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
    }
    await client.prefs.update(locale: 'en', appearance: 'light');
    await client.login(
      const String.fromEnvironment('QA_EMAIL'),
      const String.fromEnvironment('QA_PASSWORD'),
    );
    await client.selectNode(const String.fromEnvironment('QA_NODE'));
    await until(
      () => client.online && client.node.bots.length >= 2,
      'real Node ready',
    );
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: client.prefs,
        builder: (_, child) => MaterialApp(
          navigatorKey: nav,
          navigatorObservers: [nativeRoutes],
          debugShowCheckedModeBanner: false,
          theme: appTheme(
            client.prefs.theme == 'dark' ? Brightness.dark : Brightness.light,
            glass: phone,
          ),
          builder: (context, child) => phone
              ? Ambient(
                  child: ForegroundNotice(client: client, child: child!),
                )
              : WindowChrome(
                  child: ForegroundNotice(client: client, child: child!),
                ),
          home: HomePage(client: client),
        ),
      ),
    );
    unawaited(notifications.initialize(nav.currentContext!));
    await frames(1000);
    final other =
        client.node.conversations.firstWhere(
              (v) => v['kind'] == 'dm' && v['conversationId'] != dm,
            )['conversationId']
            as String;
    final input = find.byKey(const ValueKey('chat-input'));
    await tap(find.byKey(ValueKey('conversation-$dm')));
    await until(() => input.evaluate().isNotEmpty, 'chat ready');
    final tag = DateTime.now().millisecondsSinceEpoch;
    final existingFile = client.node.messages[dm]
        ?.where(
          (m) =>
              m.content['files'] is List &&
              (m.content['files'] as List).isNotEmpty,
        )
        .lastOrNull;
    if (!readingOnly) {
      if (!phone) {
        debugPrint('UI_REFRESH waiting for physical candidate focus');
        final deadline = DateTime.now().add(const Duration(minutes: 2));
        while ((!await windowManager.isFocused() ||
                binding.lifecycleState != AppLifecycleState.resumed) &&
            DateTime.now().isBefore(deadline)) {
          await frames(200);
        }
        expect(await windowManager.isFocused(), isTrue);
        expect(binding.lifecycleState, AppLifecycleState.resumed);
      }
      await tester.enterText(
        input,
        existingFile != null
            ? 'Reply with one short sentence explaining that the previous reading file is ready. Do not call tools or create another file.'
            : 'Use your real terminal tool to write a Markdown file named ui-reading-$tag.md in your workspace. Use Python to generate a title, a table of 3 rows and 35 numbered sections, each with two sentences about readable interfaces. This is a harmless UI test file. Return the absolute path as a MEDIA: line to deliver the file, and a short final response. Do not ask for confirmation.',
      );
      await tester.pump();
      await tap(find.byTooltip('Send'));
      // Read another conversation while the real model finishes the file task.
      if (phone) {
        await binding.handlePopRoute();
        await frames();
      }
      await tap(find.byKey(ValueKey('conversation-$other')));
      if (!phone) {
        await windowManager.restore();
        await windowManager.setAlwaysOnTop(true);
        await windowManager.focus();
      }
      await until(
        () => client.foregroundNotice.value?['conversationId'] == dm,
        'actual other-conversation notification',
      );
      expect(
        client.reading.unread(
          client.selectedNodeId!,
          dm,
          client.incomingSequence(dm),
        ),
        isTrue,
      );
      await shot('foreground-unread');
      await tap(find.byKey(const ValueKey('foreground-notice')));
      await until(
        () => client.visibleConversation == dm && input.evaluate().isNotEmpty,
        'notification navigates to origin',
      );
      await until(
        () => !client.reading.unread(
          client.selectedNodeId!,
          dm,
          client.incomingSequence(dm),
        ),
        'viewed message clears local unread',
      );
    }
    await until(
      () => client.node.messages[dm]!.any(
        (m) =>
            object(m.content)['files'] is List &&
            (m.content['files'] as List).isNotEmpty,
      ),
      'real file delivered',
    );
    expect(client.node.messages[dm]!.any((m) => m.kind == 'tool'), isTrue);
    final delivered = client.node.messages[dm]!.lastWhere(
      (m) =>
          m.content['files'] is List && (m.content['files'] as List).isNotEmpty,
    );
    final rawFile = (delivered.content['files'] as List).first;
    final fileId = rawFile is String
        ? rawFile
        : object(rawFile)['fileId'] as String;
    final data = utf8.decode(await downloadFile(client, fileId));
    expect(data, contains('#'));
    expect(data.length, greaterThan(1000));
    await tap(input);
    await frames(800);
    await tester.enterText(input, 'Draft retained while reading');
    await frames();
    expect(
      tester.widget<TextField>(input).controller!.text,
      'Draft retained while reading',
      reason: 'draft entered',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await frames();
    expect(
      tester.widget<TextField>(input).controller!.text,
      'Draft retained while reading',
      reason: 'draft after unfocus',
    );
    final card = find.byWidgetPredicate(
      (w) => w is FileCard && w.fileId == fileId,
    );
    final chatScroll = tester
        .widget<ScrollView>(find.byKey(const ValueKey('chat-messages')))
        .controller!;
    chatScroll.jumpTo(chatScroll.position.minScrollExtent);
    await frames();
    for (var page = 0; page < 30 && card.evaluate().isEmpty; page++) {
      await tester.drag(
        find.byKey(const ValueKey('chat-messages')),
        const Offset(0, 400),
      );
      await frames();
    }
    expect(card, findsWidgets);
    await tap(card);
    await until(
      () => find.byKey(const ValueKey('viewer-markdown')).evaluate().isNotEmpty,
      'Markdown file rendered natively',
    );
    await shot('file-reader');
    final reading = find
        .ancestor(
          of: find.byKey(const ValueKey('viewer-markdown')),
          matching: find.byType(SingleChildScrollView),
        )
        .first;
    await tester.drag(reading, const Offset(0, -480));
    await frames();
    ScrollController reader() => tester
        .widget<SingleChildScrollView>(
          find.byKey(const ValueKey('viewer-reading-scroll')),
        )
        .controller!;
    final offset = reader().position.pixels;
    expect(offset, greaterThan(0));
    if (!phone) {
      expect(find.byType(BotDetails), findsNothing);
      expect(find.byType(FlowchartPanel), findsNothing);
      await tap(find.byKey(const ValueKey('viewer-expand')));
      expect(reader().position.pixels, closeTo(offset, 1));
      await shot('file-expanded');
      await tap(find.byKey(const ValueKey('viewer-expand')));
      expect(reader().position.pixels, closeTo(offset, 1));
    }
    await tap(find.byTooltip('Close').last);
    await frames();
    expect(
      tester.widget<TextField>(input).controller!.text,
      'Draft retained while reading',
    );
    await tap(input);
    await frames(800);
    await tester.enterText(input, '');
    await frames();
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    await shot('compact-composer');
    if (phone) {
      await binding.handlePopRoute();
      await frames();
    }
    await tap(find.byTooltip('Settings').last);
    if (phone) {
      await tap(find.byKey(const ValueKey('settings-category-app')));
    } else {
      await tap(find.byKey(const ValueKey('settings-nav-app')));
    }
    await tap(find.text('中'));
    await until(
      () => find.text('语言').evaluate().isNotEmpty,
      'settings language immediately updates',
    );
    await tap(find.byIcon(Icons.dark_mode_outlined));
    await shot('settings-dark-chinese');
    await tap(find.text('EN'));
    await until(
      () => find.text('Language').evaluate().isNotEmpty,
      'settings language restores',
    );
    await tap(find.byIcon(Icons.light_mode_outlined));
    await shot('settings-light-english');
    await binding.handlePopRoute();
    if (phone) {
      await frames();
      await binding.handlePopRoute();
    }
    await frames();
    await tester.pumpWidget(const SizedBox());
  });
}
