import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nekodot_native/data/sandbox/host.dart';

/// A provider that answers from a script of responses, keyed by method and
/// path, and keeps every request it got.
class Provider {
  final requests = <http.Request>[];
  final answers = <String, List<Object>>{};
  void on(String method, String path, Object body, {int status = 200}) =>
      answers.putIfAbsent('$method $path', () => []).add([status, body]);
  late final client = MockClient((request) async {
    requests.add(request);
    final queue = answers['${request.method} ${request.url.path}'];
    if (queue == null || queue.isEmpty) {
      return http.Response('{"error":{"message":"unexpected"}}', 500);
    }
    final [status as int, body] =
        (queue.length > 1 ? queue.removeAt(0) : queue.first) as List;
    // A string is a log stream, which says nothing about its charset.
    return http.Response.bytes(
      utf8.encode(body is String ? body : jsonEncode(body)),
      status,
      headers: {
        'content-type': body is String
            ? 'application/x-ndjson'
            : 'application/json',
      },
    );
  });
  Map<String, dynamic> body(String method, String path) => jsonDecode(
    requests.lastWhere((r) => r.method == method && r.url.path == path).body,
  ) as Map<String, dynamic>;
}

void main() {
  group('Daytona', () {
    late Provider daytona;
    late SandboxHost host;
    setUp(() {
      daytona = Provider();
      host = sandboxHost(
        'daytona',
        {'apiKey': 'dt-key'},
        transport: daytona.client,
        poll: Duration.zero,
      );
    });

    test('makes an Ubuntu sandbox that never stops and waits for it', () async {
      daytona.on('POST', '/api/sandbox', {
        'id': 'sb1',
        'state': 'pending_build',
      });
      daytona.on('GET', '/api/sandbox/sb1', {
        'id': 'sb1',
        'state': 'building_snapshot',
      });
      daytona.on('GET', '/api/sandbox/sb1', {
        'id': 'sb1',
        'state': 'started',
        'toolboxProxyUrl': 'https://proxy.example.test/toolbox',
      });
      expect(await host.create('nekodot-a', SandboxSize.large), 'sb1');
      final sent = daytona.body('POST', '/api/sandbox');
      expect(sent['autoStopInterval'], 0);
      expect(sent['cpu'], 4);
      expect(sent['memory'], 8);
      expect(sent['disk'], 10);
      expect(
        sent['buildInfo']['dockerfileContent'],
        startsWith('FROM ubuntu:24.04'),
      );
      expect(daytona.requests.first.headers['Authorization'], 'Bearer dt-key');
    });

    test('a failed build says why', () async {
      daytona.on('POST', '/api/sandbox', {'id': 'sb1'});
      daytona.on('GET', '/api/sandbox/sb1', {
        'id': 'sb1',
        'state': 'build_failed',
        'errorReason': 'image not found',
      });
      await expectLater(
        host.create('nekodot-a', SandboxSize.standard),
        throwsA(
          isA<SandboxError>().having(
            (e) => e.message,
            'message',
            'image not found',
          ),
        ),
      );
    });

    test('runs short commands through the toolbox', () async {
      daytona.on('GET', '/api/sandbox/sb1', {
        'id': 'sb1',
        'state': 'started',
        'toolboxProxyUrl': 'https://proxy.example.test/toolbox',
      });
      daytona.on('POST', '/toolbox/sb1/process/execute', {
        'exitCode': 3,
        'result': 'out',
      });
      final ran = await host.exec('sb1', "echo 'hi'");
      expect(ran.exitCode, 3);
      expect(ran.output, 'out');
      expect(
        daytona.body('POST', '/toolbox/sb1/process/execute')['command'],
        r"bash -c 'echo '\''hi'\'''",
      );
      expect(daytona.requests.last.url.host, 'proxy.example.test');
    });

    test('starts a background command in its own session', () async {
      final seen = <http.Request>[];
      final background = sandboxHost(
        'daytona',
        {'apiKey': 'dt-key'},
        transport: MockClient((request) async {
          seen.add(request);
          final path = request.url.path;
          if (path == '/api/sandbox/sb1') {
            return http.Response(
              '{"id":"sb1","state":"started","toolboxProxyUrl":"https://proxy.example.test/toolbox"}',
              200,
            );
          }
          if (path.endsWith('/exec')) {
            return http.Response('{"cmdId":"c1"}', 202);
          }
          return http.Response('', 201);
        }),
      );
      await background.launch('sb1', 'sleep 1');
      final session = jsonDecode(seen[1].body)['sessionId'] as String;
      expect(seen[1].url.path, '/toolbox/sb1/process/session');
      expect(seen[2].url.path, '/toolbox/sb1/process/session/$session/exec');
      expect(jsonDecode(seen[2].body), {
        'command': "bash -c 'sleep 1'",
        'runAsync': true,
      });
    });

    test('wakes a stopped sandbox and forgets one already gone', () async {
      daytona.on('GET', '/api/sandbox/sb1', {'id': 'sb1', 'state': 'stopped'});
      daytona.on('GET', '/api/sandbox/sb1', {'id': 'sb1', 'state': 'starting'});
      daytona.on('GET', '/api/sandbox/sb1', {'id': 'sb1', 'state': 'started'});
      daytona.on('POST', '/api/sandbox/sb1/start', {});
      await host.wake('sb1');
      expect(
        daytona.requests.map((r) => '${r.method} ${r.url.path}'),
        contains('POST /api/sandbox/sb1/start'),
      );
      daytona.on('DELETE', '/api/sandbox/sb2', {
        'error': {'message': 'gone'},
      }, status: 404);
      await host.delete('sb2');
      daytona.on('GET', '/api/sandbox/sb3', {
        'message': 'not found',
      }, status: 404);
      expect(await host.state('sb3'), SandboxState.gone);
    });

    test('a refused key surfaces as 401', () async {
      daytona.on('POST', '/api/sandbox', {
        'message': 'Invalid API key',
      }, status: 401);
      await expectLater(
        host.create('nekodot-a', SandboxSize.standard),
        throwsA(
          isA<SandboxError>()
              .having((e) => e.status, 'status', 401)
              .having((e) => e.message, 'message', 'Invalid API key'),
        ),
      );
    });
  });

  group('Vercel Sandbox', () {
    late Provider vercel;
    late SandboxHost host;
    setUp(() {
      vercel = Provider();
      host = sandboxHost(
        'vercel',
        {
          'token': 'vc-token',
          'teamId': 'team_1',
          'projectId': 'prj_1',
          'sessionMinutes': '1440',
        },
        transport: vercel.client,
        poll: Duration.zero,
      );
    });

    Map<String, Object> sandbox(
      String status,
      String session, {
      String id = 'ses_1',
    }) => {
      'sandbox': {'name': 'nekodot-a', 'status': status},
      'session': {'id': id, 'status': session},
      'resumed': false,
    };

    test(
      'makes a persistent Ubuntu sandbox for the plan\'s session length',
      () async {
        vercel.on('POST', '/v4/sandboxes', sandbox('running', 'pending'));
        vercel.on(
          'GET',
          '/v2/sandboxes/nekodot-a',
          sandbox('running', 'pending'),
        );
        vercel.on(
          'GET',
          '/v2/sandboxes/nekodot-a',
          sandbox('running', 'running'),
        );
        expect(
          await host.create('nekodot-a', SandboxSize.standard),
          'nekodot-a',
        );
        final sent = vercel.body('POST', '/v4/sandboxes');
        expect(sent['timeout'], 24 * 60 * 60 * 1000);
        expect(sent['persistent'], true);
        expect(sent['projectId'], 'prj_1');
        expect(sent['resources'], {'vcpus': 2, 'memory': 4096});
        final create = vercel.requests.first;
        expect(create.url.queryParameters['teamId'], 'team_1');
        expect(create.headers['Authorization'], 'Bearer vc-token');
        final get = vercel.requests.last;
        expect(get.url.queryParameters, containsPair('resume', 'true'));
        expect(get.url.queryParameters, containsPair('projectId', 'prj_1'));
      },
    );

    test(
      'runs a command as root in the current session and reads its output',
      () async {
        vercel.on(
          'GET',
          '/v2/sandboxes/nekodot-a',
          sandbox('running', 'running', id: 'ses_2'),
        );
        vercel.on('POST', '/v2/sandboxes/sessions/ses_2/cmd', {
          'command': {'id': 'cmd_1', 'exitCode': null},
        });
        vercel.on('GET', '/v2/sandboxes/sessions/ses_2/cmd/cmd_1', {
          'command': {'id': 'cmd_1', 'exitCode': 0},
        });
        vercel.on(
          'GET',
          '/v2/sandboxes/sessions/ses_2/cmd/cmd_1/logs',
          '{"stream":"stdout","data":"0\\n"}\n{"stream":"stderr","data":"✓ venv · ok\\n"}\n',
        );
        final ran = await host.exec('nekodot-a', 'cat file');
        expect(ran.exitCode, 0);
        expect(ran.output, '0\n✓ venv · ok\n');
        final sent = vercel.body('POST', '/v2/sandboxes/sessions/ses_2/cmd');
        expect(sent['command'], 'bash');
        expect(sent['args'], ['-c', 'cat file']);
        expect(sent['sudo'], true);
        final wait = vercel.requests.firstWhere(
          (r) => r.url.path == '/v2/sandboxes/sessions/ses_2/cmd/cmd_1',
        );
        expect(wait.url.queryParameters['wait'], 'true');
      },
    );

    test(
      'a stopped sandbox reads as stopped and comes back when woken',
      () async {
        vercel.on(
          'GET',
          '/v2/sandboxes/nekodot-a',
          sandbox('stopped', 'stopped'),
        );
        expect(await host.state('nekodot-a'), SandboxState.stopped);
        vercel.answers.clear();
        vercel.on(
          'GET',
          '/v2/sandboxes/nekodot-a',
          sandbox('running', 'running', id: 'ses_3'),
        );
        await host.wake('nekodot-a');
        expect(vercel.requests.last.url.queryParameters['resume'], 'true');
        vercel.on('DELETE', '/v2/sandboxes/nekodot-a', {'sandbox': {}});
        await host.delete('nekodot-a');
        expect(vercel.requests.last.url.queryParameters['projectId'], 'prj_1');
      },
    );
  });
}
