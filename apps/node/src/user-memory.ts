import { watch, type FSWatcher } from 'node:fs';
import { mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import type {
  RpcParams,
  UserMemoryRequest,
  UserMemoryState,
  UserMemoryView,
} from '@nekodot/protocol';
import type { HermesRuntime } from './hermes/runtime';
import type { NodeDatabase } from './database';
import { NodeFault } from './fault';

interface LocalMemory {
  shared: UserMemoryState | null;
  profiles: Record<string, { base: string }>;
}

/** Syncs native files, never an agent's frozen prompt or conversation. */
export class SharedUserMemory {
  private local: LocalMemory;
  private nodeId = '';
  private exchange?: (request: UserMemoryRequest) => Promise<UserMemoryState>;
  private connected = false;
  private error = '';
  private closing = false;
  private running?: Promise<UserMemoryView>;
  private again = false;
  private timer?: ReturnType<typeof setTimeout>;
  private watchers = new Map<string, FSWatcher>();

  constructor(
    readonly database: NodeDatabase,
    readonly hermes: HermesRuntime,
  ) {
    this.local = database.setting<LocalMemory>('shared-user-memory') ?? {
      shared: null,
      profiles: {},
    };
  }
  bind(nodeId: string, exchange: (request: UserMemoryRequest) => Promise<UserMemoryState>) {
    this.nodeId = nodeId;
    this.exchange = exchange;
  }
  online(connected: boolean) {
    this.connected = connected;
    if (connected) void this.sync();
  }
  view(): UserMemoryView {
    return { shared: this.local.shared, connected: this.connected, error: this.error };
  }
  private path(botId: string) {
    return join(this.hermes.profileHome(botId), 'memories', 'USER.md');
  }
  private async read(botId: string) {
    try {
      return (
        await this.hermes.management.request<{ text: string }>(
          '/api/fs/read-text?path=' + encodeURIComponent(this.path(botId)),
          botId,
        )
      ).text;
    } catch (error) {
      if (error instanceof NodeFault && error.code === 'not_found') return '';
      throw error;
    }
  }
  private persist() {
    this.database.setSetting('shared-user-memory', this.local);
  }
  sync(): Promise<UserMemoryView> {
    if (!this.connected || !this.exchange || this.closing) return Promise.resolve(this.view());
    this.again = true;
    if (!this.running)
      this.running = (async () => {
        do {
          this.again = false;
          await this.synchronize();
          this.error = '';
        } while (this.again && this.connected && !this.closing);
        return this.view();
      })()
        .catch((error: unknown) => {
          this.error =
            error instanceof NodeFault
              ? error.message
              : 'Could not sync user memory. Local files are kept; reconnect or refresh to retry.';
          return this.view();
        })
        .finally(() => {
          this.running = undefined;
        });
    return this.running;
  }
  private async synchronize() {
    const snapshots = [];
    for (const bot of this.database.bots()) {
      const directory = join(this.hermes.profileHome(bot.botId), 'memories');
      await mkdir(directory, { recursive: true });
      if (!this.watchers.has(bot.botId)) {
        const watcher = watch(directory, (_event, file) => {
          if (file?.toString() !== 'USER.md' || this.closing) return;
          clearTimeout(this.timer);
          this.timer = setTimeout(() => void this.sync(), 150);
        });
        watcher.on('error', () => {
          this.error = 'USER.md file watching stopped. Refresh to synchronize.';
        });
        this.watchers.set(bot.botId, watcher);
      }
      snapshots.push({
        botId: bot.botId,
        name: bot.displayName,
        base: this.local.profiles[bot.botId]?.base ?? null,
        content: await this.read(bot.botId),
      });
    }
    const shared = await this.exchange!({ action: 'sync', updates: snapshots });
    this.local.shared = shared;
    this.persist();
    for (const snapshot of snapshots) {
      const imports = shared.imports.filter(
        (item) => item.nodeId === this.nodeId && item.botId === snapshot.botId,
      );
      if (imports.some((item) => !item.reviewed) || !shared.initialized) continue;
      if (snapshot.base === null && snapshot.content && snapshot.content !== shared.content) {
        const reviewed = imports.findLast((item) => item.reviewed);
        if (!reviewed) continue;
        if (reviewed.content !== snapshot.content) {
          this.local.profiles[snapshot.botId] = { base: reviewed.content };
          this.again = true;
          continue;
        }
      }
      if (snapshot.content !== shared.content) {
        // Don't contend with native writes during a run, or discard a write made during this request.
        if (this.database.runs().some((run) => run.botId === snapshot.botId && run.runId)) continue;
        if ((await this.read(snapshot.botId)) !== snapshot.content) {
          this.again = true;
          continue;
        }
        await this.hermes.management.request('/api/fs/write-text', snapshot.botId, {
          method: 'POST',
          body: JSON.stringify({
            path: this.path(snapshot.botId),
            content: shared.content,
            profile: snapshot.botId,
          }),
        });
      }
      this.local.profiles[snapshot.botId] = { base: shared.content };
    }
    this.persist();
  }
  async save(input: RpcParams<'memory.user.save'>) {
    if (!this.connected || !this.exchange)
      throw new NodeFault(
        'unavailable',
        'Reconnect this computer before confirming shared memory.',
      );
    await this.sync();
    this.local.shared = await this.exchange({ action: 'save', ...input });
    this.persist();
    return this.sync();
  }
  async close() {
    this.closing = true;
    clearTimeout(this.timer);
    for (const watcher of this.watchers.values()) watcher.close();
    await this.running;
  }
}
