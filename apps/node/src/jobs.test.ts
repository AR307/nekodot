import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import type { LiveEvent } from '@nekodot/protocol';
import { NodeDatabase, type RunRecord } from './database';
import { HermesGatewayError } from './hermes/gateway';
import type { HermesRuntime } from './hermes/runtime';
import { BackgroundJobs, commandLabel, durationSeconds, jobProgress } from './jobs';
import type { BotSecrets } from './secrets';

describe('a job’s progress line', () => {
  it('reads tqdm’s layout, the newest of its redraws', () => {
    const output =
      'Loading list\n' +
      'Collecting pages:  44%|████▍     | 440/1000 [00:29<00:38, 14.90it/s]\r' +
      'Collecting pages:  45%|████▌     | 450/1000 [00:30<00:37, 14.95it/s]\r';
    expect(jobProgress(output)).toEqual({
      label: 'Collecting pages',
      percent: 45,
      done: '450',
      total: '1000',
      elapsedSeconds: 30,
      etaSeconds: 37,
      rate: '14.95it/s',
    });
  });

  it('keeps sizes, postfixes, colours and long runs as tqdm prints them', () => {
    expect(
      jobProgress(
        '\u001b[32m下载数据\u001b[0m:  12%|█▏        | 12.3M/100M [1:02:03<7:20:00, 3.31MB/s, file=a.csv]',
      ),
    ).toMatchObject({
      label: '下载数据',
      percent: 12,
      done: '12.3M',
      total: '100M',
      elapsedSeconds: 3723,
      etaSeconds: 26400,
      rate: '3.31MB/s',
    });
    expect(jobProgress('  0%|          | 0/1000 [00:00<?, ?it/s]')).toEqual({
      label: undefined,
      percent: 0,
      done: '0',
      total: '1000',
      elapsedSeconds: 0,
    });
    expect(jobProgress('Scraping: 450it [00:30, 14.95it/s]')).toEqual({
      label: 'Scraping',
      done: '450',
      elapsedSeconds: 30,
      rate: '14.95it/s',
    });
  });

  it('reads any line that says how far it is and its ETA', () => {
    expect(jobProgress('Downloading files 450/1,000 (45%) ETA 2m 10s')).toMatchObject({
      label: 'Downloading files',
      done: '450',
      total: '1,000',
      percent: 45,
      etaSeconds: 130,
    });
    expect(jobProgress('[450/1000] ETA 00:37 elapsed 00:30')).toMatchObject({
      label: undefined,
      percent: 45,
      etaSeconds: 37,
      elapsedSeconds: 30,
    });
    expect(jobProgress('采集进度：62.5% 剩余时间：2分10秒')).toMatchObject({
      label: '采集进度',
      percent: 62.5,
      etaSeconds: 130,
    });
  });

  it('is not every line with a number in it', () => {
    for (const line of [
      'CPU 45% memory 2/8 GB',
      'Saved 450/1000 rows',
      'Server listening on :8080',
      'ETA unknown',
      '',
    ])
      expect(jobProgress(line)).toBeUndefined();
  });

  it('reads durations as scripts print them', () => {
    expect(durationSeconds('00:37')).toBe(37);
    expect(durationSeconds('1:02:03')).toBe(3723);
    expect(durationSeconds('2m10s')).toBe(130);
    expect(durationSeconds('1h 5m')).toBe(3900);
    expect(durationSeconds('3 min')).toBe(180);
    expect(durationSeconds('1小时5分')).toBe(3900);
    expect(durationSeconds('soon')).toBeUndefined();
    expect(durationSeconds('5 apples')).toBeUndefined();
  });

  it('names a job by its script when its line gives no description', () => {
    expect(commandLabel('cd /work && python3 scripts/collect_pages.py --pages 1000')).toBe(
      'collect_pages.py',
    );
    expect(commandLabel('curl -O https://example.com/data.zip')).toBe(
      'curl -O https://example.com/data.zip',
    );
  });
});

const botId = 'nk-abcdef';
const run = {
  botId,
  conversationId: 'chat',
  inputMessageId: 'input',
  runId: 'run',
  sessionId: 'live-session',
  storedSessionId: 'stored-session',
  state: 'thinking',
  lastSeq: 0,
} as RunRecord;

async function setup() {
  const database = new NodeDatabase(await mkdtemp(join(tmpdir(), 'nekodot-jobs-')));
  const calls: [string, Record<string, unknown>][] = [];
  const state: { processes: object[]; live: boolean } = { processes: [], live: true };
  const gateway = {
    rpc: async (method: string, params: Record<string, unknown>) => {
      calls.push([method, params]);
      if (method === 'process.list') {
        if (!state.live) throw new HermesGatewayError('not_found');
        return { processes: state.processes };
      }
      if (method === 'session.resume') state.live = true;
      return {};
    },
  };
  const hermes = { gateway: () => gateway } as unknown as HermesRuntime;
  const secrets = {
    scrub: (_bot: string, text: string) => text.replace('s3cret', '[confidential]'),
  } as unknown as BotSecrets;
  const live: LiveEvent[] = [];
  const jobs = new BackgroundJobs(database, hermes, secrets, (event) => live.push(event), 60_000);
  const card = () => {
    const message = database.messages('chat').find((item) => item.kind === 'job');
    return message?.kind === 'job' ? message : undefined;
  };
  return { database, jobs, state, calls, live, card };
}

