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
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// Walks the account menu, settings and the pages a Bot's details lead to,
/// against a running Relay with a real Node, Hermes and model, and writes a
/// PNG of each step: the menu with its quick preferences, settings beside the
/// rail with model sources and shared Hermes settings as list and detail,
/// statistics, a Bot's learning journey, confidential information and
/// routines with a run on the timeline; then the account sheet and settings on
/// a phone. One routine is really created and run once.
/// Defines: RELAY_URL, QA_TOKEN, QA_NODE, QA_CONVERSATION, QA_GROUP, TOUR_OUT.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('settings tour', (tester) async {
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
    });
    const shell = String.fromEnvironment('TOUR_OUT');
    final out = Directory('$shell/../settings');
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
    final talk = '${asking['conversationId']}', botId = '${asking['botId']}';
    Finder key(String name) => find.byKey(ValueKey(name));
    Finder section(String id) => key('home-section-$id');
    // The rows of a list that has its detail beside it.
    final listed = find.descendant(
      of: find.byType(MasterDetail),
      matching: find.byType(ListTile),
    );
    // The way back inside the part of the window a setting opened in.
    final back = find.byType(BackButton);
    Future<void> dark(String name) async {
      mode.value = ThemeMode.dark;
      await shot(name);
      mode.value = ThemeMode.light;
      await run(const Duration(milliseconds: 300));
    }

    // One routine with one run, so that its page has something to show.
    const routineName = '仓库有新提交';
    await tester.runAsync(() async {
      try {
        // The Node has to be reachable before it is asked anything.
        for (var i = 0; i < 100 && !client.online; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        var routines = objects(
          (await client.rpc('routines.list', {'botId': botId}))['routines'],
        );
        if (!routines.any((r) => r['name'] == routineName)) {
          final made = await client.rpc('routines.create', {
            'botId': botId,
            'name': routineName,
            'description': '有新提交时总结改动',
            'prompt': '用一句话总结这次提交改了什么。',
            'events': ['push'],
            'skills': <String>[],
          });
          final target = {'botId': botId, 'routineId': made['routineId']};
          await client.rpc('routines.grant', target);
          await client.rpc('routines.test', {
            ...target,
            'payload': {
              'ref': 'refs/heads/main',
              'commits': [
                {'message': '首页改为导轨加最近列表'},
              ],
            },
            'requestId': uid(),
          });
          routines = objects(
            (await client.rpc('routines.list', {'botId': botId}))['routines'],
          );
        }
        notes['routines'] = routines.length;
        // A routine with no run yet is run once, so its timeline has an entry.
        final existing = routines.firstWhere((r) => r['name'] == routineName);
        final target = {'botId': botId, 'routineId': existing['routineId']};
        final detail = await client.rpc('routines.get', target);
        if (objects(detail['executions']).isEmpty) {
          await client.rpc('routines.test', {
            ...target,
            'payload': {'event_type': 'push', 'message': '首页改为导轨加最近列表'},
            'requestId': uid(),
          });
          for (var i = 0; i < 60; i++) {
            await Future<void>.delayed(const Duration(seconds: 2));
            final now = await client.rpc('routines.get', target);
            if (objects(now['executions']).isNotEmpty) break;
          }
        }
        notes['runs'] = objects(
          (await client.rpc('routines.get', target))['executions'],
        ).length;
      } catch (e) {
        notes['routineError'] = '$e';
      }
    });

    // ---------- desktop ----------
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2;
    client.workspace.remove('category:${client.selectedNodeId}');
    client.workspace.remove('details:${client.selectedNodeId}');
    await tester.pumpWidget(app());
    await run(const Duration(milliseconds: 600));

    // The account menu, then settings beside the rail.
    await tester.tap(find.byTooltip('账户'));
    await shot('desk-light-account-menu', settle: 700);
    await dark('desk-dark-account-menu');
    await tester.tap(key('account-settings'));
    await shot('desk-light-settings-account', settle: 1200);
    await tester.tap(key('settings-nav-bots'));
    await shot('desk-light-settings-bots');
    await tester.tap(key('settings-sources'));
    await shot('desk-light-sources', settle: 2500);
    if (listed.evaluate().isNotEmpty) {
      await tester.tap(listed.first);
      await shot('desk-light-sources-detail', settle: 2500);
      await dark('desk-dark-sources-detail');
    }
    await tester.tap(back.first);
    await run(const Duration(milliseconds: 700));
    await tester.tap(key('settings-shared-hermes'));
    await shot('desk-light-hermes', settle: 2500);
    if (listed.evaluate().isNotEmpty) {
      await tester.tap(listed.first);
      await shot('desk-light-hermes-group', settle: 2500);
    }
    await tester.tap(back.first);
    await run(const Duration(milliseconds: 700));
    await tester.tap(key('settings-nav-app'));
    await shot('desk-light-settings-app');
    await dark('desk-dark-settings-app');
    await tester.tap(key('settings-updates'));
    await shot('desk-light-updates', settle: 2500);
    await tester.tap(back.first);
    await run(const Duration(milliseconds: 700));

    // Statistics open over the window.
    await tester.tap(find.byTooltip('账户'));
    await run(const Duration(milliseconds: 600));
    await tester.tap(key('account-statistics'));
    await shot('desk-light-statistics', settle: 3500);
    await dark('desk-dark-statistics');
    navigator.currentState!.pop();
    await run(const Duration(milliseconds: 600));

    // What a Bot's details lead to: each a list with its detail beside it.
    await tester.tap(section('recent'));
    await run(const Duration(milliseconds: 600));
    await tester.tap(key('conversation-$talk'));
    await run(const Duration(milliseconds: 900));
    await tester.tap(find.byTooltip('详情'));
    await run(const Duration(milliseconds: 2500));
    await tester.tap(key('bot-learning'));
    await shot('desk-light-learning', settle: 3000);
    if (listed.evaluate().isNotEmpty) {
      await tester.tap(listed.first);
      await shot('desk-light-learning-entry', settle: 2500);
    }
    navigator.currentState!.pop();
    await run(const Duration(milliseconds: 700));
    final routine = find.text(routineName);
    notes['routineListed'] = routine.evaluate().isNotEmpty;
    if (routine.evaluate().isNotEmpty) {
      await tester.tap(routine.first);
      await shot('desk-light-routines', settle: 4000);
      // Its runs are at the end of the page beside the list.
      await tester.dragFrom(const Offset(900, 600), const Offset(0, -4000));
      await shot('desk-light-routines-runs', settle: 1200);
      await tester.dragFrom(const Offset(900, 300), const Offset(0, 4000));
      await run(const Duration(milliseconds: 500));
      await dark('desk-dark-routines');
      navigator.currentState!.pop();
      await run(const Duration(milliseconds: 700));
    }
    await tester.tap(key('details-part-3'));
    await run(const Duration(milliseconds: 900));
    await tester.tap(key('bot-secrets'));
    await shot('desk-light-secrets', settle: 2500);
    navigator.currentState!.pop();
    await run(const Duration(milliseconds: 700));

    // ---------- phone ----------
    await tester.pumpWidget(const SizedBox.shrink());
    glass = true;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 108, bottom: 72);
    client.workspace.remove('details:${client.selectedNodeId}');
    await tester.pumpWidget(app());
    await run(const Duration(milliseconds: 600));
    navigator.currentState!.popUntil((route) => route.isFirst);
    await run(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('账户'));
    await shot('phone-light-account-sheet', settle: 900);
    await dark('phone-dark-account-sheet');
    await tester.tap(key('account-settings'));
    await shot('phone-light-settings', settle: 1200);
    await tester.tap(key('settings-category-app'));
    await shot('phone-light-settings-app', settle: 900);
    navigator.currentState!.pop();
    await run(const Duration(milliseconds: 500));
    navigator.currentState!.pop();
    await run(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('账户'));
    await run(const Duration(milliseconds: 700));
    await tester.tap(key('account-statistics'));
    await shot('phone-light-statistics', settle: 3500);
    navigator.currentState!.pop();
    await run(const Duration(milliseconds: 500));

    tester.view.reset();
    client.dispose();
    // ignore: avoid_print
    print('TOUR ${jsonEncode({'done': true, ...notes})}');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
