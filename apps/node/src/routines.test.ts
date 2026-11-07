import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { expect, it } from 'vitest';
import { NodeDatabase } from './database';
import { Routines } from './routines';
import { Notifications } from './notifications';
import type { HermesRuntime } from './hermes/runtime';
import type { RoutineRoute, TaskNotification } from '@nekodot/protocol';

function nativeSession(db: NodeDatabase, botId: string, conversationId: string) {
  db.saveHermesSession({
    conversationId,
    botId,
    storedSessionId: 'native-dm',
    replayEpoch: 'epoch',
    lastSequence: 0,
  });
}

it('keeps credentials out of chat, requires a user grant and rotates the same script reference', async () => {
  const home = await mkdtemp(join(tmpdir(), 'nekodot-routines-'));
  const db = new NodeDatabase(home);
  const botId = 'nk-abcdef';
  db.putBot({
    botId,
    displayName: 'Routine Bot',
    handle: 'routine',
    role: '',
    model: 'qa',
    avatar: { shape: 'dot', color: '#E8603C' },
    archived: false,
    createdAt: new Date().toISOString(),
  });
  const conversationId = randomUUID();
  db.putConversation({ conversationId, botId, kind: 'dm', createdAt: new Date().toISOString() });
  nativeSession(db, botId, conversationId);
  const groupId = randomUUID();
  db.putGroup(
    {
      groupId,
      name: 'Routine team',
      botIds: [botId],
      leadBotId: botId,
      archived: false,
      createdAt: new Date().toISOString(),
    },
    { conversationId: groupId, kind: 'group', groupId, createdAt: new Date().toISOString() },
  );
  let enabled = false;
  const hermes = {
    webhookUrl: 'http://127.0.0.1:1',
    cli: async () => 'Secret: native-internal-credential',
    profileHome: (profile: string) => join(home, 'hermes', 'profiles', profile),
    gateway: () => ({ rpc: async () => ({ output: '[]' }) }),
    management: {
      request: async (path: string, _profile: string, init?: RequestInit) => {
        if (init) enabled = (JSON.parse(String(init.body)) as { enabled: boolean }).enabled;
        if (path === '/api/cron/jobs') return [];
        if (path.startsWith('/api/config')) return { approvals: { mode: 'manual' } };
        if (path === '/api/webhooks') return { subscriptions: [] };
        return { enabled };
      },
    },
  } as unknown as HermesRuntime;
  const routines = new Routines(db, hermes, new Notifications(db));
  let routes: RoutineRoute[] = [];
  routines.onRoutes = async (value) => {
    routes = value;
  };
  const routine = await routines.create({
    botId,
    name: 'Scanner',
    description: 'test',
    prompt: '{__raw__}',
    events: ['scan'],
    skills: [],
  });
  const first = routines.credentials(botId, routine.routineId).secret;
  expect(enabled).toBe(false);
  await expect(routines.enable(botId, routine.routineId, true)).rejects.toThrow('Approve');
  await routines.enable(botId, routine.routineId, true, true);
  expect(routes[0]!.enabled).toBe(true);
  expect(db.messages(conversationId).filter((m) => m.kind === 'routine')).toHaveLength(3);
  const oldDigest = routes[0]!.digest;
  await routines.rotate(botId, routine.routineId);
  expect(routes[0]!.digest).not.toBe(oldDigest);
  expect(routines.credentials(botId, routine.routineId).secret).not.toBe(first);
  const stored = String(db.db.prepare('SELECT data FROM routines').get()!.data);
  expect(stored).not.toContain(first);
  expect(stored).not.toContain('native-internal-credential');
  expect(JSON.stringify(db.messages(conversationId))).not.toContain(first);
  await expect(
    routines.deliver({
      routineId: routine.routineId,
      digest: oldDigest,
      requestId: 'old',
      body: '{}',
    }),
  ).resolves.toMatchObject({ status: 403 });
  const grouped = await routines.create(
    { botId, name: 'Group scanner', description: '', prompt: 'test', events: [], skills: [] },
    groupId,
  );
  expect(
    db
      .messages(groupId)
      .some((m) => m.kind === 'routine' && m.content.routineId === grouped.routineId),
  ).toBe(true);
  expect(
    db
      .messages(conversationId)
      .some((m) => m.kind === 'routine' && m.content.routineId === grouped.routineId),
  ).toBe(false);
  await routines.close();
  db.db.close();
});

