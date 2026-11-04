import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/client.dart';
import 'installer.dart';
import 'location.dart';
import 'owned_process.dart';
import 'system.dart';

/// Set on desktop systems that can host a node; null on phones.
LocalRuntime? localRuntime;

enum LocalPhase {
  idle,
  installing,
  pairing,
  starting,
  online,
  offline,
  stopping,
  failed,
}

const localSteps = [...runtimeSteps, 'account', 'pair', 'start'];

class LocalStep {
  final String id;
  String state = 'pending', detail = '';
  LocalStep(this.id);
}

/// Installs, pairs and owns the node that runs on this computer for the signed-in account.
/// The Node itself is the existing product node; this class only prepares and supervises it.
class LocalRuntime extends ChangeNotifier {
  final NekodotClient client;
  LocalRuntime(this.client);

  LocalSupport support = const LocalSupport(null, 'unknown');
  LocalLocation? location;
  LocalPhase phase = LocalPhase.idle;
  String error = '', failedStep = '';
  List<LocalStep> steps = [for (final id in localSteps) LocalStep(id)];
  String? userId, nodeId;
  OwnedProcess? _node;
  RuntimeInstaller? _installer;
  Completer<void>? _online;
  bool _stopping = false;

  bool get running => _node?.running == true;
  bool get busy => const [
    LocalPhase.installing,
    LocalPhase.pairing,
    LocalPhase.starting,
    LocalPhase.stopping,
  ].contains(phase);
  String get _home => location!.account(userId!);
  String get _bundle => joinPath(_home, 'bin', 'nekodot-node.cjs');

  /// True when the local node currently has a run, chain or approval in progress.
  bool get working {
    final data = nodeId == null ? null : client.nodes[nodeId];
    return running &&
        (data?.activities.values.any(
              (a) => a['state'] != null && a['state'] != 'idle',
            ) ??
            false);
  }

  Future<void> initialize() async {
    support = await localSupport();
    if (!support.supported) return;
    location = await LocalLocation.load();
    client.addListener(_follow);
    _follow();
  }

  void _follow() {
    final id = client.token == null
        ? null
        : client.me?['user']?['userId'] as String?;
    if (id != userId) unawaited(_switch(id));
  }

  /// Signing out or switching accounts stops this account's node before the next one loads.
  Future<void> _switch(String? id) async {
    userId = id;
    await stop();
    if (userId != id) return;
    nodeId = null;
    error = '';
    phase = LocalPhase.idle;
    steps = [for (final step in localSteps) LocalStep(step)];
    if (id != null && location != null) {
      nodeId = await _pairedNode();
      if (nodeId != null && await ready()) unawaited(start());
    }
    notifyListeners();
  }

  Future<String?> _pairedNode() async {
    final file = File(joinPath(_home, 'node.json'));
    if (!await file.exists()) return null;
    final value = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (_relay(value['relayUrl'] as String) !=
        _relay(client.origin.toString())) {
      _fail(
        'start',
        'This computer was paired with another Relay: ${value['relayUrl']}',
      );
      return null;
    }
    return value['nodeId'] as String;
  }

  String _relay(String url) => url.replaceAll(RegExp(r'/+$'), '');

  Future<bool> ready() async =>
      location != null &&
      (await location!.completed()).containsAll(runtimeSteps) &&
      await File(location!.launcher).exists() &&
      await File(_bundle).exists();

  void _progress(String step, String state, String detail) {
    final item = steps.firstWhere((s) => s.id == step);
    item.state = state;
    item.detail = detail;
    notifyListeners();
  }

  void _fail(String step, String detail) {
    failedStep = step;
    error = detail;
    phase = LocalPhase.failed;
    if (localSteps.contains(step)) _progress(step, 'failed', detail);
    notifyListeners();
  }

