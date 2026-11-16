import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'account.dart';
import 'json.dart';
import 'node_data.dart';
import 'sandbox/host.dart';

/// A sandbox this device made for a computer: which provider holds it, its id
/// there, the credentials to manage it, and the node that runs in it.
class SandboxRecord {
  final String provider, id, name;
  final Map<String, String> credentials;
  final String? nodeId;
  const SandboxRecord({
    required this.provider,
    required this.id,
    required this.name,
    required this.credentials,
    this.nodeId,
  });
  SandboxRecord withNode(String node) => SandboxRecord(
    provider: provider,
    id: id,
    name: name,
    credentials: credentials,
    nodeId: node,
  );
  Json toJson() => {
    'provider': provider,
    'id': id,
    'name': name,
    'credentials': credentials,
    'nodeId': ?nodeId,
  };
  factory SandboxRecord.fromJson(Json json) => SandboxRecord(
    provider: '${json['provider']}',
    id: '${json['id']}',
    name: '${json['name']}',
    credentials: Map<String, String>.from(json['credentials'] as Map),
    nodeId: json['nodeId'] as String?,
  );
}

/// Where the installer keeps its output and, once it ends, its exit code.
const _installDir = r'$HOME/.nekodot-install';

/// Starts the node again in a sandbox that was stopped (install.sh --sandbox).
const startNode = r'"$HOME/.nekodot/bin/nekodot-start"';

/// The sandboxes this device made, for the signed-in account on this Relay.
/// Records, keys included, stay in the device's secure storage and nowhere
/// else; one entry each, since some stores cap an entry's size.
class SandboxStore extends ChangeNotifier {
  final AccountSession account;

  /// Makes the host for a provider and its credentials: the providers' own
  /// APIs, or a stand-in an acceptance run puts here.
  SandboxHost Function(String provider, Map<String, String> credentials)
  makeHost;
  SandboxStore(
    this.account, {
    SandboxHost Function(String, Map<String, String>)? makeHost,
  }) : makeHost = makeHost ?? ((p, c) => sandboxHost(p, c));

  SandboxHost hostFor(SandboxRecord record) =>
      makeHost(record.provider, record.credentials);

  List<SandboxRecord> records = const [];
  String _user = '';
  String get _index => 'sandboxes:${account.origin}:$_user';
  String _key(String id) => 'sandbox:${account.origin}:$_user:$id';

  /// Reads the records of [user]; another account's are never shown.
  Future<void> load(String user) async {
    _user = user;
    final ids = jsonDecode(await account.vault.read(key: _index) ?? '[]');
    final loaded = <SandboxRecord>[];
    for (final id in ids as List) {
      final value = await account.vault.read(key: _key('$id'));
      if (value != null) {
        loaded.add(SandboxRecord.fromJson(object(jsonDecode(value))));
      }
    }
    records = loaded;
    notifyListeners();
  }

  Future<void> save(SandboxRecord record) async {
    await account.vault.write(
      key: _key(record.id),
      value: jsonEncode(record.toJson()),
    );
    records = [...records.where((r) => r.id != record.id), record];
    await _writeIndex();
    notifyListeners();
  }

  Future<void> forget(SandboxRecord record) async {
    await account.vault.delete(key: _key(record.id));
    records = records.where((r) => r.id != record.id).toList();
    await _writeIndex();
    notifyListeners();
  }

  Future<void> _writeIndex() => account.vault.write(
    key: _index,
    value: jsonEncode([for (final r in records) r.id]),
  );

  /// Signed out: nothing is shown or kept running until the next sign-in.
  void clear() {
    _keeper?.cancel();
    _user = '';
    records = const [];
    notifyListeners();
  }

  SandboxRecord? forNode(String nodeId) =>
      records.where((r) => r.nodeId == nodeId).firstOrNull;

  /// Starts the sandbox if it stopped, then the node in it.
  Future<void> wake(SandboxRecord record) async {
    final host = hostFor(record);
    await host.wake(record.id);
    final started = await host.exec(record.id, startNode);
    if (started.exitCode != 0) throw SandboxError(started.output.trim());
  }

  /// Deletes the sandbox at its provider and the computer from the account.
  Future<void> remove(SandboxRecord record) async {
    await hostFor(record).delete(record.id);
    if (record.nodeId != null) {
      await account.request('/nodes/${record.nodeId}', method: 'DELETE');
    }
    await forget(record);
  }

  // ---------- keeping them running ----------
  Timer? _keeper;
  final _offlineSince = <String, DateTime>{}, _woken = <String, DateTime>{};

  /// Every minute: a computer in one of these sandboxes that has been offline
  /// for two minutes is woken, at most once in ten minutes. On Vercel this is
  /// how a sandbox comes back after its session reached the plan's limit.
  void keep(Map<String, NodeData> nodes) {
    _keeper?.cancel();
    _keeper = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(check(nodes, DateTime.now())),
    );
  }

  @visibleForTesting
  Future<void> check(Map<String, NodeData> nodes, DateTime now) async {
    for (final record in records) {
      final node = record.nodeId == null ? null : nodes[record.nodeId];
      if (node == null) continue;
      if (node.online) {
        _offlineSince.remove(record.nodeId);
        continue;
      }
      final since = _offlineSince.putIfAbsent(record.nodeId!, () => now);
      final last = _woken[record.nodeId];
      if (now.difference(since) < const Duration(minutes: 2) ||
          (last != null &&
              now.difference(last) < const Duration(minutes: 10))) {
        continue;
      }
      _woken[record.nodeId!] = now;
      try {
        await wake(record);
      } catch (error) {
        debugPrint('Waking sandbox ${record.name} failed: $error');
      }
    }
  }

  @override
  void dispose() {
    _keeper?.cancel();
    super.dispose();
  }
}

