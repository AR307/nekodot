import { createHmac, randomBytes, randomUUID } from 'node:crypto';
import { createServer, type Server } from 'node:net';
import { chmod, mkdir, readdir, readFile, rename, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { z } from 'zod';
import {
  routineInputSchema,
  rpcContracts,
  type Routine,
  type RoutineInput,
  type RoutineExecution,
  type RoutineRoute,
  type RoutineDelivery,
  type RoutineReceipt,
  type Message,
} from '@nekodot/protocol';
import type { NodeDatabase } from './database';
import type { HermesRuntime } from './hermes/runtime';
import type { Notifications } from './notifications';
import { NodeFault } from './fault';
import { RoutineSecrets, routineDigest } from './routine-secrets';

interface StoredRoutine extends Routine {
  secret: string;
  nativeSecret: string;
  route: string;
}
const nativeEvent = z.object({
  phase: z.enum(['started', 'response', 'ended']),
  botId: z.string(),
  sessionId: z.string(),
  route: z.string().nullable(),
  jobId: z.string().nullable(),
  requestId: z.string().nullable(),
  text: z.string(),
  time: z.number(),
  completed: z.boolean().optional(),
  interrupted: z.boolean().optional(),
  failed: z.boolean().optional(),
  reason: z.string().optional(),
});
const time = () => new Date().toISOString();

export class Routines {
  private secrets: RoutineSecrets;
  private server?: Server;
  private timer?: ReturnType<typeof setInterval>;
  private draining?: Promise<void>;
  private publicUrl = '';
  onError: (message: string) => void = () => {};
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
        approvals?: { mode?: string; cron_mode?: string };
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
        ? `Hermes cron · approvals.cron_mode=${config.approvals?.cron_mode ?? config.approvals?.mode ?? 'native default'} · ${String((row.native.schedule && (row.native.schedule as Record<string, unknown>).enabled_toolsets) || 'native cron toolsets')}`
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
        permissions: 'Hermes native cron / approvals.cron_mode',
        native: job,
      }));
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
      return {
        routine: { ...routine, native: { ...routine.native, runs: native.runs } },
        executions: [],
        receipts: [],
      };
    }
    const routine = (await this.list(botId)).routines.find((r) => r.routineId === id);
    if (!routine) throw new NodeFault('not_found', 'Routine not found in this Bot');
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
  async create(input: RoutineInput) {
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
    this.card(row);
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
    this.card(row);
    return this.view(row);
  }
  private card(row: StoredRoutine, card: 'task' | 'credentials' = 'task') {
    const conversation = this.database
      .conversations()
      .find((c) => c.kind === 'dm' && c.botId === row.botId)!;
    const message: Message = {
      messageId: 'routine:' + card + ':' + row.routineId,
      conversationId: conversation.conversationId,
      seq: this.database.head(),
      author: { type: 'bot', id: row.botId },
      kind: 'routine',
      status: 'done',
      createdAt: row.createdAt,
      content: {
        routineId: row.routineId,
        botId: row.botId,
        name: row.name,
        granted: row.granted,
        card,
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
    this.card(row);
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
  async start() {
    const path = join(this.database.directory, 'routines.sock');
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
                  error: error instanceof NodeFault ? error.message : 'Routine operation failed',
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
    await chmod(path, 0o600);
    await this.drain();
    this.timer = setInterval(() => {
      void this.drain().catch(() =>
        this.onError(
          'Could not collect native routine results. They remain in the profile outbox.',
        ),
      );
    }, 5000);
  }
  private async local(value: unknown) {
    const base = z
      .object({
        action: z.enum(['create', 'update', 'get', 'list', 'send', 'drain']),
        botId: z.string(),
      })
      .parse(value);
    this.bot(base.botId);
    const params = { ...(value as Record<string, unknown>) };
    delete params.action;
    switch (base.action) {
      case 'create':
        return this.create(routineInputSchema.parse(params));
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
      case 'drain':
        await this.drain();
        return {};
    }
  }
  drain() {
    return (this.draining ??= this.collect().finally(() => {
      this.draining = undefined;
    }));
  }
  private async collect() {
    for (const bot of this.database.allBots()) {
      const directory = join(
        this.hermes.profileHome(bot.botId),
        'plugin-data',
        'nekodot-routines',
        'outbox',
      );
      const files = await readdir(directory).catch(() => []);
      for (const file of files.filter((f) => f.endsWith('.json')).sort()) {
        const event = nativeEvent.parse(JSON.parse(await readFile(join(directory, file), 'utf8')));
        if (event.botId !== bot.botId) throw new Error('Routine event has the wrong profile');
        const routine = this.all().find(
          (r) =>
            r.botId === bot.botId &&
            (event.route ? r.route === event.route : r.cronJobId === event.jobId),
        );
        if (routine) this.record(routine, event);
        const retained = join(this.database.directory, 'routine-deliveries', bot.botId);
        await mkdir(retained, { recursive: true, mode: 0o700 });
        await rename(join(directory, file), join(retained, file));
      }
    }
  }
  private record(routine: StoredRoutine, event: z.infer<typeof nativeEvent>) {
    const id = routine.routineId + ':' + event.sessionId;
    const old = this.database.db
      .prepare('SELECT data FROM routine_executions WHERE execution_id=?')
      .get(id);
    const previous = old ? (JSON.parse(String(old.data)) as RoutineExecution) : undefined;
    if (previous && previous.state !== 'running' && this.database.message('routine-result:' + id))
      return;
    // post_llm_call provides text, not a success verdict. Only Hermes' end hook settles the turn.
    const state =
      previous && previous.state !== 'running'
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
      ...(event.requestId ? { requestId: event.requestId } : {}),
      state,
      text: event.text || previous?.text || '',
      ...(event.reason ? { reason: event.reason } : {}),
      updatedAt: new Date(event.time * 1000).toISOString(),
    };
    this.database.db
      .prepare(
        'INSERT INTO routine_executions VALUES(?,?,?) ON CONFLICT(execution_id) DO UPDATE SET data=excluded.data',
      )
      .run(id, routine.routineId, JSON.stringify(execution));
    if (state === 'running') return;
    const conversation = this.database
      .conversations()
      .find((c) => c.kind === 'dm' && c.botId === routine.botId)!;
    const message: Message = {
      messageId: 'routine-result:' + id,
      conversationId: conversation.conversationId,
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
                event.reason || 'Native background execution failed. The task was not restarted.',
            }
          : {}),
      },
    };
    this.database.putMessage(message);
    if (state !== 'cancelled')
      this.notifications.send({
        notificationId: 'routine:' + id,
        conversationId: conversation.conversationId,
        kind: state === 'completed' ? 'completed' : 'failed',
      });
  }
  async close() {
    clearInterval(this.timer);
    await this.drain();
    if (this.server) await new Promise<void>((resolve) => this.server!.close(() => resolve()));
  }

  /** Add native session references to the next input, never mutate a cached conversation prefix. */
  context(botId: string) {
    const since = this.database.setting<string>('routine-context:' + botId) ?? '';
    const results = this.database.db
      .prepare(
        `SELECT e.data FROM routine_executions e
      JOIN routines r ON r.routine_id=e.routine_id WHERE r.bot_id=?
      AND json_extract(e.data,'$.state')!='running' AND json_extract(e.data,'$.updatedAt')>?
      ORDER BY json_extract(e.data,'$.updatedAt') DESC LIMIT 10`,
      )
      .all(botId, since)
      .map((r) => JSON.parse(String(r.data)) as RoutineExecution);
    return {
      until: results[0]?.updatedAt,
      text: results.length
        ? '\n\n[Background routine results, not a request to rerun them. For follow-up, inspect the original Hermes session with session_search.]\n' +
          results
            .map((r) => `routine=${r.routineId} session=${r.sessionId} state=${r.state}\n${r.text}`)
            .join('\n\n')
        : '',
    };
  }
}
