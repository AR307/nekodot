import { randomUUID } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { parseDocument } from 'yaml';
import { z } from 'zod';
import {
  secretSpecSchema,
  type SavedSecret,
  type SecretEnvelope,
  type SecretRequest,
  type SecretSpec,
} from '@nekodot/protocol';
import type { NodeDatabase, RunRecord } from './database';
import type { HermesRuntime } from './hermes/runtime';
import { BotSecretKeys, secretContext } from './secret-crypto';
import { NodeFault } from './fault';

interface StoredRequest extends SecretRequest {
  nativeRequestId?: string;
  continuationId?: string;
  replaceId?: string;
  vaultId?: string;
  completed?: boolean;
  originatingRunId?: string;
}
interface StoredCredential extends SavedSecret {
  sealed?: string;
  vaultId?: string;
}
const timestamp = () => new Date().toISOString();
const actionable = (r: SecretRequest) => ['pending', 'redelivery', 'failed'].includes(r.state);

/** Product association and transport only; Hermes owns native waiting, queueing and vault. */
export class BotSecrets {
  private keys: BotSecretKeys;
  private nodeId = '';
  private temporary = new Map<string, Record<string, string>>();
  private waiting = new Map<string, (value: unknown) => void>();
  private submitting = new Map<string, Promise<SecretRequest>>();
  private attached = new Map<string, () => void>();
  onRequestCard: (request: SecretRequest) => void = () => {};
  onWaiting: (run: RunRecord, waiting: boolean) => void = () => {};
  onContinue: (request: SecretRequest, submissionId: string, text: string) => Promise<void> =
    async () => {
      throw new NodeFault('unavailable', 'The original Hermes session is unavailable');
    };
  constructor(
    private db: NodeDatabase,
    private hermes: HermesRuntime,
  ) {
    this.keys = new BotSecretKeys(db.directory);
    const credentials = join(db.directory, 'node.json');
    if (existsSync(credentials)) this.nodeId = JSON.parse(readFileSync(credentials, 'utf8')).nodeId;
    db.db
      .exec(`CREATE TABLE IF NOT EXISTS secret_requests(id TEXT PRIMARY KEY,bot_id TEXT NOT NULL,data TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS bot_credentials(id TEXT PRIMARY KEY,bot_id TEXT NOT NULL,data TEXT NOT NULL);`);
    for (const request of this.requests()) {
      if (request.nativeRequestId && (actionable(request) || request.state === 'delivered')) {
        request.state = 'expired';
        request.result = 'Hermes restarted. Request the native secret again.';
        this.persist(request);
      } else if (
        !request.saved &&
        !request.completed &&
        ['delivered', 'applied'].includes(request.state)
      ) {
        request.state = 'redelivery';
        request.result =
          'Temporary values were cleared on Node restart. Deliver again if still needed; existing target configuration was retained.';
        this.persist(request);
      }
    }
    for (const bot of db.bots()) if (!bot.archived) this.attach(bot.botId);
  }
  bind(nodeId: string) {
    this.nodeId = nodeId;
  }
  async recover() {
    for (const request of this.requests().filter(
      (r) => !r.saved && r.vaultId && (['redelivery', 'failed'].includes(r.state) || r.completed),
    )) {
      await this.hermes.management.rpc('vault.remove', {
        profile: request.botId,
        id: request.vaultId,
      });
      delete request.vaultId;
      this.persist(request);
    }
  }
  private bot(botId: string) {
    const bot = this.db.bot(botId);
    if (!bot || bot.archived) throw new NodeFault('not_found', 'Bot is not active');
    return bot;
  }
  private requests(): StoredRequest[] {
    return this.db.db
      .prepare('SELECT data FROM secret_requests')
      .all()
      .map((r) => JSON.parse(String(r.data)));
  }
  private request(botId: string, id: string): StoredRequest {
    this.bot(botId);
    const row = this.db.db
      .prepare('SELECT data FROM secret_requests WHERE id=? AND bot_id=?')
      .get(id, botId);
    if (!row) throw new NodeFault('not_found', 'Secret request not found in this Bot');
    return JSON.parse(String(row.data));
  }
  private credentials(botId: string): StoredCredential[] {
    return this.db.db
      .prepare('SELECT data FROM bot_credentials WHERE bot_id=?')
      .all(botId)
      .map((r) => JSON.parse(String(r.data)));
  }
  private credential(botId: string, id: string) {
    const entry = this.credentials(botId).find((c) => c.credentialId === id && c.enabled);
    if (!entry) throw new NodeFault('not_found', 'Saved credential is unavailable in this Bot');
    return entry;
  }
  private saveCredential(entry: StoredCredential) {
    this.db.db
      .prepare(
        'INSERT INTO bot_credentials VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data',
      )
      .run(entry.credentialId, entry.botId, JSON.stringify(entry));
  }
  private view(request: StoredRequest): SecretRequest {
    const {
      nativeRequestId,
      continuationId,
      replaceId,
      vaultId,
      completed,
      originatingRunId,
      ...view
    } = request;
    void nativeRequestId;
    void continuationId;
    void replaceId;
    void vaultId;
    void completed;
    void originatingRunId;
    return view;
  }
  private persist(request: StoredRequest) {
    request.updatedAt = timestamp();
    this.db.db
      .prepare(
        'INSERT INTO secret_requests VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data',
      )
      .run(request.requestId, request.botId, JSON.stringify(request));
    this.db.putMessage({
      messageId: 'secret:' + request.requestId,
      conversationId: request.conversationId,
      seq: this.db.head(),
      author: { type: 'bot', id: request.botId },
      kind: 'secret',
      status: actionable(request)
        ? 'streaming'
        : request.state === 'cancelled'
          ? 'cancelled'
          : request.state === 'expired'
            ? 'failed'
            : 'done',
      createdAt: request.createdAt,
      content: {
        requestId: request.requestId,
        botId: request.botId,
        service: request.service,
        purpose: request.purpose,
        state: request.state,
        result: request.result,
      },
    });
  }
  list(botId: string) {
    this.bot(botId);
    return {
      credentials: this.credentials(botId).map(({ sealed, vaultId, ...entry }) => {
        void sealed;
        void vaultId;
        return entry;
      }),
    };
  }
  get(botId: string, id: string) {
    const request = this.request(botId, id);
    return {
      request: this.view(request),
      publicKey: this.keys.publicKey(botId),
      saved: this.list(botId).credentials.filter((c) => c.enabled && this.matches(c, request)),
    };
  }
  private matches(a: SecretSpec, b: SecretSpec) {
    return (
      a.service === b.service &&
      a.purpose === b.purpose &&
      JSON.stringify(a.fields) === JSON.stringify(b.fields) &&
      JSON.stringify(a.target) === JSON.stringify(b.target)
    );
  }
  private sourceRun(botId: string, sessionId: string) {
    return this.db
      .runs()
      .find(
        (r) => r.botId === botId && (r.sessionId === sessionId || r.storedSessionId === sessionId),
      );
  }
  private create(
    botId: string,
    spec: SecretSpec,
    run: Pick<RunRecord, 'conversationId' | 'sessionId' | 'storedSessionId' | 'runId'>,
    nativeRequestId?: string,
    notify = true,
  ) {
    this.bot(botId);
    const request: StoredRequest = {
      ...spec,
      requestId: randomUUID(),
      botId,
      conversationId: run.conversationId,
      sessionId: run.storedSessionId ?? run.sessionId!,
      state: 'pending',
      saved: false,
      createdAt: timestamp(),
      updatedAt: timestamp(),
      result: '',
      ...(nativeRequestId ? { nativeRequestId } : {}),
      originatingRunId: run.runId,
    };
    this.persist(request);
    if (notify) this.onRequestCard(this.view(request));
    return request;
  }
  attach(botId: string) {
    if (this.attached.has(botId)) return;
    const gateway = this.hermes.gateway(botId);
    gateway.onRequest = async (method, params, nativeId) => {
      if (method !== 'secret')
        throw new NodeFault('unavailable', 'This native request is not supported');
      const run = this.sourceRun(botId, String(params.session_id ?? ''));
      if (!run) throw new NodeFault('not_found', 'The requesting Hermes session is unavailable');
      const name = String(params.env_var ?? '');
      if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name))
        throw new NodeFault('invalid_params', 'Invalid native environment variable');
      const request = this.create(
        botId,
        {
          service: name,
          purpose: String(params.prompt || 'Hermes skill configuration'),
          fields: [{ name, label: name, kind: 'password' }],
          target: { kind: 'native-env', path: join(this.hermes.profileHome(botId), '.env') },
        },
        run,
        nativeId,
      );
      this.onWaiting(run, true);
      return new Promise((resolve) =>
        this.waiting.set(request.requestId, (value) => {
          this.onWaiting(run, false);
          resolve(value);
        }),
      );
    };
    const listener = (frame: { type: string; payload?: Record<string, unknown> }) => {
      if (frame.type !== 'request.cancel' && frame.type !== 'gateway.disconnected') return;
      for (const request of this.requests().filter((r) => r.botId === botId && r.nativeRequestId)) {
        if (frame.type === 'request.cancel' && frame.payload?.id !== request.nativeRequestId)
          continue;
        const resolve = this.waiting.get(request.requestId);
        if (!resolve && request.state !== 'delivered') continue;
        this.waiting.delete(request.requestId);
        resolve?.({ value: null });
        if (actionable(request) || request.state === 'delivered') {
          request.state = frame.payload?.reason === 'resolved' ? 'delivered' : 'expired';
          request.result =
            frame.payload?.reason === 'resolved'
              ? 'Hermes accepted the delivery. Native configuration is still being processed.'
              : 'Native request ended: ' + String(frame.payload?.reason ?? 'disconnected');
          this.persist(request);
        }
      }
    };
    gateway.listeners.add(listener);
    this.attached.set(botId, () => {
      gateway.listeners.delete(listener);
      gateway.onRequest = undefined;
    });
  }
  submit(
    botId: string,
    id: string,
    payload: { envelope?: SecretEnvelope; credentialId?: string; save: boolean },
  ) {
    this.request(botId, id);
    const active = this.submitting.get(id);
    if (active) return active;
    const operation = this.deliver(botId, id, payload).finally(() => this.submitting.delete(id));
    this.submitting.set(id, operation);
    return operation;
  }
  private async deliver(
    botId: string,
    id: string,
    payload: { envelope?: SecretEnvelope; credentialId?: string; save: boolean },
  ) {
    const request = this.request(botId, id);
    if (!actionable(request)) return this.view(request);
    if (!this.nodeId) throw new NodeFault('unavailable', 'Node identity is unavailable');
    if (request.nativeRequestId && !this.waiting.has(id))
      throw new NodeFault('not_found', 'The native request has ended');
    const saved = payload.credentialId ? this.credential(botId, payload.credentialId) : undefined;
    if (saved && !this.matches(saved, request))
      throw new NodeFault(
        'invalid_params',
        'Service, purpose or destination changed. Confirm a new delivery.',
      );
    let values: Record<string, string> = {};
    if (saved?.sealed) values = this.keys.open(botId, saved.sealed);
    else if (!saved?.vaultId) {
      try {
        const raw = this.keys.decrypt(
          botId,
          secretContext(this.nodeId, botId, id),
          payload.envelope!,
        );
        values = z.record(z.string(), z.string().min(1).max(262_144)).parse(JSON.parse(raw));
      } catch {
        throw new NodeFault(
          'invalid_params',
          'Encrypted delivery could not be opened. Reopen the card and submit again.',
        );
      }
      if (
        Object.keys(values).length !== request.fields.length ||
        request.fields.some((f) => !values[f.name])
      )
        throw new NodeFault('invalid_params', 'Fill every requested field');
    }
    if (payload.save && request.fields.some((f) => f.kind === 'otp'))
      throw new NodeFault('invalid_params', 'One-time codes cannot be saved');
    this.temporary.set(id, values);
    request.state = 'delivered';
    request.saved = payload.save || Boolean(saved);
    request.result =
      'Encrypted delivery received by this Bot. Applying the approved destination...';
    this.persist(request);
    try {
      if (request.nativeRequestId) {
        this.waiting.get(id)!({ value: values[request.fields[0]!.name] });
        this.waiting.delete(id);
        request.result = 'Delivered to Hermes. Native skill configuration is continuing.';
      } else if (saved?.vaultId) {
        request.vaultId = saved.vaultId;
        request.state = 'applied';
        request.result = 'Existing profile vault login is ready for browser_vault.';
      } else await this.apply(request, values);
      if (request.saved) {
        const replaced = request.replaceId ? this.credential(botId, request.replaceId) : undefined;
        const entry: StoredCredential = {
          service: request.service,
          purpose: request.purpose,
          target: request.target,
          fields: request.fields,
          credentialId: saved?.credentialId ?? request.replaceId ?? randomUUID(),
          botId,
          enabled: true,
          createdAt: saved?.createdAt ?? timestamp(),
          lastUsedAt: timestamp(),
          ...(request.vaultId
            ? { vaultId: request.vaultId }
            : { sealed: this.keys.seal(botId, values) }),
        };
        this.saveCredential(entry);
        request.credentialId = entry.credentialId;
        if (replaced?.vaultId && replaced.vaultId !== request.vaultId)
          await this.hermes.management.rpc('vault.remove', {
            profile: botId,
            id: replaced.vaultId,
          });
      } else if (request.replaceId) {
        await this.disable(botId, request.replaceId);
      }
      if (request.replaceId) {
        // A settings edit is not an instruction to resume unrelated chat work.
        request.completed = true;
        this.temporary.delete(id);
        if (!request.saved && request.vaultId) {
          await this.hermes.management.rpc('vault.remove', { profile: botId, id: request.vaultId });
          delete request.vaultId;
          request.result += ' Temporary vault item withdrawn; no login task was started.';
        }
      } else if (!request.nativeRequestId) {
        request.continuationId ??= 'secret-delivery:' + id;
        // Persist before native admission; a retry uses Hermes' submission ID deduplication.
        this.persist(request);
        await this.onContinue(
          this.view(request),
          request.continuationId,
          this.continuation(request),
        );
      }
      this.persist(request);
    } catch (error) {
      request.state = 'failed';
      const detail =
        error instanceof NodeFault
          ? this.scrub(botId, error.message)
          : String((error as NodeJS.ErrnoException).code ?? 'configuration_failed');
      request.result =
        'Delivery received, but configuration or the original session could not continue: ' +
        detail +
        '. Check the destination/session, then explicitly deliver again. Previous tools were not replayed.';
      this.temporary.delete(id);
      if (!request.saved && request.vaultId) {
        await this.hermes.management
          .rpc('vault.remove', { profile: botId, id: request.vaultId })
          .then(
            () => {
              delete request.vaultId;
            },
            () => {
              request.result +=
                ' Temporary vault cleanup is pending; this reference cannot be used.';
            },
          );
      }
      this.persist(request);
    }
    return this.view(request);
  }
  private continuation(r: StoredRequest) {
    return `Confidential delivery for ${r.service} (${r.purpose}) is ready. Reference: ${r.requestId}. ${r.result} ${r.target.kind === 'vault' || r.target.kind === 'browser-code' ? 'Use nekodot_secret_browser with this reference. It delegates to native browser_vault and fills identifier/password/code without exposing values.' : ''} Continue only the remaining task. Do not read, print, copy into chat, or put credential values in tool arguments or generated scripts. Use hermes secret status/apply with this reference for metadata and the already approved destination.`;
  }
  private async apply(request: StoredRequest, values: Record<string, string>) {
    if (request.target.kind === 'browser-code') {
      request.result =
        'One-time code is ready for the original profile browser. It has not been entered yet.';
    } else if (request.target.kind === 'vault') {
      const result = await this.hermes.management.rpc<{ id: string }>('vault.add', {
        profile: request.botId,
        kind: 'login',
        label: request.service,
        origin: request.target.origin,
        secret: {
          ...values,
          identifier_type: values.identifier!.includes('@')
            ? 'email'
            : /^\+?\d+$/.test(values.identifier!)
              ? 'phone'
              : 'username',
        },
      });
      request.vaultId = result.id;
      request.result = 'Profile vault login is ready. Browser login itself has not completed.';
    } else {
      const target = request.target;
      const path = isAbsolute(target.path)
        ? target.path
        : resolve(this.hermes.profileHome(request.botId), target.path);
      await mkdir(dirname(path), { recursive: true, mode: 0o700 });
      const raw = await readFile(path, 'utf8').catch((error: NodeJS.ErrnoException) => {
        if (error.code === 'ENOENT') return '';
        throw error;
      });
      let output: string;
      if (target.kind === 'native-env' || target.format === 'env') {
        const lines = raw.split(/\r?\n/);
        for (const [key, value] of Object.entries(values)) {
          const encoded = `${key}=${JSON.stringify(value)}`;
          const index = lines.findIndex((line) =>
            new RegExp('^(?:export\\s+)?' + key + '=').test(line),
          );
          if (index < 0) lines.push(encoded);
          else lines[index] = encoded;
        }
        output = lines.join('\n');
      } else if (target.format === 'raw') {
        if (request.fields.length !== 1) throw new Error('Raw files require one field');
        output = values[request.fields[0]!.name]!;
      } else if (target.format === 'json')
        output = JSON.stringify({ ...(raw ? JSON.parse(raw) : {}), ...values }, null, 2) + '\n';
      else {
        const document = parseDocument(raw || '{}', { compat: 'yaml-1.1' });
        if (document.errors.length) throw new Error('Invalid target YAML');
        for (const [key, value] of Object.entries(values)) document.set(key, value);
        output = document.toString();
      }
      await writeFile(path, output, { mode: 0o600 });
      request.result = 'Configuration applied: ' + path;
    }
    request.state = 'applied';
  }
  cancel(botId: string, id: string) {
    const request = this.request(botId, id);
    if (!actionable(request)) return this.view(request);
    this.waiting.get(id)?.({ value: null });
    this.waiting.delete(id);
    this.temporary.delete(id);
    request.state = 'cancelled';
    request.result =
      'Cancelled. Existing target configuration or website sessions were not reverted.';
    this.persist(request);
    return this.view(request);
  }
  replace(botId: string, credentialId: string) {
    const saved = this.credential(botId, credentialId);
    const conversation = this.db.conversations().find((c) => c.kind === 'dm' && c.botId === botId)!;
    const session = this.db.hermesSession(conversation.conversationId);
    if (!session) throw new NodeFault('unavailable', 'Open this Bot conversation first');
    const request = this.create(
      botId,
      {
        service: saved.service,
        purpose: saved.purpose,
        fields: saved.fields,
        target: saved.target,
      },
      { conversationId: conversation.conversationId, sessionId: session.storedSessionId },
    );
    request.replaceId = credentialId;
    this.persist(request);
    return this.view(request);
  }
  async disable(botId: string, credentialId: string) {
    const entry = this.credential(botId, credentialId);
    entry.enabled = false;
    this.saveCredential(entry);
    if (entry.vaultId)
      await this.hermes.management.rpc('vault.remove', { profile: botId, id: entry.vaultId });
    return {};
  }
  /** Unix socket boundary: profile-owned token, no caller-selected profile or raw read command. */
  async local(input: unknown) {
    const p = z
      .object({
        botId: z.string(),
        token: z.string(),
        operation: z.enum(['request', 'status', 'apply', 'scrub', 'browser-code']),
        sessionId: z.string().optional(),
        requestId: z.string().optional(),
        spec: secretSpecSchema.optional(),
        text: z.string().optional(),
      })
      .parse(input);
    this.bot(p.botId);
    const tokenPath = join(
      this.hermes.profileHome(p.botId),
      'plugins',
      'nekodot-secrets',
      'bridge.token',
    );
    if (!p.token || p.token !== (await readFile(tokenPath, 'utf8')).trim())
      throw new NodeFault('not_found', 'Profile credential access denied');
    if (p.operation === 'scrub') return this.scrub(p.botId, p.text ?? '');
    if (p.operation === 'request') {
      const run = this.sourceRun(p.botId, p.sessionId ?? '');
      if (!run)
        throw new NodeFault('not_found', 'Create the request from the active native Bot session');
      const spec = p.spec;
      if (!spec) throw new NodeFault('invalid_params', 'Secret request specification is required');
      if (
        spec.target.kind === 'browser-code' &&
        (spec.fields.length !== 1 || spec.fields[0]!.kind !== 'otp')
      )
        throw new NodeFault(
          'invalid_params',
          'Browser codes require exactly one one-time-code field',
        );
      if (spec.target.kind === 'vault' && spec.fields.some((f) => f.kind === 'otp'))
        throw new NodeFault(
          'invalid_params',
          'Request a separate temporary browser-code card for a one-time code',
        );
      if (spec.target.kind === 'native-env')
        throw new NodeFault('invalid_params', 'Native requests are issued by Hermes');
      if (spec.target.kind === 'file' && !isAbsolute(spec.target.path))
        spec.target.path = resolve(this.hermes.profileHome(p.botId), spec.target.path);
      if (
        spec.target.kind === 'vault' &&
        (!spec.fields.some((f) => f.name === 'identifier') ||
          !spec.fields.some((f) => f.name === 'password'))
      )
        throw new NodeFault(
          'invalid_params',
          'Website login fields must include identifier and password',
        );
      const match = this.credentials(p.botId).find((c) => c.enabled && this.matches(c, spec));
      const request = this.create(p.botId, spec, run, undefined, !match);
      if (match && !spec.fields.some((f) => f.kind === 'otp')) {
        // Already approved exact service/purpose/target: apply in this turn, no extra continuation.
        const values = match.sealed ? this.keys.open(p.botId, match.sealed) : {};
        this.temporary.set(request.requestId, values);
        request.saved = true;
        request.credentialId = match.credentialId;
        if (match.vaultId) {
          request.vaultId = match.vaultId;
          request.state = 'applied';
          request.result = 'Saved profile vault login is ready.';
        } else await this.apply(request, values);
        match.lastUsedAt = timestamp();
        this.saveCredential(match);
        this.persist(request);
        return { ...this.view(request), ...(request.vaultId ? { vaultId: request.vaultId } : {}) };
      }
      return this.view(request);
    }
    const request = this.request(p.botId, p.requestId ?? '');
    if (p.operation === 'browser-code') {
      if (request.target.kind !== 'browser-code' || request.state !== 'applied')
        throw new NodeFault('forbidden', 'No approved one-time code for this reference');
      const fields = this.temporary.get(request.requestId);
      if (!fields) throw new NodeFault('unavailable', 'Deliver the code again');
      return { code: fields[request.fields[0]!.name] };
    }
    if (p.operation === 'apply') {
      if (request.state !== 'applied' && request.state !== 'delivered')
        throw new NodeFault('unavailable', 'Ask the user to deliver this card first');
      // Delivery applied exactly the approved target. Never apply twice on model retries.
    }
    return { ...this.view(request), ...(request.vaultId ? { vaultId: request.vaultId } : {}) };
  }
  scrub(botId: string, text: string) {
    const ids = new Set(
      this.requests()
        .filter((r) => r.botId === botId)
        .map((r) => r.requestId),
    );
    const values = [...this.temporary.entries()]
      .filter(([id]) => ids.has(id))
      .flatMap(([, fields]) => Object.values(fields));
    for (const entry of this.credentials(botId))
      if (entry.sealed) values.push(...Object.values(this.keys.open(botId, entry.sealed)));
    for (const value of values.sort((a, b) => b.length - a.length))
      if (value) {
        text = text.split(JSON.stringify(value).slice(1, -1)).join('[confidential]');
        text = text.split(value).join('[confidential]');
      }
    return text;
  }
  async finish(run: RunRecord) {
    for (const request of this.requests().filter(
      (r) =>
        r.botId === run.botId &&
        (r.sessionId === run.sessionId || r.sessionId === run.storedSessionId),
    )) {
      // Pending general cards survive the creating turn. Only delivered temporary items expire.
      if (!['applied', 'delivered'].includes(request.state)) continue;
      if (request.completed) continue;
      if (
        request.continuationId
          ? request.continuationId !== run.submissionId
          : request.originatingRunId !== run.runId
      )
        continue;
      if (request.nativeRequestId) {
        const name = request.fields[0]!.name;
        const expected = this.temporary.get(request.requestId)?.[name];
        const stored =
          expected !== undefined &&
          (await this.hermes.environment(run.botId).then(
            (env) => env[name] === expected,
            () => false,
          ));
        request.state = stored ? 'applied' : 'failed';
        request.result = stored
          ? 'Hermes stored the native skill configuration.'
          : 'Hermes ended the request, but the native configuration was not stored. Request delivery again; no tools were replayed.';
      }
      if (!request.saved && request.vaultId) {
        await this.hermes.management.rpc('vault.remove', {
          profile: run.botId,
          id: request.vaultId,
        });
        delete request.vaultId;
        request.result += ' Temporary vault item withdrawn; website session may remain.';
        this.persist(request);
      }
      request.completed = true;
      this.persist(request);
      this.temporary.delete(request.requestId);
    }
  }
  close() {
    for (const resolve of this.waiting.values()) resolve({ value: null });
    this.waiting.clear();
    this.temporary.clear();
    for (const detach of this.attached.values()) detach();
  }
}