it('recovers a native admission failure after restart without rerunning it or duplicating the result', async () => {
  const home = await mkdtemp(join(tmpdir(), 'nekodot-routine-result-'));
  const db = new NodeDatabase(home);
  const botId = 'nk-abcdef';
  db.putBot({
    botId,
    displayName: 'Routine Bot',
    handle: 'routine',
    role: '',
    model: 'qa',
    avatar: { shape: 'dot', color: '#E8603C' },
    archived: false,
    createdAt: new Date().toISOString(),
  });
  const conversationId = randomUUID();
  db.putConversation({ conversationId, botId, kind: 'dm', createdAt: new Date().toISOString() });
  nativeSession(db, botId, conversationId);
  let native: Record<string, unknown>[] = [];
  const hermes = {
    webhookUrl: 'http://127.0.0.1:1',
    cli: async () => 'Secret: internal',
    profileHome: (profile: string) => join(home, profile),
    management: {
      request: async (path: string) => (path === '/api/cron/jobs' ? [] : {}),
    },
    gateway: () => ({
      rpc: async (method: string, params: { session_id: string; arg: string }) => {
        expect(method).toBe('command.dispatch');
        expect(params.session_id).toBe('native-dm');
        const { profile, settled } = JSON.parse(params.arg) as {
          profile: string;
          settled: string[];
        };
        expect(profile).toBe(botId);
        return {
          output: JSON.stringify(native.filter((e) => !settled.includes(String(e.sessionId)))),
        };
      },
    }),
  } as unknown as HermesRuntime;
  const signals: TaskNotification[] = [];
  const notifications = new Notifications(db);
  notifications.onSend = (value) => signals.push(value);
  let routines = new Routines(db, hermes, notifications);
  routines.onRoutes = async () => {};
  const task = await routines.create({
    botId,
    name: 'Scanner',
    description: '',
    prompt: 'Fixed task',
    events: [],
    skills: [],
  });
  const base = {
    botId,
    sessionId: 'native-session',
    admissionId: 'native-admission',
    route: 'nk-' + task.routineId,
    jobId: null,
    requestId: 'scan-001',
    text: '',
    time: Date.now() / 1000,
  };
  native = [{ ...base, phase: 'started' }];
  await routines.drain();
  expect(db.messages(conversationId).filter((m) => m.kind === 'text')).toHaveLength(0);
  await routines.close();
  routines = new Routines(db, hermes, notifications);
  native = [
    {
      ...base,
      phase: 'ended',
      completed: false,
      failed: true,
      reason: 'model_error',
    },
  ];
  await routines.drain();
  const messages = db.messages(conversationId).filter((m) => m.kind === 'text');
  expect(messages).toHaveLength(1);
  expect(messages[0]).toMatchObject({
    status: 'failed',
    content: {
      text: '',
      failureReason: 'model_error',
      routine: { sessionId: 'native-session' },
    },
  });
  await routines.drain();
  expect(db.messages(conversationId).filter((m) => m.kind === 'text')).toHaveLength(1);
  expect(signals.map((s) => s.kind)).toEqual(['failed']);
  expect(routines.execution(botId, task.routineId + ':native-session').sessionId).toBe(
    'native-session',
  );
  await routines.close();
  db.db.close();
});

