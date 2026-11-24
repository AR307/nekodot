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
import 'package:nekodot_native/data/sandbox/host.dart';
import 'package:nekodot_native/features/home.dart';
import 'package:nekodot_native/features/local_setup.dart';
import 'package:nekodot_native/features/sandbox_setup.dart';
import 'package:nekodot_native/platform/desktop.dart';
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

/// A stand-in for a provider's API: the "sandbox" is HOME=/root/sandbox-qa in
/// WSL Ubuntu 24.04, where the node runs without a systemd service exactly as
/// install.sh --sandbox sets it up. Making one moves the previous identity
/// aside, so the installer pairs a new computer on the same files.
class WslHost implements SandboxHost {
  String get home => '/root/sandbox-qa';
  @override
  String get provider => 'daytona';

  Future<CommandResult> _wsl(String script) async {
    final result = await Process.run(
      'wsl.exe',
      [
        '-d',
        'Ubuntu-24.04',
        // Not "--", which hands the line to a shell that expands $HOME first.
        '--exec',
        'env',
        'HOME=$home',
        'bash',
        '-c',
        script,
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    return CommandResult(result.exitCode, '${result.stdout}${result.stderr}');
  }

  /// Everything the node runs ends, as when a sandbox is stopped.
  Future<void> halt() async => _wsl(r'pkill -9 -f "$HOME/.nekodot/" || true');

  @override
  Future<String> create(String name, SandboxSize size) async {
    await halt();
    await _wsl(
      r'mv -f "$HOME/.nekodot/node.json" "$HOME/.nekodot/node.json.before-$(date +%s)" 2>/dev/null; true',
    );
    return 'wsl';
  }

  @override
  Future<SandboxState> state(String id) async =>
      (await _wsl(r'pgrep -f "^bash $HOME/.nekodot/bin/nekodot-supervise"'))
              .exitCode ==
          0
      ? SandboxState.running
      : SandboxState.stopped;

  @override
  Future<void> wake(String id) async {}
  @override
  Future<CommandResult> exec(String id, String script) => _wsl(script);
  @override
  Future<void> launch(String id, String script) async {
    await _wsl(
      'setsid nohup bash -c ${shellQuote(script)} > /dev/null 2>&1 < /dev/null & sleep 1',
    );
  }

  @override
  Future<void> delete(String id) => halt();
}

/// A Daytona account below Tier 3: the sandbox is made, but nothing in it can
/// reach the Relay. Its installer fails the way curl does behind Daytona's
/// proxy, in a home of its own, so the running computer is not touched.
class BlockedHost extends WslHost {
  @override
  String get home => '/root/sandbox-qa-blocked';
  @override
  Future<String> create(String name, SandboxSize size) async => 'blocked';
  @override
  Future<void> launch(String id, String script) async {
    await _wsl(
      r'mkdir -p "$HOME/.nekodot-install" && '
      r'echo "curl: (56) CONNECT tunnel failed, response 403" '
      r'> "$HOME/.nekodot-install/log" && echo 56 > "$HOME/.nekodot-install/exit"',
    );
  }
}

/// Adds a computer in a "cloud sandbox" from the real add-computer page of the
/// Windows client, against the local acceptance Relay in .runtime/sandbox-qa,
/// then makes a Dot there and talks to it with the real model, stops the
/// sandbox and wakes it from settings. Defines: RELAY_URL, QA_TOKEN,
/// QA_PROVIDER_URL, QA_PROVIDER_KEY, QA_PROVIDER_MODEL, TOUR_OUT.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('a computer in a cloud sandbox, end to end', (tester) async {
    final client = NekodotClient(vault: MemoryVault());
    expect(client.account.origin.host, '127.0.0.1');
    client.account.token = const String.fromEnvironment('QA_TOKEN');
    final host = WslHost();
    client.sandboxes.makeHost = (_, _) => host;
    await tester.runAsync(client.bootstrap);
    final out = Directory(const String.fromEnvironment('TOUR_OUT'));
    await tester.runAsync(() => out.create(recursive: true));
    final notes = <String, Object?>{};
    final navigator = GlobalKey<NavigatorState>();

    Future<void> run(Duration time) async {
      final end = DateTime.now().add(time);
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 40));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
      }
    }

    Future<bool> until(bool Function() test, {int seconds = 60}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!test() && DateTime.now().isBefore(end)) {
        await run(const Duration(milliseconds: 500));
      }
      return test();
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

    // ---------- add a computer in a cloud sandbox ----------
    await show(RunLocationPage(client: client));
    await shot('choose');
    await tester.tap(find.byKey(const ValueKey('run-sandbox')));
    await run(const Duration(milliseconds: 600));
    await tester.enterText(
      find.byKey(const ValueKey('sandbox-daytona-key')),
      'wsl-stand-in',
    );
    await tester.enterText(
      find.byKey(const ValueKey('sandbox-name')),
      'WSL sandbox 2',
    );
    await shot('form');
    final started = DateTime.now();
    await tester.ensureVisible(find.byKey(const ValueKey('sandbox-create')));
    await tester.tap(find.byKey(const ValueKey('sandbox-create')));
    await until(
      () => find.byKey(const ValueKey('sandbox-log')).evaluate().isNotEmpty,
      seconds: 120,
    );
    await shot('installing');
    notes['done'] = await until(
      () =>
          find.byKey(const ValueKey('add-computer-done')).evaluate().isNotEmpty,
      seconds: 900,
    );
    notes['installSeconds'] = DateTime.now().difference(started).inSeconds;
    if (find.byKey(const ValueKey('sandbox-discard')).evaluate().isNotEmpty) {
      await shot('failed');
    }
    expect(notes['done'], isTrue, reason: 'The computer was not added');
    await shot('connected');
    final record = client.sandboxes.records.single;
    final nodeId = record.nodeId!;
    notes['node'] = nodeId == client.selectedNodeId;
    notes['online'] = client.node.online;

    // ---------- a Dot in the sandbox, with the real model ----------
    final sourceId = await tester.runAsync(
      () async =>
          '${(await client.rpc('providers.set', {'kind': 'custom', 'name': 'QA model', 'baseUrl': const String.fromEnvironment('QA_PROVIDER_URL'), 'apiKey': const String.fromEnvironment('QA_PROVIDER_KEY')}))['sourceId']}',
    );
    final created = await tester.runAsync(
      () => client.rpc('bots.create', {
        'displayName': 'Sandy',
        // The sandbox keeps its Dots when it pairs again, so a run makes its own.
        'handle': 'sandy${DateTime.now().millisecondsSinceEpoch % 100000}',
        'role': 'Answer in one short sentence.',
        'model': const String.fromEnvironment('QA_PROVIDER_MODEL'),
        'avatar': {'shape': 'dot', 'color': '#2E8BFF'},
        'approvalMode': 'off',
        'sourceId': sourceId,
      }),
    );
    final conversation = '${created!['conversation']['conversationId']}';
    await tester.runAsync(
      () => client.deliveries.enqueue(
        'messages.send',
        {
          'conversationId': conversation,
          'text': 'Which operating system are you running on? One sentence.',
          'clientMsgId': uid(),
        },
        nodeId,
        [],
      ),
    );
    // Answered: a finished reply after the question that names the system
    // the sandbox runs (Ubuntu), which the Dot can only learn from inside it.
    bool replied() {
      final messages = client.node.messages[conversation] ?? [];
      final asked = messages.lastIndexWhere((m) => m.author.type == 'user');
      return asked >= 0 &&
          messages
              .skip(asked + 1)
              .any(
                (m) =>
                    m.author.type != 'user' &&
                    m.kind == 'text' &&
                    // A tool task's own messages stay out of the chat.
                    m.taskRole != 'execution' &&
                    m.status == 'done' &&
                    '${m.content['text']}'.contains('Ubuntu'),
              );
    }

    await show(HomePage(client: client));
    // Messages load once the chat is open.
    final row = find.byKey(ValueKey('conversation-$conversation'));
    await until(() => row.evaluate().isNotEmpty, seconds: 30);
    await tester.tap(row);
    notes['replied'] = await until(replied, seconds: 240);
    await shot('chat', settle: 1500);
    notes['reply'] = (client.node.messages[conversation] ?? [])
        .where(
          (m) =>
              m.author.type != 'user' &&
              m.kind == 'text' &&
              m.taskRole != 'execution',
        )
        .map((m) => '${m.content['text']}')
        .join(' ');

    // ---------- the sandbox stops; settings wakes it ----------
    await tester.runAsync(host.halt);
    notes['wentOffline'] = await until(() => !client.node.online, seconds: 60);
    await show(
      AppPage(
        title: 'Cloud sandboxes',
        body: PageList(children: [SandboxesPanel(client: client)]),
      ),
    );
    await shot('settings-stopped', settle: 2000);
    await tester.tap(find.byKey(ValueKey('sandbox-wake-${record.id}')));
    notes['wokeUp'] = await until(() => client.node.online, seconds: 180);
    await shot('settings-woken', settle: 2000);

    // ---------- a Daytona account that cannot reach nekodot ----------
    client.sandboxes.makeHost = (_, _) => BlockedHost();
    await show(RunLocationPage(client: client));
    await tester.tap(find.byKey(const ValueKey('run-sandbox')));
    await run(const Duration(milliseconds: 600));
    await tester.enterText(
      find.byKey(const ValueKey('sandbox-daytona-key')),
      'tier-1-key',
    );
    await tester.enterText(
      find.byKey(const ValueKey('sandbox-name')),
      'Blocked box',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('sandbox-create')));
    await tester.tap(find.byKey(const ValueKey('sandbox-create')));
    notes['blockedSaid'] = await until(
      () => find.textContaining('Tier 3').evaluate().isNotEmpty,
      seconds: 120,
    );
    await shot('daytona-blocked');
    await tester.tap(find.byKey(const ValueKey('sandbox-discard')));
    notes['blockedForgotten'] = await until(
      () => client.sandboxes.records.length == 1,
      seconds: 30,
    );

    tester.view.reset();
    await tester.pumpWidget(const SizedBox.shrink());
    client.dispose();
    // ignore: avoid_print
    print('TOUR ${jsonEncode(notes)}');
  }, timeout: const Timeout(Duration(minutes: 30)));
}
