import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { managementReplay } from './management';
import {
  botSchema,
  hermesApprovalSchema,
  hermesCreateRunSchema,
  hermesRunStateSchema,
  hermesSseEventSchema,
  type HermesRunState,
} from '@nekodot/protocol';

const scenarios = [
  'runs-basic',
  'runs-tools',
  'runs-tools-approval',
  'runs-approval-deny',
  'runs-steer',
  'runs-stop',
] as const;
interface Fixture {
  events: ReturnType<typeof hermesSseEventSchema.parse>[];
  final: HermesRunState;
  pending?: HermesRunState;
}
interface ReplayRun {
  profile: string;
  scenario: string;
  input: string;
  instructions?: string;
  fixture: Fixture;
  state: HermesRunState;
  stopped: boolean;
  steers: string[];
  steerReplay: boolean;
  toolStarts: number;
  frames: Fixture['events'];
  clients: Set<ServerResponse>;
  replaying: boolean;
  ended: boolean;
  release?: () => void;
}
export interface FakeHermesOptions {
  fixturesDirectory: string;
  profiles: string[];
  apiKey: string;
  allowProfileCreate?: boolean;
  models?: unknown;
  eventDelayMs?: number;
  additionalFixtures?: string[];
  scenarioFor?: (
    input: { input: string; session_id?: string; instructions?: string },
    profile: string,
  ) => string | undefined;
}
function json(response: ServerResponse, status: number, body: unknown) {
  response.writeHead(status, { 'Content-Type': 'application/json' });
  response.end(JSON.stringify(body));
}
async function body(request: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  for await (const chunk of request) chunks.push(Buffer.from(chunk));
  return JSON.parse(Buffer.concat(chunks).toString('utf8')) as unknown;
}

