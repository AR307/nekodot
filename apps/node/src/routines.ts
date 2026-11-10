import { createHmac, randomBytes, randomUUID } from 'node:crypto';
import { createServer, type Server } from 'node:net';
import { chmod, mkdir, rename, stat } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { z } from 'zod';
import {
  routineInputSchema,
  cronApprovalPolicySchema,
  rpcContracts,
  type Routine,
  type RoutineInput,
  type RoutineExecution,
  type RoutineRoute,
  type RoutineDelivery,
  type RoutineReceipt,
  type CronApprovalPolicy,
  type Message,
} from '@nekodot/protocol';
import type { NativePrompt } from './execution/types';
import type { NodeDatabase } from './database';
import type { HermesRuntime } from './hermes/runtime';
import { runProfileCommand } from './hermes/session';
import type { Notifications } from './notifications';
import { NodeFault } from './fault';
import { isNamedPipe } from './bridge';
import { RoutineSecrets, routineDigest } from './routine-secrets';

interface StoredRoutine extends Routine {
  secret: string;
  nativeSecret: string;
  route: string;
}
const nativeEvent = z.object({
  phase: z.enum(['started', 'ended']),
  botId: z.string(),
  sessionId: z.string(),
  admissionId: z.string(),
  route: z.string().nullable(),
  jobId: z.string().nullable(),
  requestId: z.string().nullable(),
  text: z.string(),
  time: z.number(),
  completed: z.boolean().optional(),
  interrupted: z.boolean().optional(),
  failed: z.boolean().optional(),
  reason: z.string().optional(),
  generation: z.number().optional(),
  prompts: z
    .array(
      z.object({
        kind: z.enum(['approval', 'clarify']),
        prompt_id: z.string(),
        execution_generation: z.number(),
        description: z.string().optional(),
        command: z.string().optional(),
        question: z.string().optional(),
        choices: z.array(z.string()).optional(),
        multi_select: z.boolean().optional(),
      }),
    )
    .optional(),
});
const time = () => new Date().toISOString();