  /// First use and retries: install or resume the runtime, prepare this account, pair the
  /// node with a fresh code (requested last so a long install cannot expire it), then start.
  Future<void> setup(LocalLocation chosen) async {
    if (busy || running || userId == null) return;
    var step = 'check';
    error = '';
    failedStep = '';
    phase = LocalPhase.installing;
    for (final item in steps) {
      if (item.state != 'done') item.state = 'pending';
    }
    notifyListeners();
    try {
      await prepareFolder(chosen.runtime, FolderKind.runtime);
      await prepareFolder(chosen.data, FolderKind.data);
      await chosen.save();
      location = chosen;
      _installer = RuntimeInstaller(
        chosen,
        support.platform!,
        client.transport,
        (id, state, detail) {
          step = id;
          _progress(id, state, detail);
        },
      );
      await _installer!.run();
      step = 'account';
      _progress(step, 'running', '');
      await _prepareAccount();
      _progress(step, 'done', '');
      step = 'pair';
      nodeId = await _pairedNode();
      if (nodeId == null) {
        phase = LocalPhase.pairing;
        _progress(step, 'running', '');
        await _pair();
      }
      _progress(step, 'done', '');
      step = 'start';
      _progress(step, 'running', '');
      _online = Completer<void>();
      await start();
      await _online!.future.timeout(const Duration(minutes: 6));
      _progress(step, 'done', '');
      await client.refreshMe();
      await client.selectNode(nodeId!);
    } on InstallFailure catch (failure) {
      _fail(failure.step, failure.detail);
    } catch (failure) {
      _fail(step, '$failure');
    } finally {
      _installer = null;
    }
  }

  void cancelSetup() => _installer?.cancel();

  Future<void> _prepareAccount() async {
    final hermes = joinPath(_home, 'hermes');
    await Directory(joinPath(_home, 'logs')).create(recursive: true);
    if (!await File(joinPath(hermes, 'config.yaml')).exists()) {
      await Directory(hermes).create(recursive: true);
      await RuntimeInstaller(
        location!,
        support.platform!,
        client.transport,
        (_, state, detail) => _progress('account', 'running', detail),
      ).stage('config', hermes);
    }
    final bundle = File(_bundle);
    if (await bundle.exists()) return;
    await bundle.parent.create(recursive: true);
    final response = await client.transport
        .get(client.url('/downloads/nekodot-node.cjs'))
        .timeout(const Duration(minutes: 2));
    if (response.statusCode != 200) {
      throw InstallFailure(
        'account',
        'Node download failed: HTTP ${response.statusCode}',
      );
    }
    final partial = File('${bundle.path}.part');
    await partial.writeAsBytes(response.bodyBytes);
    await partial.rename(bundle.path);
  }

  Future<void> _pair() async {
    final code =
        (await client.request(
              '/pairing-codes',
              method: 'POST',
              body: {},
            ))['code']
            as String;
    final result = await runOwned(
      location!.nodeExecutable,
      [
        _bundle,
        'pair',
        '--relay',
        _relay(client.origin.toString()),
        '--code',
        code,
        '--name',
        Platform.localHostname,
      ],
      workingDirectory: _home,
      environment: isolatedEnvironment({'NEKODOT_HOME': _home}),
    );
    if (result.code != 0) throw InstallFailure('pair', result.output);
    nodeId = await _pairedNode();
    if (nodeId == null) {
      throw const InstallFailure('pair', 'node.json was not written');
    }
  }

  Future<void> start() async {
    if (running || location == null || userId == null || nodeId == null) return;
    error = '';
    phase = LocalPhase.starting;
    notifyListeners();
    try {
      await _applyUpdateMarkers();
      final port = await _port();
      final log = File(joinPath(_home, 'logs', 'desktop-node.log'))
          .openWrite(mode: FileMode.append);
      final process = _node = await OwnedProcess.start(
        location!.nodeExecutable,
        [_bundle, 'run', '--desktop', '--hermes-launcher', location!.launcher],
        workingDirectory: _home,
        environment: isolatedEnvironment({
          'NEKODOT_HOME': _home,
          'NEKODOT_HERMES_RUNTIME': location!.tools,
          'NEKODOT_HERMES_API_PORT': '$port',
          'HERMES_GATEWAY_LOCK_DIR': joinPath(_home, 'gateway-locks'),
        }),
        log: log,
      );
      process.lines.listen(_status);
      unawaited(
        process.exitCode.then((code) async {
          await log.close();
          if (_node == process) _node = null;
          if (code == 75 && !_stopping) return start();
          if (_stopping || code == 0) {
            phase = LocalPhase.idle;
          } else {
            _fail(
              'start',
              process.tail.where((l) => l.trim().isNotEmpty).lastOrNull ??
                  'exit $code',
            );
          }
          if (!(_online?.isCompleted ?? true)) {
            _online!.completeError(InstallFailure('start', error));
          }
          notifyListeners();
        }),
      );
    } on Object catch (failure) {
      _fail('start', '$failure');
    }
  }

