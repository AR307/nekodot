import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/data/spaces.dart';
import 'package:nekodot_native/features/files.dart';
import 'package:nekodot_native/features/chat.dart';
import 'package:nekodot_native/features/spaces.dart';
import 'package:nekodot_native/features/space_webview.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

import 'local_desktop_journey_test.dart' show MemoryVault;

// Real reported publication, real embedded browser, real isolated services.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Space rendering, named attachments and live activity', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'notification-requested': true});
    final c = NekodotClient(vault: MemoryVault());
    addTearDown(c.dispose);
    final phone = Platform.isAndroid;
    final mode = ValueNotifier(ThemeMode.light);
    final out = await tester.runAsync(() async {
      final root = phone
          ? '${(await getExternalStorageDirectory())!.path}/spaces-ui-fixes'
          : const String.fromEnvironment('QA_EVIDENCE_DIR');
      return Directory(root)..createSync(recursive: true);
    });
    final results = <String, Object?>{'platform': Platform.operatingSystem};
    Future<void> frames([int ms = 300]) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 40));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
      }
    }

    Future<void> until(
      bool Function() ready,
      String label, {
      int seconds = 90,
    }) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(end)) {
        await frames(120);
      }
      expect(ready(), isTrue, reason: label);
      debugPrint('SPACE_UI verified $label');
    }

    Future<void> mount(Widget child, {bool settle = true}) async {
      await tester.pumpWidget(
        ValueListenableBuilder(
          valueListenable: mode,
          builder: (_, value, _) => MaterialApp(
            navigatorObservers: [nativeRoutes],
            theme: appTheme(Brightness.light, glass: phone),
            darkTheme: appTheme(Brightness.dark, glass: phone),
            themeMode: value,
            builder: (_, child) =>
                phone ? Ambient(child: child!) : WindowChrome(child: child!),
            home: child,
          ),
        ),
      );
      if (settle) await frames();
    }

    Future<void> tap(Finder target) async {
      await tester.ensureVisible(target.first);
      await until(
        () => target.hitTestable().evaluate().isNotEmpty,
        'navigation target ready',
      );
      await tester.tap(target.hitTestable().first);
      await frames();
    }

    InAppWebViewController controller() {
      final dynamic state = tester.state(find.byType(SpaceWebView));
      return state.controller as InAppWebViewController;
    }

    Future<dynamic> js(String source) =>
        tester.runAsync(() => controller().evaluateJavascript(source: source));
    Future<void> shot(String name) async {
      final bytes = await tester.runAsync(() => controller().takeScreenshot());
      expect(bytes, isNotNull);
      await tester.runAsync(
        () => File('${out!.path}/$name.png').writeAsBytes(bytes!),
      );
    }

    if (!phone) {
      await tester.runAsync(() async {
        await DesktopHost.initialize();
        await windowManager.setTitle('nekodot Space UI QA');
        await windowManager.setSize(const Size(1180, 820));
      });
    }
    await tester.runAsync(() async {
      c.account.token = const String.fromEnvironment('QA_TOKEN');
      await c.prefs.load();
      await c.bootstrap();
      await c.selectNode(const String.fromEnvironment('QA_NODE'));
    });
    await until(
      () => c.online && c.node.bots.isNotEmpty,
      'real Node connected',
    );
    const dm = String.fromEnvironment('QA_CONVERSATION');
    if (c.node.spaces.values.every((s) => s.fileId == null)) {
      await tester.runAsync(
        () => c.rpc('messages.send', {
          'conversationId': dm,
          'clientMsgId': uid(),
          'createSpace': true,
          'text':
              'Create and publish one small offline Space named Space UI QA. '
              'Use the native nekodot-spaces skill and tool. Include a responsive '
              'heading, three visually distinct cards and a button that stores a '
              'counter with nekodotSpace. Use bundled CSS, no external resources. '
              'Also create and deliver a small text attachment named space-ui-qa.txt. '
              'Do not touch other files or create background tasks.',
        }),
      );
      await until(
        () => c.node.spaces.values.any((s) => s.fileId != null),
        'real model published QA Space',
        seconds: 360,
      );
      await until(
        () => (c.node.activities[dm]?.state ?? 'idle') == 'idle',
        'Space creation completed',
        seconds: 180,
      );
    }
    final response = await tester.runAsync(
      () => http.get(
        Uri.parse(const String.fromEnvironment('QA_REPORTED_SPACE_URL')),
      ),
    );
    expect(response!.statusCode, 200);
    final eager = Stopwatch()..start();
    final unpacked = {
      for (final f in ZipDecoder().decodeBytes(response.bodyBytes))
        if (f.isFile) f.name: f.readBytes()!,
    };
    eager.stop();
    final lazy = Stopwatch()..start();
    final bundle = SpaceBundle(response.bodyBytes);
    lazy.stop();
    results['package'] = {
      'compressedBytes': response.bodyBytes.length,
      'unpackedBytes': unpacked.values.fold<int>(0, (sum, b) => sum + b.length),
      'files': bundle.files.length,
      'eagerDecodeUs': eager.elapsedMicroseconds,
      'lazyIndexUs': lazy.elapsedMicroseconds,
    };
    unpacked.clear();
    final reported = Space.fromJson(
      object(jsonDecode(const String.fromEnvironment('QA_REPORTED_SPACE'))),
    );
    WebViewEnvironment? environment;
    if (!phone) {
      environment = await tester.runAsync(
        () => createSpaceEnvironment(c.store!.file('spaces/browser').path),
      );
    }
    var drawn = false;
    final open = Stopwatch()..start();
    await mount(
      Scaffold(
        body: SpaceWebView(
          client: c,
          nodeId: c.selectedNodeId!,
          space: reported,
          bundle: bundle,
          environment: environment,
          onError: () => fail('Reported Space failed to load'),
          onDrawn: () => drawn = true,
        ),
      ),
    );
    await until(() => drawn, 'reported publication drawn');
    results['reportedFirstPaintMs'] = open.elapsedMilliseconds;
    await frames(500);
    const colors =
        'JSON.stringify({background:getComputedStyle(document.body).backgroundColor,foreground:getComputedStyle(document.querySelector("#board")).color,card:getComputedStyle(document.querySelector(".card")).backgroundColor,styles:document.styleSheets.length,width:innerWidth,scrollWidth:document.documentElement.scrollWidth})';
    final light = jsonDecode(await js(colors) as String) as Map;
    expect(light['foreground'], isNot('rgb(232, 234, 239)'));
    expect(light['background'], isNot(light['foreground']));
    results['light'] = light;
    await shot('reported-light');
    await js('window.scrollTo(0, 700)');
    await frames();
    expect(await js('scrollY'), greaterThan(0));
    mode.value = ThemeMode.dark;
    await frames(600);
    final dark = jsonDecode(await js(colors) as String) as Map;
    expect(dark['background'], isNot(light['background']));
    expect(dark['foreground'], isNot(light['foreground']));
    results['dark'] = dark;
    await shot('reported-dark');
    await mount(const SizedBox.shrink());
    await tester.runAsync(() async {
      await environment?.dispose();
    });
    final available = c.node.spaces.values
        .where((s) => s.fileId != null)
        .toList();
    expect(available, isNotEmpty, reason: 'real model-created QA Space');
    final real = available.first;
    final timings = <int>[];
    final environments = <int>[];
    for (var i = 0; i < 3; i++) {
      final clock = Stopwatch()..start();
      await mount(
        SpacePage(client: c, nodeId: c.selectedNodeId!, spaceId: real.spaceId),
      );
      if (!phone) {
        await until(() {
          final dynamic page = tester.state(find.byType(SpacePage));
          return page.environment != null;
        }, 'browser environment ready');
        environments.add(clock.elapsedMilliseconds);
      }
      await until(
        () => find.byType(SpaceWebView).evaluate().isNotEmpty,
        'Space page opened',
      );
      await until(() {
        final dynamic page = tester.state(find.byType(SpacePage));
        return page.live == true;
      }, 'Space page first paint');
      timings.add(clock.elapsedMilliseconds);
      expect(find.byType(WindowDrag), findsWidgets);
      await shot('real-space-$i');
      await mount(const SizedBox.shrink());
    }
    results['spaceOpenMs'] = timings;
    results['environmentReadyMs'] = environments;
    debugPrint('SPACE_UI open $timings environment $environments');
    final list = await tester.runAsync(
      () => c.rpc('files.list', {'botId': real.botId}),
    );
    final file = objects(list!['files'])
        .firstWhere((f) => f['name'] == 'space-ui-qa.txt');
    final id = file['fileId'] as String;
    final metadata = await tester.runAsync(
      () => c.rpc('files.get', {'fileId': id}),
    );
    for (var i = 0; i < 2; i++) {
      await mount(
        Scaffold(
          body: FileCard(client: c, fileId: id, messageId: 'qa'),
        ),
        settle: false,
      );
      expect(find.text('附件'), findsNothing);
      if (!'${metadata!['mime']}'.startsWith('image/')) {
        expect(find.text(metadata['name'] as String), findsOneWidget);
      }
      await mount(const SizedBox.shrink());
    }
    results['attachmentReopen'] = 'name retained';
    mode.value = ThemeMode.light;
    await mount(ChatPage(client: c, conversationId: dm));
    final input = find.byKey(const ValueKey('chat-input'));
    await until(() => input.evaluate().isNotEmpty, 'composer available');
    await tester.enterText(
      input,
      '执行一次终端命令等待 3 秒，然后只回复“状态验收完成”。不要创建文件，不要安排后台任务。',
    );
    await frames();
    await tap(find.byTooltip('发送'));
    await until(
      () => find.byKey(const ValueKey('dot-activity')).evaluate().isNotEmpty,
      'live Dot activity visible',
      seconds: 180,
    );
    await until(
      () => (c.node.activities[dm]?.state ?? 'idle') == 'idle',
      'real model completed',
      seconds: 240,
    );
    await frames();
    expect(find.byKey(const ValueKey('dot-activity')), findsNothing);
    results['activity'] = 'visible while working; removed when idle';
    await tester.runAsync(
      () => File('${out!.path}/result.json').writeAsString(jsonEncode(results)),
    );
    debugPrint('SPACE_UI ${jsonEncode(results)}');
    await mount(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 15)));
}
