import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/chat_models.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/ui/design.dart';

/// Takes the pictures for the Product Hunt gallery: the real client in English
/// against a running Relay with a real Node, Hermes and model, on an account set
/// up with English demo names (Iris, Bibi, Scout, Penny and the group Weekly
/// report). The Dots are really asked for what the pictures show: three spaces,
/// an answer that needs a command approved, a weekly report and a hand-off in
/// the group. What has been asked once is not asked again, so the tour can be
/// run a second time for the pictures alone. Desktop and phone size, light and
/// dark. The language is set for this run only and never saved.
/// Defines: RELAY_URL, QA_TOKEN, QA_NODE, TOUR_OUT.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('product hunt shots', (tester) async {
    final client = NekodotClient();
    final navigator = GlobalKey<NavigatorState>();
    final mode = ValueNotifier(ThemeMode.light);
    var glass = false;
    client.account.token = const String.fromEnvironment('QA_TOKEN');
    client.prefs.language = 'en';
    await tester.runAsync(() async {
      await client.bootstrap();
      await client.selectNode(const String.fromEnvironment('QA_NODE'));
      while (client.node.conversations.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    final out = Directory(const String.fromEnvironment('TOUR_OUT'));
    await tester.runAsync(() => out.create(recursive: true));
    // What has already been asked of the Dots, kept between runs.
    final done = File('${out.path}/asked.json');
    final asked = await tester.runAsync(
      () async => await done.exists()
          ? (jsonDecode(await done.readAsString()) as Map<String, dynamic>)
          : <String, dynamic>{},
    );
    Future<void> mark(String step) async {
      asked![step] = true;
      await tester.runAsync(() => done.writeAsString(jsonEncode(asked)));
    }

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
      print('TOUR $name.png');
    }

    // The same view in both themes.
    Future<void> both(String name, {int settle = 900}) async {
      await shot('$name-light', settle: settle);
      mode.value = ThemeMode.dark;
      await shot('$name-dark', settle: 600);
      mode.value = ThemeMode.light;
      await run(const Duration(milliseconds: 300));
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

    // The desktop window, or a phone.
    Future<void> stage({required bool phone}) async {
      await tester.pumpWidget(const SizedBox.shrink());
      glass = phone;
      tester.view.physicalSize = phone
          ? const Size(1080, 2340)
          : const Size(2560, 1600);
      tester.view.devicePixelRatio = phone ? 3 : 2;
      tester.view.padding = phone
          ? const FakeViewPadding(top: 108, bottom: 72)
          : FakeViewPadding.zero;
      await tester.pumpWidget(app());
      await run(const Duration(milliseconds: 700));
      navigator.currentState!.popUntil((route) => route.isFirst);
      await run(const Duration(milliseconds: 500));
    }

    final notes = <String, Object?>{};
    final nodeId = client.selectedNodeId!;
    Finder key(String name) => find.byKey(ValueKey(name));
    Finder section(String id) => key('home-section-$id');
    Finder row(String id) => key('conversation-$id');
    Map<String, dynamic> dot(String name) =>
        client.node.bots.firstWhere((b) => b['displayName'] == name);
    String talkWith(String name) =>
        '${client.node.conversations.firstWhere((c) => c['kind'] != 'group' && c['botId'] == dot(name)['botId'])['conversationId']}';
    final room =
        '${client.node.conversations.firstWhere((c) => c['kind'] == 'group')['conversationId']}';
    final iris = talkWith('Iris'), bibi = talkWith('Bibi');
    bool idle(String id) =>
        (client.node.activities[id]?.state ?? 'idle') == 'idle';
    Future<void> ask(String conversation, String text, {bool space = false}) =>
        tester.runAsync(
          () => client.deliveries.enqueue(
            'messages.send',
            {
              'conversationId': conversation,
              'text': text,
              'createSpace': ?(space ? true : null),
              'clientMsgId': uid(),
            },
            nodeId,
            [],
          ),
        );
    // Asked, and answered: the Dot starts within a moment and then rests.
    Future<bool> answered(String conversation, {int seconds = 300}) async {
      await until(() => !idle(conversation), seconds: 30);
      return until(() => idle(conversation), seconds: seconds);
    }

    Future<void> approvals(String name, String how) => tester.runAsync(
      () => client.rpc('bots.update', {
        'botId': dot(name)['botId'],
        'approvalMode': how,
      }),
    );
    ChatMessage? waiting() => (client.node.messages[iris] ?? [])
        .where((m) => m.kind == 'approval' && m.status == 'streaming')
        .lastOrNull;
    int built() => client.node.spaces.values
        .where((s) => !s.archived && s.version > 0 && s.icon != null)
        .length;
    Future<void> latest() async {
      if (key('chat-latest').evaluate().isNotEmpty) {
        await tester.tap(key('chat-latest'));
        await run(const Duration(milliseconds: 500));
      }
    }

    // ---------- what the Dots are asked for ----------
    // Three spaces, each by its own Dot, all at once: these take the longest.
    for (final (name, wish) in const [
      (
        'Penny',
        "Make a ledger: record an income or an expense, list the recent entries and this month's total.",
      ),
      (
        'Scout',
        'Make a small packing list page: list what to bring, let me tick things off, and show how many are still left.',
      ),
      (
        'Bibi',
        "Make a small page that teaches me 5 Spanish words a day: show today's 5 words with their meaning and let me mark each one as learned.",
      ),
    ]) {
      final has = client.node.spaces.values.any(
        (s) => s.botId == dot(name)['botId'],
      );
      if (!has && asked!['space-$name'] != true) {
        await ask(talkWith(name), wish, space: true);
        await mark('space-$name');
      }
    }

    client.workspace.remove('category:$nodeId');
    client.workspace.remove('details:$nodeId');
    client.workspace.remove('space:$nodeId');

    // ---------- an answer that needs a command approved ----------
    if (asked!['approval'] != true) {
      await stage(phone: false);
      await tester.tap(row(iris));
      await run(const Duration(milliseconds: 1500));
      await until(() => idle(iris), seconds: 120);
      await approvals('Iris', 'manual');
      await ask(
        iris,
        'Use Python to count the working days from today to the end of this year. Just tell me the number.',
      );
      notes['approvalAsked'] = await until(
        () => waiting() != null,
        seconds: 150,
      );
      await latest();
      await both('desk-approval', settle: 1200);
      // The same moment on a phone, where it is answered.
      await stage(phone: true);
      await tester.tap(row(iris));
      await run(const Duration(milliseconds: 1500));
      await latest();
      await both('phone-approval', settle: 1000);
      final pending = waiting();
      if (pending != null) {
        await tester.tap(key('choice-${pending.messageId}-0'));
        notes['approvalAnswered'] = await until(() => idle(iris), seconds: 240);
      }
      await approvals('Iris', 'off');
      await latest();
      await both('phone-chat', settle: 1200);
      navigator.currentState!.pop();
      await run(const Duration(milliseconds: 600));
      await mark('approval');
    }

    // ---------- the desktop ----------
    await stage(phone: false);
    await tester.tap(row(iris));
    await run(const Duration(milliseconds: 1500));
    await latest();
    await both('desk-chat', settle: 1200);
    await tester.tap(key('chat-flowchart'));
    await both('desk-flow', settle: 1500);
    if (key('flow-close').evaluate().isNotEmpty) {
      await tester.tap(key('flow-close'));
      await run(const Duration(milliseconds: 500));
    }

    // The spaces have been in the making all along.
    final making = Stopwatch()..start();
    notes['spacesBuilt'] = await until(() => built() >= 3, seconds: 1200);
    notes['spaces'] = built();
    notes['spacesSeconds'] = making.elapsed.inSeconds;

    // A weekly report, written by Bibi.
    await until(() => idle(bibi), seconds: 300);
    if (asked['report'] != true) {
      await ask(
        bibi,
        "Turn this week's progress into a short weekly report: the new sign-up flow shipped and active users are up 12%; the payment page passed design review; the analytics plan has a first draft.",
      );
      notes['report'] = await answered(bibi);
      await mark('report');
    }
    // One more turn, so that the conversation fills the window.
    if (asked['more'] != true) {
      await ask(
        bibi,
        'Add a plan for next week: three points at most, one sentence each.',
      );
      notes['more'] = await answered(bibi);
      await mark('more');
    }
    await until(() => idle(bibi), seconds: 180);
    await tester.tap(row(bibi));
    await run(const Duration(milliseconds: 1500));
    await latest();
    await both('desk-report', settle: 1500);

    // Every step of building a space, beside the conversation.
    final penny = talkWith('Penny');
    await until(() => idle(penny), seconds: 180);
    await tester.tap(row(penny));
    await run(const Duration(milliseconds: 1500));
    await latest();
    await tester.tap(key('chat-flowchart'));
    await both('desk-build', settle: 1800);
    if (key('flow-close').evaluate().isNotEmpty) {
      await tester.tap(key('flow-close'));
      await run(const Duration(milliseconds: 500));
    }

    // A hand-off in the group.
    if (asked['group'] != true) {
      await ask(
        room,
        "@bibi please draft this week's report: the new sign-up flow shipped, active users are up 12%, the payment page passed design review. When it is done, ask @iris to check how the 12% was measured.",
      );
      notes['group'] = await answered(room, seconds: 420);
      await mark('group');
    }
    await tester.tap(row(room));
    await run(const Duration(milliseconds: 1500));
    await latest();
    await both('desk-group', settle: 1200);

    // Spaces, once each has its picture.
    await tester.tap(section('space'));
    notes['pictured'] = await until(
      () => client.node.spaces.values
          .where((s) => !s.archived && s.version > 0)
          .every(
            (s) => client.spaces.thumbs.version(nodeId, s.spaceId) == s.version,
          ),
      seconds: 150,
    );
    await both('desk-spaces', settle: 1800);
    await tester.tap(section('plugins'));
    await both('desk-plugins', settle: 3000);
    await tester.tap(section('recent'));
    await run(const Duration(milliseconds: 500));

    // ---------- the phone ----------
    await stage(phone: true);
    await tester.tap(section('recent'));
    await both('phone-recent', settle: 1000);
    await tester.tap(row(room));
    await run(const Duration(milliseconds: 1500));
    await latest();
    await both('phone-group', settle: 1000);
    navigator.currentState!.pop();
    await run(const Duration(milliseconds: 600));
    await tester.tap(section('space'));
    await both('phone-spaces', settle: 1800);

    tester.view.reset();
    client.dispose();
    // ignore: avoid_print
    print('TOUR ${jsonEncode({'done': true, ...notes})}');
  }, timeout: const Timeout(Duration(minutes: 45)));
}