/// The steps of putting a new computer into a sandbox.
enum SandboxStep { create, install, connect, done, failed }

/// Makes a sandbox, runs the Relay's installer in it in sandbox mode, and
/// waits for the new computer to come online. The record is saved as soon as
/// the sandbox exists, so a failed installation can still be deleted.
class SandboxInstall extends ChangeNotifier {
  final SandboxStore store;
  final SandboxHost host;
  final Duration poll, extendEvery;
  SandboxInstall(
    this.store,
    this.host, {
    this.poll = const Duration(seconds: 5),
    this.extendEvery = const Duration(minutes: 20),
  });

  SandboxStep step = SandboxStep.create;

  /// The step that was running when the installation failed.
  SandboxStep failedAt = SandboxStep.create;
  String error = '', log = '';
  SandboxRecord? record;
  bool _stopped = false;

  void _to(SandboxStep next) {
    step = next;
    notifyListeners();
  }

  /// A name for the computer, safe inside a shell's single quotes.
  static String? validName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 40) return null;
    if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(trimmed)) return null;
    return trimmed;
  }

  /// The sandbox's name at its provider: letters, digits and dashes.
  static String sandboxName() =>
      'nekodot-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

  Future<void> run({
    required String name,
    required SandboxSize size,
    required Map<String, String> credentials,
  }) async {
    final account = store.account;
    final before = {
      for (final n in objects(account.me?['nodes'])) '${n['nodeId']}',
    };
    try {
      _to(SandboxStep.create);
      final id = await host.create(sandboxName(), size);
      record = SandboxRecord(
        provider: host.provider,
        id: id,
        name: name,
        credentials: credentials,
      );
      await store.save(record!);

      _to(SandboxStep.install);
      final code = await account.request('/pairing-codes', method: 'POST');
      final command = '${code['sandboxCommand']} --name ${shellQuote(name)}';
      await host.launch(
        id,
        // pipefail: a Relay that cannot be reached fails the download, not
        // an empty bash after it.
        'set -o pipefail; mkdir -p "$_installDir" && rm -f "$_installDir/exit"; '
        // The installer is fetched with curl, which a bare image may lack.
        '{ command -v curl > /dev/null || { apt-get update && '
        'apt-get install -y --no-install-recommends ca-certificates curl; }; } '
        '> "$_installDir/log" 2>&1; '
        '( $command ) >> "$_installDir/log" 2>&1; '
        'echo \$? > "$_installDir/exit"',
      );
      final exit = await _installerExit(id, '${code['code']}');
      if (exit != 0) {
        throw SandboxError(_installFailure());
      }

      _to(SandboxStep.connect);
      final node = await _newNode(before);
      record = record!.withNode(node);
      await store.save(record!);
      _to(SandboxStep.done);
    } catch (e) {
      error = switch (e) {
        SandboxError(status: 401 || 403) => 'unauthorized',
        SandboxError(:final message) => message,
        _ => '$e',
      };
      failedAt = step;
      _to(SandboxStep.failed);
    }
  }

  /// Reads the installer's progress until it has ended; returns its exit code.
  /// The pairing code lasts 30 minutes and the installer pairs last, so a slow
  /// first installation keeps it alive every 20.
  Future<int> _installerExit(String id, String pairingCode) async {
    final end = DateTime.now().add(const Duration(minutes: 45));
    var extended = DateTime.now();
    while (!_stopped && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(poll);
      if (DateTime.now().difference(extended) >= extendEvery) {
        await store.account.request(
          '/pairing-codes/$pairingCode/extend',
          method: 'POST',
        );
        extended = DateTime.now();
      }
      final read = await host.exec(
        id,
        'cat "$_installDir/exit" 2>/dev/null; echo "---"; '
        'tail -n 15 "$_installDir/log" 2>/dev/null',
      );
      final parts = read.output.split('---');
      log = parts.length > 1 ? parts.sublist(1).join('---').trim() : '';
      notifyListeners();
      final exit = int.tryParse(parts.first.trim());
      if (exit != null) return exit;
    }
    throw SandboxError(_stopped ? 'stopped' : 'install_timeout');
  }

  /// Why the installer failed, from its last lines. A Daytona sandbox that
  /// cannot reach the Relay at all is most likely held back by its account
  /// tier, which only lets essential services through.
  String _installFailure() {
    final relay = store.account.origin.host;
    if (host.provider == 'daytona' &&
        log.contains('curl:') &&
        (log.contains(relay) || !log.contains('First installation'))) {
      return 'daytona_network';
    }
    return log.split('\n').where((l) => l.trim().isNotEmpty).lastOrNull ??
        'install_failed';
  }

  /// The id of the computer that came online since [before], within 5 minutes.
  Future<String> _newNode(Set<String> before) async {
    final end = DateTime.now().add(const Duration(minutes: 5));
    while (!_stopped && DateTime.now().isBefore(end)) {
      final me = await store.account.request('/me');
      store.account.me = me;
      final added = objects(me['nodes'])
          .where(
            (n) => !before.contains('${n['nodeId']}') && n['online'] == true,
          )
          .firstOrNull;
      if (added != null) return '${added['nodeId']}';
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    throw SandboxError('not_online');
  }

  void stop() => _stopped = true;
}
