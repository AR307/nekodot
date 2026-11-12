import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/bot_editor.dart';
import 'package:nekodot_native/features/plugin_center.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/learning.dart';
import 'package:nekodot_native/features/pets.dart';
import 'package:nekodot_native/features/settings.dart';
import 'package:nekodot_native/features/subscription.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Uses actual platform clipboard, uploads, native widgets, Hermes and model.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('device commands and native learning, pets and account pages', (
    tester,
  ) async {
    SharedPreferences.setPrefix('nekodot-command-device-qa.');
    if (Platform.isWindows) await DesktopHost.initialize();
    final c = NekodotClient()..prefs.language = 'en';
    final botId = const String.fromEnvironment('QA_SECOND_BOT');
    final login = await c.account.request(
      '/auth/login',
      method: 'POST',
      body: {
        'email': const String.fromEnvironment('QA_EMAIL'),
        'password': const String.fromEnvironment('QA_PASSWORD'),
      },
    );
    c.account.token = login['token'];
    c.selectedNodeId = const String.fromEnvironment('QA_NODE');
    await c.bootstrap();
    addTearDown(c.dispose);
    Future<void> until(bool Function() ready, {int seconds = 90}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 150));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(ready(), isTrue, reason: 'Real device command journey timed out');
    }

    Future<void> tap(Finder target) async {
      await until(() => target.hitTestable().evaluate().isNotEmpty);
      await tester.tap(target.hitTestable().first);
    }

    await until(() => c.online && c.node.bots.length >= 2);
    final conversationId =
        '${c.node.conversations.firstWhere((r) => r['kind'] == 'dm' && r['botId'] == botId)['conversationId']}';
    final home = HomePage(client: c),
        light = appTheme(Brightness.light),
        dark = appTheme(Brightness.dark);
    runApp(
      ListenableBuilder(
        listenable: c,
        builder: (context, child) => MaterialApp(
          theme: light,
          darkTheme: dark,
          themeMode: c.prefs.theme == 'dark' ? ThemeMode.dark : ThemeMode.light,
          navigatorObservers: [nativeRoutes],
          builder: (context, child) => Platform.isWindows
              ? WindowChrome(child: child!)
              : Ambient(child: child!),
          home: home,
        ),
      ),
    );
    await tap(find.byKey(ValueKey('conversation-$conversationId')));
    final input = find.byKey(const ValueKey('chat-input'));
    await until(() => input.evaluate().isNotEmpty);
    await c.loadMessages(conversationId);
    await until(() => c.node.activities[conversationId]?.state == 'idle');
    Future<void> send(String text) async {
      debugPrint('QA DEVICE: sending ${text.split(' ').first}');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 150));
      await tap(input);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.enterText(input, text);
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.widget<TextField>(input).controller!.text, text);
      await until(
        () => find
            .byWidgetPredicate(
              (w) =>
                  w is IconButton && w.tooltip == 'Send' && w.onPressed != null,
            )
            .evaluate()
            .isNotEmpty,
      );
      await tap(find.byTooltip('Send'));
    }

    Future<void> local(String text, bool Function() complete) async {
      await send(text);
      await until(
        () =>
            complete() &&
            tester.widget<TextField>(input).controller!.text.isEmpty,
      );
    }

    for (final key in [
      'focus',
      'density',
      'timestamps',
      'statusbar',
      'battery',
    ]) {
      await local('/$key on', () => c.prefs.chatDisplay[key] == true);
      final prefs = await SharedPreferences.getInstance();
      await until(() => prefs.getBool('chat-$key') == true);
    }
    await until(
      () => find.byKey(const ValueKey('chat-statusbar')).evaluate().isNotEmpty,
    );
    await until(
      () => find.byKey(const ValueKey('device-battery')).evaluate().isNotEmpty,
    );
    await until(
      () => find.textContaining('Reading battery').evaluate().isEmpty,
    );
    expect(find.textContaining('Device battery'), findsOneWidget);
    final messagesBeforeRefresh = (c.node.messages[conversationId] ?? [])
        .map((r) => r.messageId)
        .toSet();
    await local('/redraw', () => true);
    expect(
      (c.node.messages[conversationId] ?? []).map((r) => r.messageId).toSet(),
      messagesBeforeRefresh,
    );
    await local('/skin dark', () => c.prefs.theme == 'dark');
    await until(
      () => Theme.of(tester.element(input)).brightness == Brightness.dark,
    );
    expect(Theme.of(tester.element(input)).brightness, Brightness.dark);
    await local('/skin light', () => c.prefs.theme == 'light');
    debugPrint(
      'QA DEVICE: local display commands and persisted native appearance passed',
    );

    final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    canvas.drawRect(
      const Rect.fromLTWH(10, 20, 100, 80),
      Paint()..color = Colors.red,
    );
    canvas.drawCircle(const Offset(170, 60), 35, Paint()..color = Colors.blue);
    final picture = recorder.endRecording(),
        image = await picture.toImage(240, 120);
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
    image.dispose();
    picture.dispose();
    final temp = await Directory.systemTemp.createTemp(
      'nekodot-device-command-',
    );
    final file = File('${temp.path}/原生图片.png');
    await file.writeAsBytes(png);
    final draftKey = '${c.selectedNodeId}:$conversationId';
    if (Platform.isWindows) {
      // Existing plugin's real Windows clipboard call; keep the source fixture.
      await const MethodChannel('pasteboard')
          .invokeMethod('writeImage', {'fileName': file.path});
      expect(await Pasteboard.image, isNotNull);
      await local(
        '/paste',
        () => c.attachmentDrafts[draftKey]?.isNotEmpty == true,
      );
    } else {
      // Prepare the command before copying, as when returning from an image
      // app. The Android IME must not replace the image fixture while typing.
      await tester.enterText(input, '/paste');
      FocusManager.instance.primaryFocus?.unfocus();
      await until(() => tester.view.viewInsets.bottom == 0);
      await Pasteboard.writeImage(png);
      expect(await Pasteboard.image, isNotNull);
      await tap(find.byTooltip('Send'));
      await until(() => c.attachmentDrafts[draftKey]?.isNotEmpty == true);
    }
    if (Platform.isWindows) {
      await local(
        '/image "${file.path}"',
        () => c.attachmentDrafts[draftKey]?.length == 2,
      );
    }
    final old = (c.node.messages[conversationId] ?? [])
        .map((m) => m.messageId)
        .toSet();
    await send(
      'Harmless real image acceptance. Describe only the two shapes and their colors in the attached image. Do not use tools.',
    );
    await until(
      () => (c.node.messages[conversationId] ?? []).any(
        (m) =>
            !old.contains(m.messageId) &&
            m.author.type == 'bot' &&
            m.status == 'done' &&
            '${m.content['text']}'.toLowerCase().contains('red') &&
            '${m.content['text']}'.toLowerCase().contains('blue'),
      ),
      seconds: 240,
    );
    await until(() => c.node.activities[conversationId]?.state == 'idle');
    final reply = (c.node.messages[conversationId] ?? []).lastWhere(
      (m) => m.author.type == 'bot' && m.kind == 'text',
    );
    await local('/copy', () => true);
    expect(
      (await Clipboard.getData(Clipboard.kTextPlain))?.text,
      reply.content['text'],
    );
    debugPrint(
      'QA DEVICE: actual clipboard image, file upload, model vision and reply copy passed',
    );

    final memory = await c.rpc('memory.get', {'botId': botId});
    final previous =
        '${objects(memory['documents']).firstWhere((d) => d['name'] == 'MEMORY.md')['content']}';
    final marker =
        'Native command learning QA ${DateTime.now().millisecondsSinceEpoch}';
    await c.rpc('memory.save', {
      'botId': botId,
      'name': 'MEMORY.md',
      'content': '$previous\n\n§\n\n$marker',
    });
    await send('/journey');
    await until(() => find.byType(LearningPage).evaluate().isNotEmpty);
    await until(() => find.textContaining(marker).evaluate().isNotEmpty);
    await tester.ensureVisible(find.textContaining(marker).first);
    await tap(find.textContaining(marker).first);
    await until(() => find.byType(LearningEntryPage).evaluate().isNotEmpty);
    await tap(find.text('Edit'));
    await until(
      () => find.byKey(const ValueKey('learning-editor')).evaluate().isNotEmpty,
    );
    await tester.enterText(
      find.byKey(const ValueKey('learning-editor')),
      '$marker · edited in the native App',
    );
    await tap(find.text('Save'));
    await until(() => find.byType(LearningEntryPage).evaluate().isEmpty);
    final readback = await c.rpc('memory.get', {'botId': botId});
    expect(
      '${objects(readback['documents']).firstWhere((d) => d['name'] == 'MEMORY.md')['content']}',
      contains('$marker · edited in the native App'),
    );
    await tester.pageBack();
    await until(() => input.evaluate().isNotEmpty);
    debugPrint('QA DEVICE: native learning entry read/edit/readback passed');

    await send('/pet list');
    await until(() => find.byType(PetsPage).evaluate().isNotEmpty);
    await until(() => find.text('Select').evaluate().isNotEmpty);
    await tap(find.text('Select').first);
    await until(
      () => find.text('Currently enabled').evaluate().isNotEmpty,
      seconds: 180,
    );
    await until(() => find.byType(LinearProgressIndicator).evaluate().isEmpty);
    await tester.ensureVisible(find.text('Disable'));
    await tap(find.text('Disable'));
    await until(() => find.text('Currently enabled').evaluate().isEmpty);
    await tester.pageBack();
    await until(() => input.evaluate().isNotEmpty);
    await send('/hatch a friendly QA cat');
    await until(() => find.byType(PetsPage).evaluate().isNotEmpty);
    await until(
      () => find
          .textContaining('no reference-capable image provider')
          .evaluate()
          .isNotEmpty,
    );
    await tester.pageBack();
    await until(() => input.evaluate().isNotEmpty);
    await send('/subscription');
    await until(() => find.byType(SubscriptionPage).evaluate().isNotEmpty);
    await until(
      () => find
          .text('This profile is not signed in to Nous')
          .evaluate()
          .isNotEmpty,
    );
    await tester.pageBack();
    await until(() => input.evaluate().isNotEmpty);
    await send('/login');
    await until(() => find.byType(SourcesPage).evaluate().isNotEmpty);
    await tester.pageBack();
    await until(() => input.evaluate().isNotEmpty);
    await send('/model');
    await until(() => find.byType(BotEditor).evaluate().isNotEmpty);
    await tester.pageBack();
    await until(() => input.evaluate().isNotEmpty);
    await send('/plugins');
    await until(() => find.byType(PluginCenterPage).evaluate().isNotEmpty);
    await tester.pageBack();
    await until(() => input.evaluate().isNotEmpty);
    await send('/prompt Harmless unsent native draft');
    await until(
      () =>
          tester.widget<TextField>(input).controller!.text ==
          'Harmless unsent native draft',
    );
    await send('/palette');
    await until(() => tester.widget<TextField>(input).controller!.text == '/');
    await tester.enterText(input, '');
    debugPrint(
      'QA DEVICE: real pet adoption/disable and account navigation passed; hatch provider and Nous account unavailable',
    );

    if (Platform.isAndroid) {
      FocusManager.instance.primaryFocus?.unfocus();
      await until(() => tester.view.viewInsets.bottom == 0);
      await binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(milliseconds: 300));
      await binding.takeScreenshot('hermes-device-commands-android');
    }
    binding.reportData = {
      ...?binding.reportData,
      'realHermes': true,
      'nativeDisplayPreferences': true,
      'clipboardImageAndVision': true,
      'localImagePath': Platform.isWindows,
      'copyRealReply': true,
      'learningEditReadback': true,
      'nativePetSelectDisable': true,
      'nativeAccountNavigation': true,
      'modelAndPluginNavigation': true,
      'promptAndPaletteLocalPrefill': true,
      'hatch': 'missing image provider',
      'subscription': 'no Nous account',
    };
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 15)));
}
