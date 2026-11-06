import { z } from 'zod';
import { tokenUsageSchema, type Bot, type UsageEntity, type UsageRecord } from '@nekodot/protocol';
import type { NodeDatabase } from './database';
import type { HermesRuntime } from './hermes/runtime';

const nativeRows = z.array(
  z.object({
    seq: z.number().int(),
    id: z.string(),
    sessionId: z.string(),
    executionId: z.string(),
    at: z.number(),
    tokens: tokenUsageSchema.nullable(),
    lineage: z.array(z.string()),
    route: z.string().optional(),
    jobId: z.string().optional(),
  }),
);
type NativeUsage = z.infer<typeof nativeRows>[number];
interface RoutineLabel {
  routineId: string;
  botId: string;
  name: string;
  route?: string;
  cronJobId?: string;
}

export class NodeUsage {
  private timer?: ReturnType<typeof setInterval>;
  private pending?: Promise<void>;
  private connected = false;
  publish?: (records: UsageRecord[]) => Promise<void>;
  onError: (message: string) => void = () => {};
  constructor(
    private database: NodeDatabase,
    private hermes: HermesRuntime,
  ) {}

  online(value: boolean) {
    this.connected = value;
    clearInterval(this.timer);
    if (value) {
      const collect = () => void this.sync().catch(() => this.onError('Usage sync failed'));
      collect();
      this.timer = setInterval(collect, 10_000);
      this.timer.unref();
    }
  }

  sync(): Promise<void> {
    if (!this.connected || !this.publish) return Promise.resolve();
    return (this.pending ??= this.collect().finally(() => {
      this.pending = undefined;
    }));
  }

  private owner(bot: Bot, row: NativeUsage): UsageEntity {
    const execution = this.database.db
      .prepare(
        "SELECT conversation_id FROM usage_owners WHERE profile=? AND kind='execution' AND id=?",
      )
      .get(bot.botId, row.executionId);
    let conversationId = execution?.conversation_id;
    if (!conversationId)
      for (const sid of row.lineage) {
        const session = this.database.db
          .prepare(
            "SELECT conversation_id FROM usage_owners WHERE profile=? AND kind='session' AND id=?",
          )
          .get(bot.botId, sid);
        if (session) {
          conversationId = session.conversation_id;
          break;
        }
      }
    const conversation = conversationId
      ? this.database.conversation(String(conversationId))
      : undefined;
    const group =
      conversation?.kind === 'group' ? this.database.group(conversation.groupId) : undefined;
    if (group)
      return {
        id: group.groupId,
        kind: 'group',
        name: group.name,
        ownerName: group.name,
        group: true,
        avatars: group.botIds.flatMap((id) => {
          const b = this.database.bot(id);
          return b ? [b.avatar] : [];
        }),
      };
    return {
      id: bot.botId,
      kind: 'bot',
      name: bot.displayName,
      ownerName: bot.displayName,
      group: false,
      avatars: [bot.avatar],
    };
  }

  private async collect() {
    for (const bot of this.database.allBots()) {
      let more = true;
      while (more && this.connected) {
        const key = 'usage-cursor:' + bot.botId;
        const after = this.database.setting<number>(key) ?? 0;
        const result = await this.hermes.management.rpc<{ output: string }>('command.dispatch', {
          profile: bot.botId,
          name: 'nekodot-usage-read',
          arg: JSON.stringify({ profile: bot.botId, after }),
        });
        const rows = nativeRows.parse(JSON.parse(result.output));
        const routines: RoutineLabel[] = this.database.db
          .prepare('SELECT data FROM routines')
          .all()
          .map((r) => JSON.parse(String(r.data)) as RoutineLabel)
          .filter((r) => r.botId === bot.botId);
        const jobs = rows.some((r) => r.jobId)
          ? await this.hermes.management.request<{ id: string; name: string }[]>(
              '/api/cron/jobs',
              bot.botId,
            )
          : [];
        const records = rows.map((row): UsageRecord => {
          let entity = this.owner(bot, row);
          if (row.route || row.jobId) {
            const routine = routines.find((r) =>
              row.route ? r.route === row.route : r.cronJobId === row.jobId,
            );
            // Adding a webhook to an existing cron must keep one lifetime statistics row.
            const id = row.jobId
              ? 'cron:' + row.jobId
              : (routine?.routineId ?? 'webhook:' + row.route);
            entity = {
              ...entity,
              kind: 'routine',
              id: bot.botId + ':' + id,
              name: routine?.name ?? jobs.find((j) => j.id === row.jobId)?.name ?? id,
            };
          }
          return {
            id: row.id,
            profile: bot.botId,
            sessionId: row.sessionId,
            executionId: row.executionId,
            at: new Date(row.at * 1000).toISOString(),
            tokens: row.tokens,
            entity,
          };
        });
        // Only advance after Relay commits the batch. Reconnection resends the same identities.
        await this.publish!(records);
        if (rows.length) this.database.setSetting(key, rows.at(-1)!.seq);
        more = rows.length === 500;
      }
    }
  }

  async close() {
    this.online(false);
    await this.pending?.catch(() => {});
  }
}
