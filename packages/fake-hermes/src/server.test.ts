import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { resolve } from 'node:path';
import { randomUUID } from 'node:crypto';
import { startFakeHermes } from './index';
import { HermesApi } from '../../../apps/node/src/hermes/api';
import type { SseFrame } from '../../../apps/node/src/hermes/sse';

describe('recorded Hermes HTTP journeys', () => {
  let server: Awaited<ReturnType<typeof startFakeHermes>>;
  let api: HermesApi;
  beforeAll(async () => {
    server = await startFakeHermes({
      fixturesDirectory: resolve('docs/fixtures'),
      profiles: ['nk-abcdef', 'nk-ghijkl'],
      apiKey: 'test-local-key',
    });
    api = new HermesApi(server.url + '/p/nk-abcdef', 'test-local-key');
  });
  afterAll(async () => {
    await server?.close();
  });

  async function create(scenario: string) {
    return api.createRun(scenario, 'nk_dm_test', randomUUID());
  }
  it('checks profile health and streams a real recorded response', async () => {
    const health = await fetch(api.baseUrl + '/health', {
      headers: { Authorization: 'Bearer test-local-key' },
    });
    expect(health.status).toBe(200);
    const created = await create('runs-basic');
    const frames: SseFrame[] = [];
    for await (const frame of api.events(created.run_id)) frames.push(frame);
    expect(
      frames
        .filter((frame) => frame.event === 'message.delta')
        .map((frame) => frame.data.delta)
        .join(''),
    ).toContain('NEKODOT_PHASE0_OK');
    expect(frames.at(-1)?.event).toBe('run.completed');
    expect((await api.state(created.run_id)).status).toBe('completed');
    expect(frames.every((frame) => frame.data.run_id === created.run_id)).toBe(true);
  });
  it('pairs tool start/completion through the actual tool_call_id', async () => {
    const created = await create('runs-tools');
    const frames: SseFrame[] = [];
    for await (const frame of api.events(created.run_id)) frames.push(frame);
    const start = frames.find((frame) => frame.event === 'tool.started');
    const completed = frames.find((frame) => frame.event === 'tool.completed');
    expect(start?.data.tool_call_id).toBeTypeOf('string');
    expect(completed?.data.tool_call_id).toBe(start?.data.tool_call_id);
    expect((await api.state(created.run_id)).output).toContain('NEKODOT_TOOL_OK');
  });
  it.each([
    ['runs-tools-approval', 'once'],
    ['runs-approval-deny', 'deny'],
  ] as const)('waits for the user before %s can continue', async (scenario, choice) => {
    const created = await create(scenario);
    const events: string[] = [];
    let approvalRequested = false;
    let mutationFailed: unknown;
    for await (const frame of api.events(created.run_id)) {
      events.push(frame.event);
      if (frame.event === 'tool.completed' && approvalRequested) mutationFailed = frame.data.error;
      if (frame.event === 'approval.request') {
        approvalRequested = true;
        const pending = await api.state(created.run_id);
        expect(pending.status).toBe('waiting_for_approval');
        const control = pending.pending_controls![0]!;
        await expect(
          api.approve(created.run_id, 'wrong-request', pending.execution_generation!, choice),
        ).rejects.toThrow('409');
        await api.approve(created.run_id, control.prompt_id, pending.execution_generation!, choice);
      }
    }
    expect(events).toContain('approval.settled');
    expect(events.indexOf('approval.settled')).toBeGreaterThan(events.indexOf('approval.request'));
    const final = await api.state(created.run_id);
    expect(final.status).toBe('completed');
    expect(final.pending_controls).toEqual([]);
    expect(approvalRequested).toBe(true);
    expect(mutationFailed).toBe(choice === 'deny');
  });
  it('stops a running tool and consumes the recorded cancellation', async () => {
    const created = await create('runs-stop');
    const events: string[] = [];
    let stopped = false;
    for await (const frame of api.events(created.run_id)) {
      events.push(frame.event);
      if (frame.event === 'tool.started' && !stopped) {
        expect(await api.stop(created.run_id)).toMatchObject({ status: 'stopping' });
        stopped = true;
      }
    }
    expect(events).toContain('run.cancelled');
    expect((await api.state(created.run_id)).status).toBe('cancelled');
  });
  it('cancels a waiting approval without granting the file write', async () => {
    const created = await create('runs-tools-approval');
    const events: string[] = [];
    for await (const frame of api.events(created.run_id)) {
      events.push(frame.event);
      if (frame.event === 'approval.request') await api.stop(created.run_id);
    }
    expect(events).not.toContain('approval.settled');
    expect(events.at(-1)).toBe('run.cancelled');
    expect((await api.state(created.run_id)).status).toBe('cancelled');
  });
  it('keeps runs in their profile and rejects malformed external requests', async () => {
    const created = await create('runs-basic');
    const other = new HermesApi(server.url + '/p/nk-ghijkl', 'test-local-key');
    await expect(other.state(created.run_id)).rejects.toThrow('404');
    const response = await fetch(api.baseUrl + '/v1/runs', {
      method: 'POST',
      headers: { Authorization: 'Bearer test-local-key', 'Content-Type': 'application/json' },
      body: JSON.stringify({ input: 123 }),
    });
    expect(response.status).toBe(400);
    const unauthorized = await fetch(api.baseUrl + '/health');
    expect(unauthorized.status).toBe(401);
  });
});