it('shows a one-shot completion without reporting a user stop, while a pause still reports stopped', async () => {
  const db = new NodeDatabase(await mkdtemp(join(tmpdir(), 'nekodot-cron-notice-')));
  const botId = 'nk-abcdef',
    conversationId = randomUUID();
  db.putBot({
    botId,
    displayName: 'Notice Bot',
    handle: 'notice',
    role: '',
    model: 'qa',
    avatar: { shape: 'dot', color: '#E8603C' },
    archived: false,
    createdAt: new Date().toISOString(),
  });
  db.putConversation({ conversationId, botId, kind: 'dm', createdAt: new Date().toISOString() });
  nativeSession(db, botId, conversationId);
  const job = {
    id: 'once',
    name: 'Reminder',
    prompt: 'Test reminder',
    schedule: { kind: 'once' },
    enabled: true,
    state: 'scheduled',
  };
  const jobs = [job];
  let events: Record<string, unknown>[] = [];
  const hermes = {
    management: {
      request: async () => jobs,
    },
    gateway: () => ({
      rpc: async (_method: string, params: { name: string }) => ({
        output: params.name === 'nekodot-routine-context' ? '[]' : JSON.stringify(events),
      }),
    }),
  } as unknown as HermesRuntime;
  const routines = new Routines(db, hermes, new Notifications(db));
  await routines.drain();
  job.enabled = false;
  job.state = 'completed';
  events = [
    {
      phase: 'ended',
      botId,
      sessionId: 'once-session',
      admissionId: 'once-admission',
      route: null,
      jobId: 'once',
      requestId: null,
      text: 'Reminder completed',
      time: Date.now() / 1000,
      completed: true,
    },
  ];
  await routines.drain();
  const context = await routines.context(botId, 'ordinary-chat');
  expect(context.text).toContain('Reminder completed');
  expect(context.text).toContain('session=once-session');
  expect(
    db
      .messages(conversationId)
      .filter((m) => m.kind === 'routine')
      .map((m) => m.content.action),
  ).toEqual(['executed']);
  await routines.drain();
  expect(db.messages(conversationId).filter((m) => m.kind === 'routine')).toHaveLength(1);
  const later = { ...job, id: 'later', name: 'Later reminder', enabled: true, state: 'scheduled' };
  jobs.push(later);
  await routines.drain();
  later.enabled = false;
  later.state = 'paused';
  await routines.drain();
  expect(
    db
      .messages(conversationId)
      .filter((m) => m.kind === 'routine')
      .map((m) => m.content.action),
  ).toEqual(['executed', 'created', 'stopped']);
  await routines.close();
  db.db.close();
});

it('shows a cron approval in the Bot chat and answers that exact native admission', async () => {
  const db = new NodeDatabase(await mkdtemp(join(tmpdir(), 'nekodot-cron-approval-')));
  const botId = 'nk-abcdef',
    conversationId = randomUUID();
  db.putBot({
    botId,
    displayName: 'Routine Bot',
    handle: 'routine',
    role: '',
    model: 'qa',
    avatar: { shape: 'dot', color: '#E8603C' },
    archived: false,
    createdAt: new Date().toISOString(),
  });
  db.putConversation({ conversationId, botId, kind: 'dm', createdAt: new Date().toISOString() });
  nativeSession(db, botId, conversationId);
  const calls: { method: string; params: Record<string, unknown> }[] = [];
  const hermes = {
    management: {
      request: async () => [{ id: 'job', name: 'Report', prompt: 'Write report', enabled: true }],
    },
    gateway: () => ({
      rpc: async (method: string, params: Record<string, unknown>) => {
        if (method === 'command.dispatch') {
          expect(params.session_id).toBe('native-dm');
          return {
            output: JSON.stringify([
              {
                phase: 'started',
                botId,
                sessionId: 'cron-session',
                admissionId: 'admission-1',
                route: null,
                jobId: 'job',
                requestId: null,
                text: '',
                time: Date.now() / 1000,
              },
            ]),
          };
        }
        calls.push({ method, params });
        return method === 'cron.status'
          ? {
              prompts: [
                {
                  kind: 'approval',
                  prompt_id: 'prompt-1',
                  execution_generation: 4,
                  description: 'Run test command',
                  command: 'test',
                },
              ],
            }
          : { status: 'resolved', prompt_id: 'prompt-1' };
      },
    }),
  } as unknown as HermesRuntime;
  const routines = new Routines(db, hermes, new Notifications(db));
  await routines.drain();
  const approval = db.messages(conversationId).find((m) => m.kind === 'approval');
  expect(approval?.content).toMatchObject({ requestId: 'prompt-1', choices: ['once', 'deny'] });
  expect(calls[0]).toEqual({
    method: 'cron.status',
    params: {
      session_id: 'cron-session',
      admission_id: 'admission-1',
    },
  });
  await routines.approvalRespond(botId, 'cron:job:cron-session', 'prompt-1', 'once');
  expect(calls[1]).toEqual({
    method: 'cron.approve',
    params: {
      session_id: 'cron-session',
      admission_id: 'admission-1',
      execution_generation: 4,
      prompt_id: 'prompt-1',
      choice: 'once',
    },
  });
  expect(db.message(approval!.messageId)?.status).toBe('done');
  await routines.approvalRespond(botId, 'cron:job:cron-session', 'prompt-1', 'once');
  expect(calls.filter((call) => call.method === 'cron.approve')).toHaveLength(1);
  await expect(
    routines.approvalRespond(botId, 'cron:job:cron-session', 'prompt-1', 'deny'),
  ).rejects.toThrow('no longer pending');
  await routines.close();
  db.db.close();
});
