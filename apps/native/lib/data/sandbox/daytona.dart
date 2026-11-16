import 'dart:async';

import 'package:http/http.dart' as http;

import 'host.dart';

/// Daytona, through its REST API (https://www.daytona.io/docs/openapi.json
/// and toolbox-openapi.json). The sandbox is an Ubuntu 24.04 container that
/// never stops on its own; commands run as root through its toolbox.
class DaytonaHost implements SandboxHost {
  static final api = Uri.parse('https://app.daytona.io/api/');
  static const image =
      'FROM ubuntu:24.04\n'
      'RUN apt-get update && apt-get install -y --no-install-recommends '
      'ca-certificates curl git tar xz-utils libatomic1 sudo procps '
      '&& rm -rf /var/lib/apt/lists/*\n';

  final String apiKey;
  final http.Client transport;
  final Duration poll;
  final _toolbox = <String, Uri>{};
  DaytonaHost({
    required this.apiKey,
    http.Client? transport,
    required this.poll,
  }) : transport = transport ?? http.Client();

  @override
  String get provider => 'daytona';

  Map<String, String> get _auth => {'Authorization': 'Bearer $apiKey'};
  Future<dynamic> _call(String method, String path, [Object? body]) =>
      providerRequest(transport, method, api.resolve(path), _auth, body);

  @override
  Future<String> create(String name, SandboxSize size) async {
    final sandbox = await _call('POST', 'sandbox', {
      'name': name,
      'buildInfo': {'dockerfileContent': image},
      'cpu': size.cpu,
      'memory': size.memoryGb,
      'disk': 10,
      // A Dot lives here: it must not stop when nobody talks to it.
      'autoStopInterval': 0,
      'labels': {'app': 'nekodot'},
    });
    final id = '${(sandbox as Map)['id']}';
    // Building the image the first time takes a few minutes.
    await _until(id, const Duration(minutes: 20));
    return id;
  }

  Future<Map> _sandbox(String id) async =>
      await _call('GET', 'sandbox/$id') as Map;

  @override
  Future<SandboxState> state(String id) async {
    try {
      return _state(await _sandbox(id));
    } on SandboxError catch (error) {
      if (error.status == 404) return SandboxState.gone;
      rethrow;
    }
  }

  SandboxState _state(Map sandbox) => switch ('${sandbox['state']}') {
    'started' => SandboxState.running,
    'stopped' ||
    'stopping' ||
    'archived' ||
    'archiving' ||
    'paused' ||
    'pausing' => SandboxState.stopped,
    'destroyed' || 'destroying' => SandboxState.gone,
    'error' || 'build_failed' => SandboxState.failed,
    _ => SandboxState.starting,
  };

  /// Waits until the sandbox has started; a failed build or start says why.
  Future<void> _until(String id, Duration limit) async {
    final end = DateTime.now().add(limit);
    while (true) {
      final sandbox = await _sandbox(id);
      switch (_state(sandbox)) {
        case SandboxState.running:
          return;
        case SandboxState.failed:
          throw SandboxError('${sandbox['errorReason'] ?? sandbox['state']}');
        case SandboxState.gone:
          throw SandboxError('The sandbox no longer exists', 404);
        case SandboxState.stopped || SandboxState.starting:
          break;
      }
      if (DateTime.now().isAfter(end)) {
        throw SandboxError('The sandbox did not start in time');
      }
      await Future<void>.delayed(poll);
    }
  }

  @override
  Future<void> wake(String id) async {
    if (await state(id) == SandboxState.stopped) {
      await _call('POST', 'sandbox/$id/start');
    }
    await _until(id, const Duration(minutes: 5));
  }

  /// Where this sandbox's toolbox answers: its proxy URL plus its id.
  Future<Uri> _tools(String id) async {
    final known = _toolbox[id];
    if (known != null) return known;
    final proxy = '${(await _sandbox(id))['toolboxProxyUrl']}';
    return _toolbox[id] = Uri.parse(
      '${proxy.endsWith('/') ? proxy : '$proxy/'}$id/',
    );
  }

  @override
  Future<CommandResult> exec(String id, String script) async {
    final result = await providerRequest(
      transport,
      'POST',
      (await _tools(id)).resolve('process/execute'),
      _auth,
      {'command': 'bash -c ${shellQuote(script)}', 'timeout': 120},
    ) as Map;
    return CommandResult(
      (result['exitCode'] as num?)?.toInt() ?? 0,
      '${result['result'] ?? ''}',
    );
  }

  @override
  Future<void> launch(String id, String script) async {
    final tools = await _tools(id);
    final session = 'nekodot-${DateTime.now().millisecondsSinceEpoch}';
    await providerRequest(
      transport,
      'POST',
      tools.resolve('process/session'),
      _auth,
      {'sessionId': session},
    );
    await providerRequest(
      transport,
      'POST',
      tools.resolve('process/session/$session/exec'),
      _auth,
      {'command': 'bash -c ${shellQuote(script)}', 'runAsync': true},
    );
  }

  @override
  Future<void> delete(String id) async {
    try {
      await _call('DELETE', 'sandbox/$id');
    } on SandboxError catch (error) {
      if (error.status != 404) rethrow;
    }
  }
}
