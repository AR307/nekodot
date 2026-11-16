import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'host.dart';

/// Vercel Sandbox, through its REST API (vercel.com/docs/rest-api/sandboxes).
/// A sandbox runs in sessions of at most the plan's limit; when one ends the
/// files are kept and a new session starts on the next request, so commands
/// always go through [_session], which resumes it. Commands run as root.
class VercelHost implements SandboxHost {
  static final api = Uri.parse('https://api.vercel.com/');

  final String token, teamId, projectId;

  /// How long a session lasts: the plan's limit (24 hours on Pro, 45 minutes
  /// on Hobby).
  final Duration session;
  final http.Client transport;
  final Duration poll;
  VercelHost({
    required this.token,
    required this.teamId,
    required this.projectId,
    required this.session,
    http.Client? transport,
    required this.poll,
  }) : transport = transport ?? http.Client();

  @override
  String get provider => 'vercel';

  Map<String, String> get _auth => {'Authorization': 'Bearer $token'};
  Uri _url(String path, [Map<String, String> query = const {}]) =>
      api.resolve(path).replace(queryParameters: {'teamId': teamId, ...query});
  Future<dynamic> _call(
    String method,
    String path, {
    Map<String, String> query = const {},
    Object? body,
  }) => providerRequest(transport, method, _url(path, query), _auth, body);

  @override
  Future<String> create(String name, SandboxSize size) async {
    final created = await _call(
      'POST',
      'v4/sandboxes',
      body: {
        'name': name,
        'projectId': projectId,
        'image': 'ubuntu:latest',
        'resources': {'vcpus': size.cpu, 'memory': size.memoryGb * 1024},
        'timeout': session.inMilliseconds,
        'persistent': true,
      },
    ) as Map;
    final id = '${(created['sandbox'] as Map)['name']}';
    await _session(id);
    return id;
  }

  Future<Map> _sandbox(String id, {bool resume = false}) async => await _call(
    'GET',
    'v2/sandboxes/$id',
    query: {'projectId': projectId, if (resume) 'resume': 'true'},
  ) as Map;

  @override
  Future<SandboxState> state(String id) async {
    try {
      final found = await _sandbox(id);
      final sandbox = found['sandbox'] as Map;
      final current = found['session'] as Map?;
      if (sandbox['status'] != 'running') return SandboxState.stopped;
      return switch ('${current?['status']}') {
        'running' => SandboxState.running,
        'failed' || 'aborted' => SandboxState.failed,
        'stopped' || 'stopping' || 'snapshotting' => SandboxState.stopped,
        _ => SandboxState.starting,
      };
    } on SandboxError catch (error) {
      if (error.status == 404) return SandboxState.gone;
      rethrow;
    }
  }

  /// The running session, resuming the sandbox from its files if it stopped.
  Future<String> _session(String id) async {
    final end = DateTime.now().add(const Duration(minutes: 5));
    while (true) {
      final current = (await _sandbox(id, resume: true))['session'] as Map;
      switch ('${current['status']}') {
        case 'running':
          return '${current['id']}';
        case 'failed' || 'aborted':
          throw SandboxError('The sandbox session ${current['status']}');
      }
      if (DateTime.now().isAfter(end)) {
        throw SandboxError('The sandbox did not start in time');
      }
      await Future<void>.delayed(poll);
    }
  }

  @override
  Future<void> wake(String id) => _session(id);

  Future<String> _start(
    String session,
    String script, {
    Duration? timeout,
  }) async {
    final started = await _call(
      'POST',
      'v2/sandboxes/sessions/$session/cmd',
      body: {
        'command': 'bash',
        'args': ['-c', script],
        'sudo': true,
        'timeout': ?timeout?.inMilliseconds,
      },
    ) as Map;
    return '${(started['command'] as Map)['id']}';
  }

  @override
  Future<CommandResult> exec(String id, String script) async {
    final session = await _session(id);
    final command = await _start(
      session,
      script,
      timeout: const Duration(minutes: 2),
    );
    final finished = await _call(
      'GET',
      'v2/sandboxes/sessions/$session/cmd/$command',
      query: {'wait': 'true'},
    ) as Map;
    final exitCode = ((finished['command'] as Map)['exitCode'] as num).toInt();
    final logs = await transport
        .get(
          _url('v2/sandboxes/sessions/$session/cmd/$command/logs'),
          headers: _auth,
        )
        .timeout(const Duration(seconds: 60));
    final output = StringBuffer();
    // NDJSON names no charset, and http would read it as Latin-1.
    for (final line in const LineSplitter().convert(
      utf8.decode(logs.bodyBytes),
    )) {
      if (line.trim().isEmpty) continue;
      final entry = jsonDecode(line) as Map;
      if (entry['stream'] == 'stdout' || entry['stream'] == 'stderr') {
        output.write(entry['data']);
      }
    }
    return CommandResult(exitCode, '$output');
  }

  @override
  Future<void> launch(String id, String script) async {
    // Long enough for a first installation; the node it starts runs on in
    // the background after the script itself has ended.
    await _start(await _session(id), script, timeout: const Duration(hours: 1));
  }

  @override
  Future<void> delete(String id) async {
    try {
      await _call(
        'DELETE',
        'v2/sandboxes/$id',
        query: {'projectId': projectId},
      );
    } on SandboxError catch (error) {
      if (error.status != 404) rethrow;
    }
  }
}
