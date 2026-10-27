import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import {
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
  'runs-stop',
] as const;
type Scenario = (typeof scenarios)[number];
interface Fixture {
  events: ReturnType<typeof hermesSseEventSchema.parse>[];
  final: HermesRunState;
  pending?: HermesRunState;
}
interface ReplayRun {
  profile: string;
  scenario: Scenario;
  fixture: Fixture;
  state: HermesRunState;
  stopped: boolean;
  release?: () => void;
}
export interface FakeHermesOptions {
  fixturesDirectory: string;
  profiles: string[];
  apiKey: string;
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
  const fixtures = new Map<Scenario, Fixture>();
  for (const name of scenarios) {
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
  async function route(request: IncomingMessage, response: ServerResponse) {
    if (request.headers.authorization !== 'Bearer ' + options.apiKey)
      return json(response, 401, {
        error: { code: 'unauthorized', message: 'Invalid test API key' },
      });
    const path = new URL(request.url ?? '/', 'http://127.0.0.1').pathname.split('/');
    const profile = path[2];
    if (path[1] !== 'p' || !profile || !options.profiles.includes(profile))
      return json(response, 404, {
        error: { code: 'profile_not_found', message: 'Unknown test profile' },
      });
    if (request.method === 'GET' && path[3] === 'health' && path.length === 4)
      return json(response, 200, { status: 'ok', profile });
    if (path[3] !== 'v1' || path[4] !== 'runs') return json(response, 404, {});
    if (request.method === 'POST' && path.length === 5) {
      const input = hermesCreateRunSchema.parse(await body(request));
      const scenario = scenarios.find((name) => name === input.input);
      if (!scenario)
        return json(response, 400, {
          error: { code: 'unknown_fixture', message: 'Use a recorded scenario name as input' },
        });
      const fixture = fixtures.get(scenario)!;
      const runId = 'run_' + randomUUID().replaceAll('-', '');
      runs.set(runId, {
        profile,
        scenario,
        fixture,
        stopped: false,
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
      response.once('close', () => run.release?.());
      let stopGateSeen = false;
      for (const event of run.fixture.events) {
        if (response.destroyed) break;
        if (run.stopped && run.scenario !== 'runs-stop') {
          const cancelled = fixtures.get('runs-stop')!;
          const terminal = cancelled.events.find((item) => item.event === 'run.cancelled')!;
          run.state = { ...cancelled.final, run_id: runId!, session_id: run.state.session_id };
          response.write(
            'id: ' +
              event.seq +
              '\ndata: ' +
              JSON.stringify({ ...terminal, run_id: runId, seq: event.seq }) +
              '\n\n',
          );
          break;
        }
        let gate: Promise<void> | undefined;
        if (event.event === 'approval.request' && !run.stopped) {
          run.state = { ...run.fixture.pending!, run_id: runId!, session_id: run.state.session_id };
          gate = new Promise<void>((resolve) => {
            run.release = resolve;
          });
        }
        if (run.scenario === 'runs-stop' && event.event === 'tool.started' && !stopGateSeen) {
          stopGateSeen = true;
          if (!run.stopped)
            gate = new Promise<void>((resolve) => {
              run.release = resolve;
            });
        }
        if (
          event.event.startsWith('run.') &&
          ['run.completed', 'run.cancelled', 'run.failed', 'run.interrupted'].includes(event.event)
        )
          run.state = { ...run.fixture.final, run_id: runId!, session_id: run.state.session_id };
        response.write(
          'id: ' + event.seq + '\ndata: ' + JSON.stringify({ ...event, run_id: runId }) + '\n\n',
        );
        if (gate) {
          await gate;
          run.release = undefined;
        }
        await delay(1);
      }
      response.end();
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
  await new Promise<void>((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('Test server has no TCP address');
  return {
    url: 'http://127.0.0.1:' + address.port,
    close: async () => {
      for (const run of runs.values()) run.release?.();
      server.closeAllConnections();
      await new Promise<void>((resolve, reject) =>
        server.close((error) => (error ? reject(error) : resolve())),
      );
    },
  };
}