export class Routines {
  private secrets: RoutineSecrets;
  private server?: Server;
  private timer?: ReturnType<typeof setInterval>;
  private draining?: Promise<void>;
  private publicUrl = '';
  onError: (message: string) => void = () => {};
  scrub!: (botId: string, value: string) => string;
  onSecret?: (input: unknown) => Promise<unknown>;
  onTask?: (input: unknown) => Promise<unknown>;
  onExecution!: (
    routine: Routine,
    execution: RoutineExecution,
    conversationId: string,
    prompts: NativePrompt[],
    generation?: number,
  ) => Promise<void>;
  onRoutes: (routes: RoutineRoute[]) => Promise<void> = async () => {
    throw new NodeFault(
      'unavailable',
      'Relay is disconnected. Reconnect before changing webhook access.',
    );
  };
  constructor(
    readonly database: NodeDatabase,
    readonly hermes: HermesRuntime,
    private notifications: Notifications,
  ) {
    this.secrets = new RoutineSecrets(database.directory);
    database.db
      .exec(`CREATE TABLE IF NOT EXISTS routines(routine_id TEXT PRIMARY KEY,bot_id TEXT NOT NULL,data TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS routine_executions(execution_id TEXT PRIMARY KEY,routine_id TEXT NOT NULL,data TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS routine_receipts(id INTEGER PRIMARY KEY,routine_id TEXT NOT NULL,data TEXT NOT NULL);`);
  }
  private stored(id: string, botId?: string): StoredRoutine {
    const row = this.database.db.prepare('SELECT data FROM routines WHERE routine_id=?').get(id);
    if (!row) throw new NodeFault('not_found', 'Routine not found');
    const result = JSON.parse(String(row.data)) as StoredRoutine;
    if (botId && result.botId !== botId)
      throw new NodeFault('not_found', 'Routine not found in this Bot');
    this.bot(result.botId);
    return result;
  }
  private bot(id: string) {
    const bot = this.database.bot(id);
    if (!bot || bot.archived) throw new NodeFault('not_found', 'Bot is not active');
    return bot;
  }
  private all(): StoredRoutine[] {
    return this.database.db
      .prepare('SELECT data FROM routines')
      .all()
      .map((r) => JSON.parse(String(r.data)) as StoredRoutine);
  }
  private view(row: StoredRoutine): Routine {
    const { secret, nativeSecret, route, ...view } = row;
    void secret;
    void nativeSecret;
    void route;
    return { ...view, url: this.publicUrl + '/hooks/' + row.routineId };
  }
  private save(row: StoredRoutine) {
    this.database.db
      .prepare(
        'INSERT INTO routines VALUES(?,?,?) ON CONFLICT(routine_id) DO UPDATE SET data=excluded.data',
      )
      .run(row.routineId, row.botId, JSON.stringify(row));
  }
  routes(): RoutineRoute[] {
    return this.all().map((r) => ({
      routineId: r.routineId,
      botId: r.botId,
      digest: routineDigest(this.secrets.open(r.secret)),
      enabled: r.enabled && !this.database.bot(r.botId)?.archived,
    }));
  }
  async syncRoutes() {
    await this.onRoutes(this.routes());
  }
  async list(botId: string) {
    this.bot(botId);
    const [jobs, hooks, config] = await Promise.all([
      this.hermes.management.request<Record<string, unknown>[]>('/api/cron/jobs', botId),
      this.hermes.management.request<{ subscriptions: Record<string, unknown>[] }>(
        '/api/webhooks',
        'default',
      ),
      this.hermes.management.request<{
        approvals?: {
          mode?: string;
          cron_mode?: string;
          cron_policies?: Record<string, CronApprovalPolicy>;
        };
        platform_toolsets?: Record<string, string[]>;
      }>('/api/config?include_defaults=true', botId),
    ]);
    const rows = this.all().filter((r) => r.botId === botId);
    for (const row of rows) {
      const native = hooks.subscriptions.find((h) => h.name === row.route);
      row.native = {
        ...native,
        ...(row.cronJobId ? { schedule: jobs.find((j) => j.id === row.cronJobId) } : {}),
      };
      row.permissions = row.cronJobId
        ? `Hermes cron · task approval policy · ${String((row.native.schedule && (row.native.schedule as Record<string, unknown>).enabled_toolsets) || 'native cron toolsets')}`
        : `Hermes webhook · approvals.mode=${config.approvals?.mode ?? 'native default'} · ${(config.platform_toolsets?.webhook ?? ['hermes-webhook']).join(', ')}`;
      // Hermes is authoritative, including edits made through its own CLI.
      row.enabled = row.enabled && native?.enabled === true;
      if (native) {
        row.description = String(native.description ?? row.description);
        row.prompt = String(native.prompt ?? row.prompt);
        row.events = native.events as string[];
        row.skills = native.skills as string[];
      }
    }
    const linked = new Set(rows.map((r) => r.cronJobId));
    const schedules: Routine[] = jobs
      .filter((j) => !linked.has(String(j.id)))
      .map((job) => ({
        routineId: 'cron:' + String(job.id),
        botId,
        name: String(job.name ?? job.id),
        description: String(job.prompt ?? ''),
        prompt: String(job.prompt ?? ''),
        events: [],
        skills: [],
        trigger: 'schedule',
        cronJobId: String(job.id),
        enabled: job.enabled !== false,
        granted: false,
        url: '',
        createdAt: String(job.created_at ?? ''),
        permissions: 'Hermes native cron / task approval policy',
        native: {
          ...job,
          approvalPolicy: config.approvals?.cron_policies?.[String(job.id)] ?? null,
        },
      }));
    for (const row of rows)
      if (row.cronJobId)
        row.native = {
          ...row.native,
          approvalPolicy: config.approvals?.cron_policies?.[row.cronJobId] ?? null,
        };
    return { routines: [...rows.map((r) => this.view(r)), ...schedules] };
  }
  async get(botId: string, id: string) {
    if (id.startsWith('cron:')) {
      const routine = (await this.list(botId)).routines.find((r) => r.routineId === id);
      if (!routine) throw new NodeFault('not_found', 'Scheduled routine not found');
      const native = await this.hermes.management.request<{ runs: Record<string, unknown>[] }>(
        '/api/cron/jobs/' + encodeURIComponent(routine.cronJobId!) + '/runs?limit=20',
        botId,
      );
      await this.drain();
      return {
        routine: { ...routine, native: { ...routine.native, runs: native.runs } },
        executions: this.database.db
          .prepare(
            'SELECT data FROM routine_executions WHERE routine_id=? ORDER BY rowid DESC LIMIT 100',
          )
          .all(id)
          .map((row) => JSON.parse(String(row.data)) as RoutineExecution),
        receipts: [],
      };
    }
    const routine = (await this.list(botId)).routines.find((r) => r.routineId === id);
    if (!routine) throw new NodeFault('not_found', 'Routine not found in this Bot');
    if (routine.cronJobId) {
      const native = await this.hermes.management.request<{ runs: Record<string, unknown>[] }>(
        '/api/cron/jobs/' + encodeURIComponent(routine.cronJobId) + '/runs?limit=20',
        botId,
      );
      routine.native = { ...routine.native, runs: native.runs };
    }
    await this.drain();
    const executions = this.database.db
      .prepare(
        'SELECT data FROM routine_executions WHERE routine_id=? ORDER BY rowid DESC LIMIT 100',
      )
      .all(id)
      .map((row) => JSON.parse(String(row.data)) as RoutineExecution);
    const receipts = this.database.db
      .prepare('SELECT data FROM routine_receipts WHERE routine_id=? ORDER BY id DESC LIMIT 100')
      .all(id)
      .map((row) => JSON.parse(String(row.data)) as Record<string, unknown>);
    return { routine, executions, receipts };
  }
  private async subscribe(row: StoredRoutine) {
    const args = [
      'webhook',
      'subscribe',
      row.route,
      '--route-profile',
      row.botId,
      '--description',
      row.description,
      '--prompt',
      row.prompt,
      '--events',
      row.events.join(','),
      '--skills',
      row.skills.join(','),
    ];
    if (row.cronJobId) args.push('--cron-job', row.cronJobId);
    const output = await this.hermes.cli('default', args);
    const secret = output.match(/Secret:\s+(\S+)/)?.[1];
    if (!secret)
      throw new NodeFault('unavailable', 'Hermes did not create the native webhook subscription');
    row.nativeSecret = this.secrets.seal(secret);
    await this.hermes.management.request('/api/webhooks/' + row.route + '/enabled', 'default', {
      method: 'PUT',
      body: JSON.stringify({ enabled: row.enabled }),
    });
  }
  async create(input: RoutineInput, conversationId?: string) {
    this.bot(input.botId);
    if (!this.hermes.webhookUrl)
      throw new NodeFault('unavailable', 'Native webhook transport is not available');
    if (input.cronJobId) {
      const { routines } = await this.list(input.botId);
      if (routines.some((r) => r.cronJobId === input.cronJobId && r.trigger === 'both'))
        throw new NodeFault('conflict', 'This scheduled task already has a webhook');
      if (!routines.some((r) => r.cronJobId === input.cronJobId))
        throw new NodeFault('not_found', 'Scheduled task is not in this Bot');
    }
    const id = randomUUID();
    const row: StoredRoutine = {
      ...input,
      routineId: id,
      conversationId,
      trigger: input.cronJobId ? 'both' : 'webhook',
      enabled: false,
      granted: false,
      url: '',
      createdAt: time(),
      permissions: input.cronJobId
        ? 'Hermes native cron / approvals.cron_mode'
        : 'Hermes native webhook tools / approvals',
      secret: this.secrets.seal(randomBytes(32).toString('base64url')),
      nativeSecret: '',
      route: 'nk-' + id,
    };
    await this.subscribe(row);
    this.save(row);
    this.card(row, 'created', undefined, conversationId);
    await this.syncRoutes();
    return this.view(row);
  }
  async update(input: RoutineInput & { routineId: string }) {
    const old = this.stored(input.routineId, input.botId);
    if (input.cronJobId !== old.cronJobId)
      throw new NodeFault('invalid_params', 'The native scheduled task binding cannot be changed');
    const row = { ...old, ...input };
    await this.subscribe(row);
    this.save(row);
    this.card(row, 'updated');
    return this.view(row);
  }
  private card(
    row: Routine,
    action:
      | 'created'
      | 'updated'
      | 'enabled'
      | 'stopped'
      | 'started'
      | 'executed'
      | 'failed'
      | 'credentials' = 'created',
    executionId?: string,
    conversationId?: string,
  ) {
    const card = action === 'credentials' ? 'credentials' : 'task';
    const conversation = this.database
      .conversations()
      .find((c) => c.kind === 'dm' && c.botId === row.botId)!;
    const message: Message = {
      messageId: executionId
        ? 'routine-status:' + executionId
        : 'routine:' + row.routineId + ':' + randomUUID(),
      conversationId: conversationId ?? row.conversationId ?? conversation.conversationId,
      seq: this.database.head(),
      author: { type: 'bot', id: row.botId },
      kind: 'routine',
      status: 'done',
      createdAt: time(),
      content: {
        routineId: row.routineId,
        botId: row.botId,
        name: row.name,
        trigger: row.trigger,
        granted: row.granted,
        card,
        ...(action !== 'credentials' ? { action } : {}),
        ...(executionId ? { executionId } : {}),
      },
    };
    this.database.putMessage(message);
  }
  credentials(botId: string, id: string) {
    const row = this.stored(id, botId);
    return { url: this.view(row).url, secret: this.secrets.open(row.secret) };
  }
  async enable(botId: string, id: string, enabled: boolean, grant = false) {
    const row = this.stored(id, botId);
    if (grant) row.granted = true;
    if (enabled && !row.granted)
      throw new NodeFault('forbidden', 'Approve secure credential delivery first');
    await this.hermes.management.request('/api/webhooks/' + row.route + '/enabled', 'default', {
      method: 'PUT',
      body: JSON.stringify({ enabled }),
    });
    row.enabled = enabled;
    this.save(row);
    await this.syncRoutes();
    this.card(row, enabled ? 'enabled' : 'stopped');
    if (grant) this.card(row, 'credentials');
    return this.view(row);
  }
  async rotate(botId: string, id: string) {
    const row = this.stored(id, botId);
    row.secret = this.secrets.seal(randomBytes(32).toString('base64url'));
    this.save(row);
    await this.syncRoutes();
    return this.view(row);
  }
  async send(
    botId: string,
    id: string,
    payload: Record<string, unknown>,
    requestId: string,
  ): Promise<RoutineReceipt> {
    const row = this.stored(id, botId);
    if (!row.granted || !row.enabled)
      throw new NodeFault(
        'forbidden',
        'Open the routine in nekodot and approve secure credential delivery first',
      );
    const url = this.view(row).url;
    if (!url.startsWith('https://'))
      throw new NodeFault('unavailable', 'A public HTTPS Relay URL is required');
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer ' + this.secrets.open(row.secret),
        'Content-Type': 'application/json',
        'X-Request-ID': requestId,
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(30_000),
    });
    return { status: response.status, body: (await response.json()) as Record<string, unknown> };
  }
  async deliver(input: RoutineDelivery): Promise<RoutineReceipt> {
    const row = this.stored(input.routineId);
    if (!row.enabled || input.digest !== routineDigest(this.secrets.open(row.secret)))
      return { status: 403, body: { error: 'Webhook is disabled or credential was rotated' } };
    const timestamp = String(Math.floor(Date.now() / 1000));
    const signature = createHmac('sha256', this.secrets.open(row.nativeSecret))
      .update(timestamp + '.' + input.body)
      .digest('hex');
    const response = await fetch(
      this.hermes.webhookUrl + '/p/' + row.botId + '/webhooks/' + row.route,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Request-ID': input.requestId,
          'X-Webhook-Timestamp': timestamp,
          'X-Webhook-Signature-V2': signature,
        },
        body: input.body,
        signal: AbortSignal.timeout(25_000),
      },
    );
    const receipt = {
      status: response.status,
      body: (await response.json()) as Record<string, unknown>,
    };
    this.database.db
      .prepare('INSERT INTO routine_receipts(routine_id,data) VALUES(?,?)')
      .run(
        row.routineId,
        JSON.stringify({ ...receipt, requestId: input.requestId, receivedAt: time() }),
      );
    return receipt;
  }
  setPublicUrl(publicUrl: string) {
    this.publicUrl = publicUrl.replace(/\/$/, '');
  }
  /** Serves the Hermes plugin bridge at the address written into each profile config. */
  async start(path: string) {
    if (!isNamedPipe(path)) {
      await mkdir(dirname(path), { recursive: true, mode: 0o700 });
      // Retain the stale socket inode rather than deleting user files.
      if (
        await stat(path).then(
          () => true,
          () => false,
        )
      ) {
        const retained = join(this.database.directory, 'retained-routine-sockets');
        await mkdir(retained, { recursive: true, mode: 0o700 });
        await rename(path, join(retained, String(Date.now()) + '.sock'));
      }
    }
    this.server = createServer((socket) => {
      let input = '';
      socket.on('data', (chunk) => {
        input += chunk.toString();
        if (Buffer.byteLength(input) > 1_048_576) return socket.destroy();
        if (!input.endsWith('\n')) return;
        socket.pause();
        void Promise.resolve()
          .then(() => this.local(JSON.parse(input)))
          .then(
            (result) => socket.end(JSON.stringify({ ok: true, result }) + '\n'),
            (error) =>
              socket.end(
                JSON.stringify({
                  ok: false,
                  error:
                    error instanceof NodeFault
                      ? error.message
                      : error instanceof z.ZodError
                        ? error.issues.map((issue) => issue.message).join('; ')
                        : 'Routine operation failed',
                }) + '\n',
              ),
          );
      });
      socket.on('error', () => {});
    });
    await new Promise<void>((resolve, reject) => {
      this.server!.once('error', reject);
      this.server!.listen(path, resolve);
    });
    if (!isNamedPipe(path)) await chmod(path, 0o600);
    await this.drain();
    this.timer = setInterval(() => {
      void this.drain().catch(() =>
        this.onError(
          'Could not read native routine results. They remain in the Hermes profile history.',
        ),
      );
    }, 5000);
  }
  private async local(value: unknown) {
    if (value && typeof value === 'object' && 'action' in value && value.action === 'task') {
      if (!this.onTask) throw new NodeFault('unavailable', 'Task coordination is unavailable');
      return this.onTask(value);
    }
    if (value && typeof value === 'object' && 'action' in value && value.action === 'secret') {
      if (!this.onSecret)
        throw new NodeFault('unavailable', 'Confidential delivery is unavailable');
      return this.onSecret(value);
    }
    const base = z
      .object({
        action: z.enum(['create', 'update', 'get', 'list', 'send', 'approvalPolicy']),
        botId: z.string(),
        sessionId: z.string().optional(),
      })
      .parse(value);
    this.bot(base.botId);
    const params = { ...(value as Record<string, unknown>) };
    delete params.action;
    delete params.sessionId;
    switch (base.action) {
      case 'approvalPolicy': {
        const p = z
          .strictObject({
            botId: z.string(),
            routineId: z.string().min(1),
            policy: cronApprovalPolicySchema,
          })
          .parse(params);
        return this.approvalPolicy(p.botId, p.routineId, p.policy);
      }
      case 'create': {
        const run = this.database
          .runs()
          .find(
            (r) =>
              r.botId === base.botId &&
              base.sessionId &&
              (r.sessionId === base.sessionId || r.storedSessionId === base.sessionId),
          );
        const routine = await this.create(routineInputSchema.parse(params), run?.conversationId);
        return {
          ...routine,
          nextAction:
            'Ask the user to open the Webhook button in the created routine card and confirm the connection. It is disabled until they approve. Never request the secret in ordinary chat.',
        };
      }
      case 'update':
        return this.update(rpcContracts['routines.update'].params.parse(params));
      case 'list':
        return this.list(base.botId);
      case 'get': {
        const p = rpcContracts['routines.get'].params.parse(params);
        return this.get(p.botId, p.routineId);
      }
      case 'send': {
        const p = rpcContracts['routines.test'].params.parse(params);
        return this.send(p.botId, p.routineId, p.payload, p.requestId);
      }
    }
  }
  drain() {
    return (this.draining ??= this.collect().finally(() => {
      this.draining = undefined;
    }));
  }
  private async collect() {
    const hooks = this.all();
    for (const bot of this.database.allBots().filter((b) => !b.archived)) {
      const botId = bot.botId;
      const jobs = await this.hermes.management.request<Record<string, unknown>[]>(
        '/api/cron/jobs',
        botId,
      );
      const snapshot = jobs.map((job) => ({
        id: String(job.id),
        name: String(job.name ?? job.id),
        prompt: String(job.prompt ?? ''),
        schedule: job.schedule,
        enabled: job.enabled !== false,
      }));
      const previous = this.database.setting<typeof snapshot>('routine-schedules:' + botId);
      const routines: Routine[] = hooks.filter((r) => r.botId === botId);
      for (const job of jobs) {
        const routine: Routine = routines.find((r) => r.cronJobId === job.id) ?? {
          routineId: 'cron:' + String(job.id),
          botId,
          name: String(job.name ?? job.id),
          description: String(job.prompt ?? ''),
          prompt: String(job.prompt ?? ''),
          events: [],
          skills: [],
          trigger: 'schedule',
          cronJobId: String(job.id),
          enabled: job.enabled !== false,
          granted: false,
          url: '',
          createdAt: String(job.created_at ?? ''),
          permissions: 'Hermes native cron / task approval policy',
          native: job,
        };
        if (!routines.includes(routine)) routines.push(routine);
        const saved = previous?.find((p) => p.id === job.id);
        const current = snapshot.find((p) => p.id === job.id)!;
        // Completing a one-shot disables it natively; that is execution, not a user stop.
        if (
          previous &&
          job.state !== 'completed' &&
          JSON.stringify(saved) !== JSON.stringify(current)
        )
          this.card(routine, !saved ? 'created' : !current.enabled ? 'stopped' : 'updated');
      }
      this.database.setSetting('routine-schedules:' + botId, snapshot);
      if (!routines.length) continue;
      const ids = new Set(routines.map((r) => r.routineId));
      const settled = this.database.db
        .prepare(
          `SELECT data FROM routine_executions WHERE json_extract(data,'$.state') NOT IN ('running','waiting_approval','waiting_question')`,
        )
        .all()
        .map((r) => JSON.parse(String(r.data)) as RoutineExecution)
        .filter((r) => ids.has(r.routineId))
        .map((r) => r.sessionId);
      const result = await runProfileCommand(
        this.database,
        this.hermes,
        botId,
        'nekodot-routine-status',
        { settled },
      );
      const events = z.array(nativeEvent).parse(JSON.parse(result.output));
      for (const event of events) {
        if (event.botId !== botId) throw new Error('Routine event has the wrong profile');
        if (event.phase === 'started') {
          const snapshot = await this.hermes.gateway(botId).rpc<{
            execution_generation: number;
            prompts?: NativePrompt[];
          }>(event.jobId ? 'cron.status' : 'session.resume', event.jobId ? { session_id: event.sessionId, admission_id: event.admissionId } : { session_id: event.sessionId, omit_messages: true, defer_history: true });
          event.prompts = snapshot.prompts;
          event.generation = snapshot.execution_generation;
        }
        const routine = routines.find(
          (r) =>
            r.botId === botId &&
            (event.route
              ? hooks.some((h) => h.routineId === r.routineId && h.route === event.route)
              : r.cronJobId === event.jobId),
        );
        if (routine) await this.record(routine, event);
      }
    }
  }
  private async record(routine: Routine, event: z.infer<typeof nativeEvent>) {
    const id = routine.routineId + ':' + event.sessionId;
    const old = this.database.db
      .prepare('SELECT data FROM routine_executions WHERE execution_id=?')
      .get(id);
    const previous = old ? (JSON.parse(String(old.data)) as RoutineExecution) : undefined;
    if (
      previous &&
      !['running', 'waiting_approval', 'waiting_question'].includes(previous.state) &&
      this.database.message('routine-result:' + id)
    )
      return;
    // Native admission verdicts include failures that occur before agent/session hooks run.
    const state =
      previous && !['running', 'waiting_approval', 'waiting_question'].includes(previous.state)
        ? previous.state
        : event.phase === 'ended'
          ? event.interrupted
            ? 'cancelled'
            : event.completed && !event.failed
              ? 'completed'
              : 'failed'
          : 'running';
    const execution: RoutineExecution = {
      executionId: id,
      routineId: routine.routineId,
      sessionId: event.sessionId,
      admissionId: event.admissionId,
      ...(routine.native?.origin &&
      typeof (routine.native.origin as Record<string, unknown>).chat_id === 'string'
        ? { originSessionId: String((routine.native.origin as Record<string, unknown>).chat_id) }
        : {}),
      ...(event.requestId ? { requestId: event.requestId } : {}),
      state:
        state === 'running' && event.prompts?.length
          ? event.prompts[0]!.kind === 'clarify'
            ? 'waiting_question'
            : 'waiting_approval'
          : state,
      text: this.scrub(routine.botId, event.text || previous?.text || ''),
      ...(event.reason ? { reason: this.scrub(routine.botId, event.reason) } : {}),
      updatedAt: new Date(event.time * 1000).toISOString(),
    };
    this.database.db
      .prepare(
        'INSERT INTO routine_executions VALUES(?,?,?) ON CONFLICT(execution_id) DO UPDATE SET data=excluded.data',
      )
      .run(id, routine.routineId, JSON.stringify(execution));
    const owner = execution.originSessionId
      ? this.database.db
          .prepare(
            "SELECT conversation_id FROM usage_owners WHERE profile=? AND kind='session' AND id=?",
          )
          .get(routine.botId, execution.originSessionId)
      : undefined;
    const conversationId =
      routine.conversationId ??
      (owner ? String(owner.conversation_id) : undefined) ??
      this.database.conversations().find((c) => c.kind === 'dm' && c.botId === routine.botId)!
        .conversationId;
    if (
      previous?.state !== execution.state &&
      !['waiting_approval', 'waiting_question'].includes(execution.state)
    )
      this.card(
        routine,
        state === 'running'
          ? 'started'
          : state === 'completed'
            ? 'executed'
            : state === 'cancelled'
              ? 'stopped'
              : 'failed',
        id,
        conversationId,
      );
    if (state !== 'running') {
      this.database.putMessage({
        messageId: 'routine-result:' + id,
        nativeSessionId: event.sessionId,
        taskId: 'routine-task:' + id,
        taskRole: 'execution',
        conversationId,
        seq: this.database.head(),
        author: { type: 'bot', id: routine.botId },
        kind: 'text',
        createdAt: execution.updatedAt,
        status: state === 'completed' ? 'done' : state === 'cancelled' ? 'cancelled' : 'failed',
        content: {
          text: execution.text,
          routine: { routineId: routine.routineId, executionId: id, sessionId: event.sessionId },
          ...(state === 'failed'
            ? {
                failureReason:
                  execution.reason ||
                  'Native background execution failed. The task was not restarted.',
              }
            : {}),
        },
      });
    }
    await this.onExecution(
      routine,
      execution,
      conversationId,
      event.prompts ?? [],
      event.generation,
    );
  }
  async close() {
    clearInterval(this.timer);
    await this.drain();
    if (this.server) await new Promise<void>((resolve) => this.server!.close(() => resolve()));
  }

  execution(botId: string, executionId: string) {
    this.bot(botId);
    const row = this.database.db
      .prepare(
        "SELECT e.data FROM routine_executions e JOIN dot_tasks t ON json_extract(t.data,'$.routineExecutionId')=e.execution_id WHERE e.execution_id=? AND json_extract(t.data,'$.botId')=?",
      )
      .get(executionId, botId);
    if (!row) throw new NodeFault('not_found', 'Routine execution not found in this Bot');
    return JSON.parse(String(row.data)) as RoutineExecution;
  }

  private async approvalPolicy(botId: string, routineId: string, policy: CronApprovalPolicy) {
    const routine = await this.get(botId, routineId);
    const jobId = routine.routine.cronJobId;
    if (!jobId) throw new NodeFault('invalid_params', 'This task has no schedule');
    const result = await runProfileCommand(
      this.database,
      this.hermes,
      botId,
      'nekodot-cron-approval-policy',
      { jobId, policy },
    );
    return JSON.parse(result.output) as CronApprovalPolicy;
  }
}