/** Test-only HTTP replay. No provider, shell execution, or product runtime entry point. */
export async function startFakeHermes(options: FakeHermesOptions) {
  const management = await managementReplay(options.fixturesDirectory, options.apiKey);
  const fixtures = new Map<string, Fixture>();
  for (const name of [...scenarios, ...(options.additionalFixtures ?? [])]) {
    const raw = await readFile(join(options.fixturesDirectory, name + '.sse'), 'utf8');
    const events = raw
      .trim()
      .split(/\r?\n\r?\n/)
      .flatMap((frame) => {
        const data = frame.split(/\r?\n/).filter((line) => line.startsWith('data:'));
        return data.length
          ? [
              hermesSseEventSchema.parse(
                JSON.parse(data.map((line) => line.slice(5).trimStart()).join('\n')),
              ),
            ]
          : [];
      });
    const states = JSON.parse(
      await readFile(join(options.fixturesDirectory, name + '.state.json'), 'utf8'),
    ) as { final: unknown; pending: unknown };
    fixtures.set(name, {
      events,
      final: hermesRunStateSchema.parse(states.final),
      ...(states.pending ? { pending: hermesRunStateSchema.parse(states.pending) } : {}),
    });
  }
  const runs = new Map<string, ReplayRun>();
  async function replay(runId: string, run: ReplayRun) {
    run.replaying = true;
    let toolGateSeen = false;
    for (const recorded of run.fixture.events) {
      let event = { ...recorded, run_id: runId };
      if (run.stopped && !run.scenario.endsWith('-stop')) {
        const cancelled = fixtures.get('runs-stop')!;
        event = {
          ...cancelled.events.find((item) => item.event === 'run.cancelled')!,
          run_id: runId,
          seq: recorded.seq,
        };
        run.state = { ...cancelled.final, run_id: runId, session_id: run.state.session_id };
      }
      let gate: Promise<void> | undefined;
      if (event.event === 'approval.request' && !run.stopped) {
        run.state = { ...run.fixture.pending!, run_id: runId, session_id: run.state.session_id };
        gate = new Promise<void>((resolve) => {
          run.release = resolve;
        });
      }
      if (
        (run.scenario.endsWith('-stop') || run.steerReplay) &&
        event.event === 'tool.started' &&
        !toolGateSeen
      ) {
        toolGateSeen = true;
        if (!run.stopped && !run.steers.length)
          gate = new Promise<void>((resolve) => {
            run.release = resolve;
          });
      }
      if (event.event === 'tool.started') run.toolStarts++;
      if (
        ['run.completed', 'run.cancelled', 'run.failed', 'run.interrupted'].includes(event.event)
      ) {
        if (!run.stopped || run.scenario.endsWith('-stop'))
          run.state = { ...run.fixture.final, run_id: runId, session_id: run.state.session_id };
      }
      run.frames.push(event);
      for (const client of run.clients)
        client.write('id: ' + event.seq + '\ndata: ' + JSON.stringify(event) + '\n\n');
      if (event.event === 'run.cancelled' && run.stopped) break;
      if (gate) {
        await gate;
        run.release = undefined;
      }
      await delay(options.eventDelayMs ?? 1);
    }
    run.ended = true;
    for (const client of run.clients) client.end();
    run.clients.clear();
  }
  async function route(request: IncomingMessage, response: ServerResponse) {
    if (await management.route(request, response)) return;
    if (request.headers.authorization !== 'Bearer ' + options.apiKey)
      return json(response, 401, {
        error: { code: 'unauthorized', message: 'Invalid test API key' },
      });
    if (request.method === 'POST' && request.url === '/test/profiles') {
      if (!options.allowProfileCreate)
        return json(response, 404, { error: { code: 'not_found', message: 'Not found' } });
      const input = await body(request);
      if (!input || typeof input !== 'object' || !('profile' in input))
        return json(response, 400, {
          error: { code: 'invalid_params', message: 'Profile is required' },
        });
      const profile = botSchema.shape.botId.parse(input.profile);
      if (!options.profiles.includes(profile)) options.profiles.push(profile);
      return json(response, 201, { profile });
    }
    const path = new URL(request.url ?? '/', 'http://127.0.0.1').pathname.split('/');
    const profile = path[2];
    if (path[1] !== 'p' || !profile || !options.profiles.includes(profile))
      return json(response, 404, {
        error: { code: 'profile_not_found', message: 'Unknown test profile' },
      });
    if (request.method === 'GET' && path[3] === 'health' && path.length === 4)
      return json(response, 200, { status: 'ok', profile });
    if (
      request.method === 'GET' &&
      path[3] === 'api' &&
      path[4] === 'model' &&
      path[5] === 'options'
    )
      return json(
        response,
        200,
        options.models ?? {
          provider: 'custom',
          providers: [{ slug: 'custom', models: [], is_current: true }],
        },
      );
    if (path[3] !== 'v1' || path[4] !== 'runs') return json(response, 404, {});
    if (request.method === 'POST' && path.length === 5) {
      const input = hermesCreateRunSchema.parse(await body(request));
      const inputText = input.input.toLowerCase();
      const scenario =
        options.scenarioFor?.(input, profile) ??
        scenarios.find((name) => name === input.input) ??
        [...scenarios]
          .sort((a, b) => b.length - a.length)
          .find((name) => input.input.includes(name)) ??
        (inputText.includes('long task')
          ? 'runs-stop'
          : inputText.includes('steer') || inputText.includes('same run')
            ? 'runs-steer'
            : inputText.includes('deny') || inputText.includes('denial')
              ? 'runs-approval-deny'
              : inputText.includes('approval') || inputText.includes('approve')
                ? 'runs-tools-approval'
                : inputText.includes('hello') || inputText.includes('greeting')
                  ? 'runs-basic'
                  : undefined);
      if (!scenario || !fixtures.has(scenario))
        return json(response, 400, {
          error: { code: 'unknown_fixture', message: 'Use a recorded scenario name as input' },
        });
      const fixture = fixtures.get(scenario)!;
      const runId = 'run_' + randomUUID().replaceAll('-', '');
      runs.set(runId, {
        profile,
        scenario,
        input: input.input,
        instructions: input.instructions,
        fixture,
        stopped: false,
        steers: [],
        steerReplay: scenario.endsWith('-steer'),
        toolStarts: 0,
        frames: [],
        clients: new Set(),
        replaying: false,
        ended: false,
        state: {
          run_id: runId,
          session_id: input.session_id,
          status: 'running',
          output: '',
          execution_generation: fixture.final.execution_generation,
          pending_controls: [],
        },
      });
      return json(response, 202, { run_id: runId, status: 'running' });
    }
    const runId = path[5];
    const run = runId ? runs.get(runId) : undefined;
    if (!run || run.profile !== profile)
      return json(response, 404, {
        error: { code: 'run_not_found', message: 'Run not found in this profile' },
      });
    if (request.method === 'GET' && path.length === 6) return json(response, 200, run.state);
    if (request.method === 'POST' && path[6] === 'steer') {
      const input = await body(request);
      if (
        !input ||
        typeof input !== 'object' ||
        !('input' in input) ||
        typeof input.input !== 'string' ||
        !input.input
      )
        return json(response, 400, {
          error: { code: 'invalid_params', message: 'Input is required' },
        });
      if (!['running', 'queued', 'pending'].includes(run.state.status))
        return json(response, 409, {
          error: { code: 'run_not_active', message: 'Run is no longer active' },
        });
      if (!run.steerReplay)
        return json(response, 409, {
          error: { code: 'steer_not_recorded', message: 'This run has no recorded steer replay.' },
        });
      run.steers.push(input.input);
      run.state = { ...run.state, pending_steer: input.input };
      run.release?.();
      return json(response, 200, { run_id: runId, accepted: true });
    }
    if (request.method === 'POST' && path[6] === 'approval') {
      const approval = hermesApprovalSchema.parse(await body(request));
      const pending = run.state.pending_controls?.find(
        (item) => item.prompt_id === approval.request_id,
      );
      const expected = run.scenario === 'runs-tools-approval' ? 'once' : 'deny';
      if (
        !pending ||
        approval.execution_generation !== run.state.execution_generation ||
        approval.choice !== expected
      )
        return json(response, 409, {
          error: {
            code: 'approval_not_active',
            message: 'Approval must match the recorded pending request and choice',
          },
        });
      run.state = { ...run.state, status: 'running', pending_controls: [] };
      json(response, 200, { run_id: runId, status: 'resolved', prompt_id: approval.request_id });
      run.release?.();
      return;
    }
    if (request.method === 'POST' && path[6] === 'stop') {
      run.stopped = true;
      run.state = { ...run.state, status: 'stopping', pending_controls: [] };
      json(response, 200, {
        run_id: runId,
        status: 'stopping',
        admission_id: run.fixture.final.admission_id,
      });
      run.release?.();
      return;
    }
    if (request.method === 'GET' && path[6] === 'events') {
      response.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache' });
      response.write(': open\n\n');
      const lastSeq = Number(request.headers['last-event-id'] ?? -1);
      for (const event of run.frames)
        if (event.seq > lastSeq)
          response.write('id: ' + event.seq + '\ndata: ' + JSON.stringify(event) + '\n\n');
      if (run.ended) response.end();
      else {
        run.clients.add(response);
        response.once('close', () => run.clients.delete(response));
        if (!run.replaying) void replay(runId!, run);
      }
      return;
    }
    json(response, 404, {});
  }
  const server = createServer((request, response) => {
    void route(request, response).catch((error: unknown) => {
      if (response.headersSent) response.destroy();
      else json(response, 400, { error: { code: 'invalid_request', message: String(error) } });
    });
  });
  const closeManagement = management.attach(server);
  await new Promise<void>((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('Test server has no TCP address');
  return {
    url: 'http://127.0.0.1:' + address.port,
    pluginCatalog: management.catalog,
    inspectRuns: () =>
      [...runs.entries()].map(([runId, run]) => ({
        runId,
        profile: run.profile,
        scenario: run.scenario,
        sessionId: run.state.session_id,
        input: run.input,
        instructions: run.instructions,
        steers: [...run.steers],
        toolStarts: run.toolStarts,
      })),
    close: async () => {
      closeManagement();
      for (const run of runs.values()) run.release?.();
      server.closeAllConnections();
      await new Promise<void>((resolve, reject) =>
        server.close((error) => (error ? reject(error) : resolve())),
      );
    },
  };
}