const process = (overrides: object) => ({
  session_id: 'proc_4dae91c03b2f',
  command: 'TOKEN=s3cret python3 collect.py',
  status: 'running',
  exit_code: null,
  started_epoch: Date.now() / 1000 - 30,
  completion_reason: null,
  output_tail: '',
  ...overrides,
});

describe('a Dot’s background job', () => {
  it('becomes a card once it prints progress, updates live, and is saved when it ends', async () => {
    const { jobs, state, live, card, calls } = await setup();
    jobs.track(run, 'proc_4dae91c03b2f');

    state.processes = [process({ output_tail: 'Starting\n' })];
    await jobs.poll();
    expect(card()).toBeUndefined();

    state.processes = [
      process({ output_tail: 'Pages:  45%|████▌     | 450/1000 [00:30<00:37, 14.95it/s]\r' }),
    ];
    await jobs.poll();
    expect(calls[0]).toEqual(['process.list', { session_id: 'stored-session' }]);
    expect(card()).toMatchObject({
      author: { type: 'bot', id: botId },
      status: 'streaming',
      content: {
        label: 'Pages',
        state: 'running',
        done: '450',
        total: '1000',
        percent: 45,
        etaSeconds: 37,
        elapsedSeconds: 30,
        rate: '14.95it/s',
      },
    });

    state.processes = [
      process({ output_tail: 'Pages:  60%|██████    | 600/1000 [00:40<00:26, 15.00it/s]\r' }),
    ];
    await jobs.poll();
    expect(card()!.content.done).toBe('450');
    expect(live.at(-1)).toMatchObject({
      kind: 'job',
      conversationId: 'chat',
      messageId: card()!.messageId,
      content: { done: '600', percent: 60, etaSeconds: 26 },
    });

    state.processes = [
      process({
        status: 'exited',
        exit_code: 0,
        exited_at: Date.now() / 1000,
        completion_reason: 'exited',
        output_tail: 'Pages: 100%|██████████| 1000/1000 [01:07<00:00, 14.90it/s]\nDone\n',
      }),
    ];
    await jobs.poll();
    expect(card()).toMatchObject({
      status: 'done',
      content: { state: 'done', done: '1000', percent: 100, exitCode: 0, elapsedSeconds: 67 },
    });
    expect(card()!.content).not.toHaveProperty('etaSeconds');
    await expect(jobs.stop(card()!.messageId)).rejects.toThrow(/no longer running/);
    await jobs.close();
  });

  it('is stopped from its card, and says so once Hermes reports it', async () => {
    const { jobs, state, card, calls } = await setup();
    jobs.track(run, 'proc_4dae91c03b2f');
    state.processes = [process({ output_tail: '[120/400] 30% ETA 1:10' })];
    await jobs.poll();
    // Named by its script; the token in its command stays out of the card.
    expect(card()!.content.label).toBe('collect.py');
    await jobs.stop(card()!.messageId);
    expect(calls.at(-1)).toEqual([
      'process.kill',
      { session_id: 'stored-session', process_id: 'proc_4dae91c03b2f' },
    ]);
    state.processes = [
      process({
        status: 'exited',
        exit_code: -15,
        completion_reason: 'killed',
        output_tail: '[130/400] 32.5% ETA 1:05',
      }),
    ];
    await jobs.poll();
    expect(card()).toMatchObject({
      status: 'cancelled',
      content: { state: 'stopped', done: '130', exitCode: -15 },
    });
    await jobs.close();
  });

  it('asks a session Hermes let go of again, and gives up on a process it forgot', async () => {
    const { jobs, state, card, calls, database } = await setup();
    jobs.track(run, 'proc_4dae91c03b2f');
    state.live = false;
    state.processes = [
      process({ output_tail: 'Pages:  10%|█         | 1/10 [00:01<00:09, 1.00it/s]' }),
    ];
    await jobs.poll();
    expect(calls.map(([method]) => method)).toEqual([
      'process.list',
      'session.resume',
      'process.list',
    ]);
    expect(card()!.content.state).toBe('running');

    // The node restarts and Hermes, restarted too, no longer has the process.
    await jobs.close();
    const again = new BackgroundJobs(
      database,
      { gateway: () => ({ rpc: async () => ({ processes: [] }) }) } as unknown as HermesRuntime,
      { scrub: (_bot: string, text: string) => text } as unknown as BotSecrets,
      () => {},
      60_000,
    );
    for (let i = 0; i < 3; i++) await again.poll();
    expect(card()).toMatchObject({ status: 'cancelled', content: { state: 'stopped' } });
    expect(card()!.content).not.toHaveProperty('etaSeconds');
    await again.close();
  });

  it('shows no card for a background process that never prints progress', async () => {
    const { jobs, state, card } = await setup();
    jobs.track(run, 'proc_4dae91c03b2f');
    state.processes = [
      process({ command: 'python3 -m http.server 8000', output_tail: 'Serving HTTP on 0.0.0.0' }),
    ];
    await jobs.poll();
    state.processes = [process({ status: 'exited', exit_code: 0, output_tail: 'bye' })];
    await jobs.poll();
    expect(card()).toBeUndefined();
    await jobs.close();
  });
});