  void _status(String line) {
    if (!line.startsWith('{"desktop"')) return;
    final state =
        (jsonDecode(line) as Map<String, dynamic>)['desktop']
            as Map<String, dynamic>;
    switch (state['state']) {
      case 'online':
        phase = LocalPhase.online;
        if (!(_online?.isCompleted ?? true)) _online!.complete();
      case 'offline':
        phase = LocalPhase.offline;
      case 'stopping':
        phase = LocalPhase.stopping;
      case 'failed':
        _fail('start', '${state['detail'] ?? ''}');
        return;
    }
    notifyListeners();
  }

  /// macOS: asks the system to grant cua-driver Accessibility and Screen Recording. Runs only
  /// here on the computer itself, never on behalf of a remote client. Returns an error or ''.
  Future<String> grantDesktopControl() async {
    if (location == null || userId == null) return '';
    final result = await runOwned(
      location!.launcher,
      ['computer-use', 'permissions', 'grant'],
      workingDirectory: _home,
      environment: isolatedEnvironment({
        'HERMES_HOME': joinPath(_home, 'hermes'),
        'HERMES_RUNTIME_DIR': location!.tools,
      }),
    );
    return result.code == 0 ? '' : result.output;
  }

  /// Graceful stop through the Node's stdin; the owned job reaps anything left after a minute.
  Future<void> stop() async {
    _installer?.cancel();
    final process = _node;
    if (process == null) return;
    _stopping = true;
    phase = LocalPhase.stopping;
    notifyListeners();
    process.write('stop\n', close: true);
    await process.exitCode.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        process.kill();
        return process.exitCode;
      },
    );
    _stopping = false;
    phase = LocalPhase.idle;
    notifyListeners();
  }

  /// The same pending/tried/rejected rollback the server launcher performs for Node updates.
  Future<void> _applyUpdateMarkers() async {
    final bin = joinPath(_home, 'bin');
    File file(String name) => File(joinPath(bin, name));
    if (!await file('update-pending').exists()) return;
    if (!await file('update-tried').exists()) {
      await file('update-tried').writeAsString('');
      return;
    }
    final recycle = Directory(joinPath(bin, 'recycle'));
    await recycle.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    await file('nekodot-node.cjs.previous').rename(_bundle);
    if (await file('update-rejected').exists()) {
      await file('update-rejected')
          .rename(joinPath(recycle.path, 'update-rejected-$stamp'));
    }
    await file('update-pending').rename(file('update-rejected').path);
    await file('update-tried')
        .rename(joinPath(recycle.path, 'update-tried-$stamp'));
  }

  /// Hermes needs three consecutive loopback ports (API, management, webhook).
  Future<int> _port() async {
    final file = File(joinPath(_home, 'hermes-api-port'));
    final saved = await file.exists()
        ? int.tryParse((await file.readAsString()).trim())
        : null;
    for (final candidate in [
      ?saved,
      for (var p = 18642; p <= 18740; p += 3) p,
    ]) {
      if (await _free(candidate) &&
          await _free(candidate + 1) &&
          await _free(candidate + 2)) {
        await file.writeAsString('$candidate');
        return candidate;
      }
    }
    throw const InstallFailure('start', 'No local Hermes port is available');
  }

  Future<bool> _free(int port) async {
    try {
      await (await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      )).close();
      return true;
    } on SocketException {
      return false;
    }
  }
}
