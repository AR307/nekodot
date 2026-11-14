import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/local/runtime.dart';
import 'package:nekodot_native/local/system.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// Walks what is made and added, against a running Relay with a real Node,
/// Hermes and model, and writes a PNG of each step: spaces as a gallery and
/// one opened, the plugin center beside the rail, a new Bot with its preview,
/// a new group, and adding a computer step by step; then the same on a phone.
/// With no space yet, a Bot is really asked to build two.
/// Defines: RELAY_URL, QA_TOKEN, QA_NODE, QA_CONVERSATION, QA_GROUP, TOUR_OUT.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('create tour', (tester) async {
    final client = NekodotClient();
    final navigator = GlobalKey<NavigatorState>();
    final mode = ValueNotifier(ThemeMode.light);
    var glass = false;
    client.account.token = const String.fromEnvironment('QA_TOKEN');
    await tester.runAsync(() async {
      await client.bootstrap();
      await client.selectNode(const String.fromEnvironment('QA_NODE'));
      while (client.node.conversations.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      // The steps of adding a computer need to know what this one can do.
      localRuntime = LocalRuntime(client)..support = await localSupport();
    });
    const shell = String.fromEnvironment('TOUR_OUT');
    final out = Directory('$shell/../create');
    await tester.runAsync(() => out.create(recursive: true));

    Future<void> run(Duration time) async {
      final end = DateTime.now().add(time);
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 40));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
      }
    }

    Future<bool> until(bool Function() test, {int seconds = 120}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!test() && DateTime.now().isBefore(end)) {
        await run(const Duration(milliseconds: 500));
      }
      return test();
    }

    Future<void> shot(String name, {int settle = 900}) async {
      await run(Duration(milliseconds: settle));
      final view = tester.binding.renderViews.first;
      // ignore: invalid_use_of_protected_member
      final layer = view.layer! as OffsetLayer;
      final size = tester.view.physicalSize;
      await tester.runAsync(() async {
        final ui.Image image = await layer.toImage(Offset.zero & size);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${out.path}/$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      // ignore: avoid_print
      print('TOUR ${out.path}/$name.png');
    }

    Widget app() => ValueListenableBuilder(
      valueListenable: mode,
      builder: (context, value, _) => MaterialApp(
        navigatorKey: navigator,
        debugShowCheckedModeBanner: false,
        navigatorObservers: [nativeRoutes],
        theme: appTheme(Brightness.light, glass: glass),
        darkTheme: appTheme(Brightness.dark, glass: glass),
        themeMode: value,
        builder: (context, child) =>
            glass ? Ambient(child: child!) : WindowChrome(child: child!),
        home: HomePage(client: client),
      ),
    );

    final notes = <String, Object?>{};
    const dm = String.fromEnvironment('QA_CONVERSATION');
    final asking = client.node.conversations.firstWhere(
      (c) => c['kind'] != 'group' && c['conversationId'] != dm,
    );
    final talk = '${asking['conversationId']}';
    Finder key(String name) => find.byKey(ValueKey(name));
    Finder section(String id) => key('home-section-$id');
    // Asked for, and built: a space has a version once the Bot has made it.
    int asked() =>
        client.node.spaces.values.where((space) => !space.archived).length;
    int spaces() => client.node.spaces.values
        .where((space) => !space.archived && space.version > 0)
        .length;
    Future<void> dark(String name) async {
      mode.value = ThemeMode.dark;
      await shot(name);
      mode.value = ThemeMode.light;
      await run(const Duration(milliseconds: 300));
    }

    Future<void> name(String text) async {
      final field = key('bot-name');
      await tester.tap(field);
      await run(const Duration(milliseconds: 150));
      tester
              .widget<EditableText>(
                find.descendant(of: field, matching: find.byType(EditableText)),
              )
              .controller
              .text =
          text;
      await run(const Duration(milliseconds: 400));
    }

    // ---------- desktop ----------
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2;
    client.workspace.remove('category:${client.selectedNodeId}');
    client.workspace.remove('details:${client.selectedNodeId}');
    client.workspace.remove('space:${client.selectedNodeId}');
    await tester.pumpWidget(app());
    await run(const Duration(milliseconds: 600));

    // Spaces: none at first, then two a Bot really builds.
    await tester.tap(section('space'));
    if (spaces() == 0) await shot('desk-light-spaces-empty');
    for (final ask in const [
      '做一个记账本：能记一笔收入或支出，列出最近的记录和本月合计。',
      '做一个每天背 5 个单词的小页面：显示今天的 5 个词，可以标记记住了。',
    ]) {
      if (asked() >= 2) break;
      final before = asked();
      await tester.runAsync(
        () => client.deliveries.enqueue(
          'messages.send',
          {
            'conversationId': talk,
            'text': ask,
            'createSpace': true,
            'clientMsgId': uid(),
          },
          client.selectedNodeId!,
          [],
        ),
      );
      notes['asked${before + 1}'] = await until(
        () => asked() > before,
        seconds: 120,
      );
    }
    notes['built'] = await until(() => spaces() >= 2, seconds: 480);
    notes['spaces'] = spaces();
    await shot('desk-light-spaces', settle: 1500);
    await dark('desk-dark-spaces');
    final first = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('space-tile-'),
    );
    if (first.evaluate().isNotEmpty) {
      await tester.tap(first.first);
      await shot('desk-light-space-open', settle: 4000);
      await tester.tap(find.byTooltip('返回'));
      await shot('desk-light-spaces-back', settle: 900);
    }

    // The plugin center fills the window beside the rail.
    await tester.tap(section('plugins'));
    await shot('desk-light-plugins', settle: 2500);
    await tester.tap(key('plugin-kind-mcp'));
    await shot('desk-light-plugins-mcp', settle: 1800);
    await tester.tap(key('plugin-kind-connectors'));
    await shot('desk-light-plugins-connectors', settle: 2500);
    await dark('desk-dark-plugins-connectors');

    // A new Bot beside what it will look like.
    await tester.tap(section('recent'));
    await run(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('新建'));
    await run(const Duration(milliseconds: 500));
    await tester.tap(find.text('新建 Bot').last);
    await shot('desk-light-new-bot', settle: 2000);
    await name('摘要员');
    await tester.tap(find.byTooltip('兔'));
    await run(const Duration(milliseconds: 300));
    await tester.tap(key('avatar-color-${avatarColors[5]}'));
    await run(const Duration(milliseconds: 300));
    await tester.tap(find.text('全部允许'));
    await shot('desk-light-new-bot-filled', settle: 900);
    await dark('desk-dark-new-bot-filled');
    navigator.currentState!.pop();
    await run(const Duration(milliseconds: 600));

    await tester.tap(find.byTooltip('新建'));
    await run(const Duration(milliseconds: 500));
    await tester.tap(find.text('新建群组').last);
    await shot('desk-light-new-group', settle: 1500);
    navigator.currentState!.pop();
    await run(const Duration(milliseconds: 600));

    // Adding a computer, step by step.
    await tester.tap(find.byTooltip('电脑').first);
    await run(const Duration(milliseconds: 500));
    await tester.tap(find.text('添加电脑').last);
    await shot('desk-light-add-computer', settle: 1500);
    await tester.tap(key('run-here'));
    await shot('desk-light-add-computer-folders', settle: 2500);
    await dark('desk-dark-add-computer-folders');
    await tester.tap(key('add-computer-step-0'));
    await run(const Duration(milliseconds: 500));
    await tester.tap(key('connect-server'));
    await shot('desk-light-add-computer-server', settle: 3000);
    navigator.currentState!.pop();
    await run(const Duration(milliseconds: 600));

    // ---------- phone ----------
    await tester.pumpWidget(const SizedBox.shrink());
    glass = true;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 108, bottom: 72);
    await tester.pumpWidget(app());
    await run(const Duration(milliseconds: 600));
    navigator.currentState!.popUntil((route) => route.isFirst);
    await run(const Duration(milliseconds: 500));
    await tester.tap(section('space'));
    await shot('phone-light-spaces', settle: 1200);
    await dark('phone-dark-spaces');
    await tester.tap(section('recent'));
    await run(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('新建'));
    await run(const Duration(milliseconds: 600));
    await tester.tap(find.text('新建 Bot').last);
    await shot('phone-light-new-bot', settle: 2000);
    await name('摘要员');
    await tester.tap(find.byTooltip('兔'));
    await shot('phone-light-new-bot-filled', settle: 700);
    await dark('phone-dark-new-bot-filled');
    navigator.currentState!.pop();
    await run(const Duration(milliseconds: 600));

    localRuntime = null;
    tester.view.reset();
    client.dispose();
    // ignore: avoid_print
    print('TOUR ${jsonEncode({'done': true, ...notes})}');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
