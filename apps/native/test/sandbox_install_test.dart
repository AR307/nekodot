import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nekodot_native/data/account.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/data/node_data.dart';
import 'package:nekodot_native/data/sandbox/host.dart';
import 'package:nekodot_native/data/sandboxes.dart';
import 'package:nekodot_native/features/local_setup.dart';
import 'package:nekodot_native/features/sandbox_setup.dart';
import 'package:nekodot_native/ui/design.dart';

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

/// A sandbox in memory: commands it is given, and what the installer leaves.
class FakeHost implements SandboxHost {
  @override
  final String provider;
  FakeHost(this.provider);
  final launched = <String>[];
  final ran = <String>[];
  String? exitFile;
  String log = 'First installation can take several minutes.';
  int woken = 0, deleted = 0;
  Object? refuse;

  @override
  Future<String> create(String name, SandboxSize size) async {
    if (refuse != null) throw refuse!;
    return 'sb-$name';
  }

  @override
  Future<CommandResult> exec(String id, String script) async {
    ran.add(script);
    if (script.contains('nekodot-start')) return const CommandResult(0, '');
    return CommandResult(0, '${exitFile ?? ''}\n---\n$log\n');
  }

  @override
  Future<void> launch(String id, String script) async => launched.add(script);
  @override
  Future<SandboxState> state(String id) async => SandboxState.running;
  @override
  Future<void> wake(String id) async => woken++;
  @override
  Future<void> delete(String id) async => deleted++;
}

/// A Relay that hands out a pairing code and, once asked enough times, shows
/// the new computer online.
class FakeRelay {
  final requests = <http.Request>[];
  bool online = false;
  late final account =
      AccountSession(
          server: 'https://api.example.test',
          vault: MemoryVault(),
          transport: MockClient((request) async {
            requests.add(request);
            final path = request.url.path;
            Object body = {};
            if (path == '/api/pairing-codes') {
              body = {
                'code': 'ABCD-2345',
                'sandboxCommand': "curl -fsSL 'https://api.example.test/install.sh' | bash -s -- --pair ABCD-2345 --sandbox",
              };
            } else if (path == '/api/me') {
              body = {
                'user': {'userId': 'u1'},
                'nodes': [
                  {'nodeId': 'old', 'online': true},
                  if (online) {'nodeId': 'new', 'online': true},
                ],
              };
            }
            return http.Response(
              jsonEncode(body),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        )
        ..me = {
          'nodes': [
            {'nodeId': 'old', 'online': true},
          ],
        };
}

void main() {
  test('puts a computer into a sandbox and keeps its record and key', () async {
    final relay = FakeRelay();
    final store = SandboxStore(relay.account);
    await store.load('u1');
    final host = FakeHost('daytona');
    final install = SandboxInstall(
      store,
      host,
      poll: Duration.zero,
      extendEvery: Duration.zero,
    );
    final steps = <SandboxStep>[];
    install.addListener(() {
      if (steps.lastOrNull != install.step) steps.add(install.step);
      // The installer ends, then the Relay sees the computer.
      if (host.ran.length == 2) host.exitFile = '0';
      if (install.step == SandboxStep.connect) relay.online = true;
    });
    await install.run(
      name: "Dot's box",
      size: SandboxSize.standard,
      credentials: {'apiKey': 'dt-key'},
    );
    expect(install.error, '');
    expect(steps, [
      SandboxStep.create,
      SandboxStep.install,
      SandboxStep.connect,
      SandboxStep.done,
    ]);
    final script = host.launched.single;
    expect(script, startsWith('set -o pipefail;'));
    expect(script, contains("--sandbox --name 'Dot'\\''s box'"));
    expect(install.record!.nodeId, 'new');
    // While the installer runs, the pairing code is kept alive.
    expect(
      relay.requests.map((r) => r.url.path),
      contains('/api/pairing-codes/ABCD-2345/extend'),
    );

    // Saved on this device, with its key, for this account only.
    final again = SandboxStore(relay.account);
    await again.load('u1');
    expect(again.records.single.credentials, {'apiKey': 'dt-key'});
    expect(again.records.single.nodeId, 'new');
    await again.load('someone-else');
    expect(again.records, isEmpty);
  });

  test('a failed installation says why, and a blocked Daytona says it is the tier', () async {
    Future<SandboxInstall> fail(
      String provider,
      String log, {
      Object? refuse,
    }) async {
      final relay = FakeRelay();
      final store = SandboxStore(relay.account);
      await store.load('u1');
      final host = FakeHost(provider)
        ..exitFile = '6'
        ..log = log
        ..refuse = refuse;
      final install = SandboxInstall(store, host, poll: Duration.zero);
      await install.run(
        name: 'Box',
        size: SandboxSize.standard,
        credentials: {'apiKey': 'k'},
      );
      expect(install.step, SandboxStep.failed);
      return install;
    }

    expect(
      (await fail(
        'daytona',
        "curl: (56) CONNECT tunnel failed, response 403",
      )).error,
      'daytona_network',
    );
    expect(
      (await fail(
        'vercel',
        'First installation can take several minutes.\nNo space left on device',
      )).error,
      'No space left on device',
    );
    final refused = await fail(
      'daytona',
      '',
      refuse: SandboxError('Invalid API key', 401),
    );
    expect(refused.error, 'unauthorized');
    expect(refused.record, isNull);
  });

  test('wakes a computer that has been offline for two minutes, not more often than every ten', () async {
    final relay = FakeRelay();
    final host = FakeHost('vercel');
    final store = SandboxStore(relay.account, makeHost: (_, _) => host);
    await store.load('u1');
    await store.save(
      const SandboxRecord(
        provider: 'vercel',
        id: 'nekodot-a',
        name: 'Box',
        credentials: {},
        nodeId: 'n1',
      ),
    );
    final nodes = {'n1': NodeData()..online = false};
    final start = DateTime(2026, 11, 16, 12);
    await store.check(nodes, start);
    await store.check(nodes, start.add(const Duration(minutes: 1)));
    expect(host.woken, 0);
    await store.check(nodes, start.add(const Duration(minutes: 2)));
    expect(host.woken, 1);
    expect(host.ran.last, startNode);
    await store.check(nodes, start.add(const Duration(minutes: 5)));
    expect(host.woken, 1);
    await store.check(nodes, start.add(const Duration(minutes: 12)));
    expect(host.woken, 2);
    nodes['n1']!.online = true;
    await store.check(nodes, start.add(const Duration(minutes: 30)));
    expect(host.woken, 2);
  });

  testWidgets('a phone offers a server or a cloud sandbox', (tester) async {
    final client = NekodotClient(
      transport: MockClient((_) async => http.Response('{}', 200)),
      vault: MemoryVault(),
    );
    addTearDown(client.dispose);
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: RunLocationPage(client: client),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('run-here')), findsNothing);
    expect(find.byKey(const ValueKey('connect-server')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('run-sandbox')));
    await tester.pumpAndSettle();
    expect(find.byType(SandboxSetupPage), findsOneWidget);
    // Nothing is made until every field is filled.
    await tester.ensureVisible(find.byKey(const ValueKey('sandbox-create')));
    await tester.tap(find.byKey(const ValueKey('sandbox-create')));
    await tester.pumpAndSettle();
    expect(find.text('请填写完整'), findsOneWidget);
    await tester.tap(find.text('Vercel Sandbox'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sandbox-vercel-team')), findsOneWidget);
    expect(find.byKey(const ValueKey('sandbox-daytona-key')), findsNothing);
  });
}
