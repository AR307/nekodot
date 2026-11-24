import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/json.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/workplace.dart';
import 'package:nekodot_native/platform/desktop.dart';
import 'package:nekodot_native/screen/viewer.dart';
import 'package:nekodot_native/ui/design.dart';

/// Keeps the session in memory, so the installed client's own login is never touched.
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

/// A Dot on a computer that cannot run a screen (the WSL stand-in for a small
/// VPS) is handed a sandbox provider's key through a confidential card, moves
/// its commands, browser and screen into a sandbox there, works on the screen,
/// comes back, and puts a whole new computer into another sandbox. The user's
/// side is the real Windows client against the local acceptance Relay; the
/// provider is .runtime/sandbox-qa/provider.ts over Docker containers.
/// Defines: RELAY_URL, QA_TOKEN, QA_PROVIDER_URL, QA_PROVIDER_KEY,
/// QA_PROVIDER_MODEL, QA_SANDBOX_KEY, TOUR_OUT.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('a Dot works in a sandbox it set up with my key', (tester) async {
    final client = NekodotClient(vault: MemoryVault());
    expect(client.account.origin.host, '127.0.0.1');
    client.account.token = const String.fromEnvironment('QA_TOKEN');
    await tester.runAsync(client.bootstrap);
    final out = Directory(const String.fromEnvironment('TOUR_OUT'));
    await tester.runAsync(() => out.create(recursive: true));
    final notes = <String, Object?>{};
    final navigator = GlobalKey<NavigatorState>();
    final answered = <String>{};
    final approvals = <String>[];

    Future<void> run(Duration time) async {
      final end = DateTime.now().add(time);
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 40));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
      }
    }

    Future<void> shot(String name, {int settle = 600}) async {
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

    Future<void> show(Widget home) async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.physicalSize = const Size(2560, 1600);
      tester.view.devicePixelRatio = 2;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          debugShowCheckedModeBanner: false,
          theme: appTheme(Brightness.light),
          builder: (context, child) => WindowChrome(child: child!),
          home: home,
        ),
      );
      await run(const Duration(milliseconds: 600));
    }

    /// Taps [finder] after bringing it to the middle of its list, clear of
    /// the composer floating over the end of a chat.
    Future<void> tap(Finder finder) async {
      final target = finder.first;
      if (Scrollable.maybeOf(tester.element(target)) != null) {
        // ignore: unawaited_futures
        Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
      }
      await run(const Duration(milliseconds: 800));
      await tester.tap(target);
      await run(const Duration(milliseconds: 600));
    }

    Future<String> docker(List<String> args) async {
      final result = await tester.runAsync(
        () => Process.run(
          'docker',
          args,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        ),
      );
      return '${result!.stdout}${result.stderr}'.trim();
    }

    // ---------- a Dot on the small computer, with the real model ----------
    for (var i = 0; i < 120 && !client.online; i++) {
      await run(const Duration(milliseconds: 500));
    }
    final nodeId = client.selectedNodeId!;
    notes['node'] = client.node.online;
    final sourceId = await tester.runAsync(
      () async =>
          '${(await client.rpc('providers.set', {'kind': 'custom', 'name': 'QA model', 'baseUrl': const String.fromEnvironment('QA_PROVIDER_URL'), 'apiKey': const String.fromEnvironment('QA_PROVIDER_KEY')}))['sourceId']}',
    );
    // Earlier runs left Dots on this computer: this one has a name of its own.
    final suffix = DateTime.now().millisecondsSinceEpoch % 100000;
    final name = 'Desk $suffix';
    final created = await tester.runAsync(
      () => client.rpc('bots.create', {
        'displayName': name,
        'handle': 'desk$suffix',
        'role': 'Keep replies short.',
        'model': const String.fromEnvironment('QA_PROVIDER_MODEL'),
        'avatar': {'shape': 'dot', 'color': '#2E8BFF'},
        // Approvals are the user's: every card is answered here, by tapping it.
        'approvalMode': 'manual',
        'sourceId': sourceId,
      }),
    );
    final bot = object(created!['bot']);
    final botId = '${bot['botId']}';
    final conversation = '${created['conversation']['conversationId']}';
    Future<Json?> workplace() async =>
        (await tester.runAsync(
              () => client.rpc('bots.workplace', {'botId': botId}),
            ))!['workplace']
            as Json?;

    final row = find.byKey(ValueKey('conversation-$conversation'));

    /// Opens this Dot's chat on the home page. The list re-sorts as messages
    /// arrive, so a tap can land on the row that moved into its place: tap
    /// until the chat's header names this Dot (its row names it too).
    Future<void> openChat() async {
      await show(HomePage(client: client));
      for (var i = 0; i < 20; i++) {
        for (var j = 0; j < 20 && row.evaluate().isEmpty; j++) {
          await run(const Duration(milliseconds: 500));
        }
        await tester.tap(row, warnIfMissed: false);
        await run(const Duration(seconds: 1));
        if (find.text(name).evaluate().length >= 2) return;
      }
      fail('Could not open the chat of $name');
    }

    await openChat();

    /// The user's part while the Dot works: the provider key into its card,
    /// "once" on each approval. Each is answered by tapping the real card.
    Future<void> answerCards() async {
      // New cards arrive at the end of the chat: go there first.
      final latest = find.byKey(const ValueKey('chat-latest'));
      if (latest.evaluate().isNotEmpty) {
        await tester.tap(latest, warnIfMissed: false);
        await run(const Duration(milliseconds: 800));
      }
      final secret = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey &&
            '${(w.key! as ValueKey).value}'.startsWith('secret-field-'),
      );
      if (secret.evaluate().isNotEmpty && !answered.contains('secret')) {
        answered.add('secret');
        // ignore: unawaited_futures
        Scrollable.ensureVisible(tester.element(secret.first), alignment: 0.5);
        await run(const Duration(milliseconds: 800));
        await tester.enterText(
          secret.first,
          const String.fromEnvironment('QA_SANDBOX_KEY'),
        );
        await run(const Duration(milliseconds: 400));
        await shot('secret-card');
        await tap(find.byKey(const ValueKey('secret-submit')));
        await run(const Duration(seconds: 3));
        // Delivered: the card no longer asks. Otherwise the next pass tries again.
        if (secret.evaluate().isEmpty) {
          notes['secretDelivered'] = true;
        } else {
          answered.remove('secret');
        }
      }
      for (final m in [...?client.node.messages[conversation]]) {
        if (m.kind != 'approval' || answered.contains(m.messageId)) continue;
        final content = m.content;
        if (content['choice'] != null) continue;
        final choices = (content['choices'] as List? ?? const [])
            .map((c) => '$c')
            .toList();
        final index = choices.indexOf('once');
        final card = find.byKey(ValueKey('choice-${m.messageId}-$index'));
        if (index < 0 || card.evaluate().isEmpty) continue;
        answered.add(m.messageId);
        approvals.add('${content['command'] ?? content['prompt']}');
        await shot('approval-${approvals.length}');
        await tap(card);
      }
    }

    /// Whether the Dot is still at work in this chat: its own turn or a task.
    bool busy() {
      final state = client.node.activities[conversation]?.state;
      return (state != null && state != 'idle') ||
          client.node.tasks.values.any(
            (t) =>
                t.conversationId == conversation &&
                !const ['completed', 'failed', 'cancelled'].contains(t.state),
          );
    }

    /// Sends [text], serves the cards, and once the Dot has finished (no turn
    /// or task at work for 15 s after a finished reply) returns whether its
    /// replies pass [done].
    Future<bool> ask(
      String text,
      bool Function(String reply) done, {
      int minutes = 12,
      Future<bool> Function()? until,
    }) async {
      if (find.text(name).evaluate().length < 2) await openChat();
      await tester.runAsync(
        () => client.deliveries.enqueue(
          'messages.send',
          {'conversationId': conversation, 'text': text, 'clientMsgId': uid()},
          nodeId,
          [],
        ),
      );
      await run(const Duration(seconds: 2));
      final end = DateTime.now().add(Duration(minutes: minutes));
      DateTime? idle;
      var reached = until == null;
      var checked = DateTime.now();
      while (DateTime.now().isBefore(end)) {
        await answerCards();
        if (!reached &&
            DateTime.now().difference(checked) > const Duration(seconds: 5)) {
          checked = DateTime.now();
          reached = await until!();
        }
        final messages = client.node.messages[conversation] ?? const [];
        final asked = messages.lastIndexWhere(
          (m) => m.author.type == 'user' && '${m.content['text']}' == text,
        );
        final replies = asked < 0
            ? const <String>[]
            : messages
                  .skip(asked + 1)
                  .where(
                    (m) =>
                        m.author.type != 'user' &&
                        m.kind == 'text' &&
                        m.taskRole != 'execution' &&
                        m.status == 'done',
                  )
                  .map((m) => '${m.content['text']}')
                  .toList();
        if (reached && replies.isNotEmpty && !busy()) {
          idle ??= DateTime.now();
          if (DateTime.now().difference(idle) > const Duration(seconds: 15)) {
            notes['reply ${notes.length}'] = replies.join(' | ');
            return replies.any(done);
          }
        } else {
          idle = null;
        }
        await run(const Duration(seconds: 1));
      }
      notes['timeout ${notes.length}'] = text;
      return false;
    }

    // ---------- my key, its sandbox ----------
    notes['moved'] = await ask(
      'This computer has too little memory for your screen. I have a sandbox for you at my '
      'provider, QA Sandbox Cloud: the API is at http://172.19.32.1:4613 and its documentation '
      'is at GET /. Ask me for the API key with a confidential card. Move your work into my '
      'existing sandbox qa-desk following your nekodot-sandbox skill, then tell me in one sentence.',
      (reply) => reply.isNotEmpty,
      minutes: 25,
      until: () async => await workplace() != null,
    );
    await shot('moved', settle: 1500);
    notes['workplace'] = await workplace();
    expect(notes['workplace'], isNotNull, reason: 'The Dot did not move');
    notes['approvals'] = approvals;

    notes['hostnameThere'] = await ask(
      'Run the command hostname and reply with its exact output only.',
      (reply) => reply.split(RegExp(r'[\s`]+')).contains('qa-desk'),
    );

    // ---------- its screen, in the sandbox ----------
    await show(ScreenPage(client: client, bot: bot));
    await shot('screen-before', settle: 2500);
    final start = find.byWidgetPredicate(
      (w) => w is Text && (w.data == 'Start screen' || w.data == '启动屏幕'),
    );
    notes['screenCouldStart'] = start.evaluate().isNotEmpty;
    if (start.evaluate().isNotEmpty) await tap(start.first);
    var running = false;
    for (var i = 0; i < 90 && !running; i++) {
      await run(const Duration(seconds: 2));
      // Hermes restarts once after a move: a status asked meanwhile fails.
      final status = await tester.runAsync(
        () => client
            .rpc('screen.status', {'botId': botId})
            .then<Json?>((value) => value, onError: (_) => null),
      );
      running = status?['running'] == true;
    }
    notes['screenRunning'] = running;
    await shot('screen-running', settle: 8000);
    notes['xvncInSandbox'] = await docker([
      'exec',
      'nekodot-qa-desk',
      'pgrep',
      '-c',
      'Xvnc',
    ]);

    await openChat();
    notes['browsed'] = await ask(
      'Open https://example.com in the browser on your screen and tell me the main heading '
      'of the page.',
      (reply) => reply.contains('Example Domain'),
    );
    await show(ScreenPage(client: client, bot: bot));
    await shot('screen-browser', settle: 8000);
    notes['browserInSandbox'] = await docker([
      'exec',
      'nekodot-qa-desk',
      'bash',
      '-c',
      'pgrep -fc "chrom"',
    ]);

    // ---------- back to its own computer ----------
    await show(
      AppPage(
        title: 'Desk',
        body: PageList(
          children: [WorkplaceTile(client: client, botId: botId)],
        ),
      ),
    );
    await shot('workplace', settle: 2000);
    await tap(find.byKey(const ValueKey('bot-workplace-home')));
    await run(const Duration(seconds: 3));
    notes['workplaceAfterHome'] = await workplace();
    await shot('workplace-home', settle: 1000);

    await openChat();
    notes['hostnameHome'] = await ask(
      'Run the command hostname again and reply with its exact output only.',
      // WSL takes this computer's name.
      (reply) =>
          reply.split(RegExp(r'[\s`*]+')).contains(Platform.localHostname),
    );

    // ---------- a whole new computer in another sandbox ----------
    final before = (client.account.me?['nodes'] as List? ?? const []).length;
    notes['computer'] = await ask(
      'Now I also want a whole new nekodot computer named QA box, in a new sandbox at the same '
      'provider. Set it up following your nekodot-sandbox skill and tell me when it is online.',
      (reply) => reply.isNotEmpty,
      minutes: 30,
    );
    await shot('computer', settle: 1500);
    final me = await tester.runAsync(() => client.account.request('/me'));
    final nodes = objects(me!['nodes']);
    notes['nodes'] = nodes.map((n) => '${n['name']}:${n['online']}').toList();
    notes['newComputer'] =
        nodes.length > before &&
        nodes.any((n) => n['name'] == 'QA box' && n['online'] == true);
    notes['approvals'] = approvals;

    tester.view.reset();
    await tester.pumpWidget(const SizedBox.shrink());
    client.dispose();
    // ignore: avoid_print
    print('TOUR ${jsonEncode(notes)}');
  }, timeout: const Timeout(Duration(minutes: 90)));
}
