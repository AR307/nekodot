import { mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import type { MemoryDocument, Operation, RpcParams, RpcResult } from '@nekodot/protocol';
import type { BotService } from './bots';
import type { NodeDatabase } from './database';
import type { HermesRuntime } from './hermes/runtime';
import type { Operations } from './operations';
import { NodeFault } from './fault';
import type { SharedUserMemory } from './user-memory';

export class BotManagement {
  constructor(
    readonly database: NodeDatabase,
    readonly bots: BotService,
    readonly hermes: HermesRuntime,
    readonly operations: Operations,
    readonly userMemory: SharedUserMemory,
  ) {}
  async jobs(botId: string): Promise<RpcResult<'bots.jobs'>> {
    this.bots.get(botId);
    const jobs = await this.hermes.management.request<Record<string, unknown>[]>(
      '/api/cron/jobs',
      botId,
    );
    return { jobs };
  }
  async jobRuns(botId: string, jobId: string): Promise<RpcResult<'bots.jobs.runs'>> {
    const { jobs } = await this.jobs(botId);
    const job = jobs.find((row) => row.id === jobId || row.job_id === jobId);
    if (!job) throw new NodeFault('not_found', 'Job not found in this profile');
    const data = await this.hermes.management.request<
      { runs: Record<string, unknown>[] } | Record<string, unknown>[]
    >('/api/cron/jobs/' + encodeURIComponent(jobId) + '/runs?limit=20', botId);
    return { job, runs: Array.isArray(data) ? data : data.runs };
  }
  private documentPath(botId: string, name: MemoryDocument) {
    return join(
      this.hermes.profileHome(botId),
      ...(name === 'SOUL.md' ? [name] : ['memories', name]),
    );
  }
  async memory(botId: string): Promise<RpcResult<'memory.get'>> {
    this.bots.get(botId);
    const documents = await Promise.all(
      (['SOUL.md', 'MEMORY.md', 'USER.md'] as const).map(async (name) => {
        if (name === 'SOUL.md') {
          const v = await this.hermes.management.request<{ content: string; exists: boolean }>(
            '/api/profiles/' + botId + '/soul',
            botId,
          );
          return { name, ...v };
        }
        try {
          const v = await this.hermes.management.request<{ text: string }>(
            '/api/fs/read-text?path=' + encodeURIComponent(this.documentPath(botId, name)),
            botId,
          );
          return { name, content: v.text, exists: true };
        } catch (error) {
          if (error instanceof NodeFault && error.code === 'not_found')
            return { name, content: '', exists: false };
          throw error;
        }
      }),
    );
    let pending = '';
    const conversation = this.database
      .conversations()
      .find((c) => c.kind === 'dm' && c.botId === botId);
    if (conversation && this.database.messages(conversation.conversationId, undefined, 1).length) {
      const session = await this.session(botId);
      const outputs = await Promise.all(
        ['memory', 'skills'].map(async (kind) => {
          const v = await this.hermes.management.rpc<{ output?: string }>('slash.exec', {
            profile: botId,
            session_id: session,
            command: '/' + kind + ' pending',
          });
          return v.output ?? '';
        }),
      );
      pending = outputs.join('\n\n');
    }
    return { documents, pending };
  }
  async save(input: RpcParams<'memory.save'>) {
    const bot = this.bots.get(input.botId);
    const api = this.hermes.management;
    if (input.name === 'SOUL.md') {
      // The native identity editor and the existing role editor share the same document.
      const rules = /<!-- nekodot managed:[\s\S]*?<!-- end nekodot managed -->\n?/;
      const current = await api.request<{ content: string }>(
        '/api/profiles/' + bot.botId + '/soul',
        bot.botId,
      );
      const content = input.content.match(rules)
        ? input.content
        : input.content.trimEnd() + '\n\n' + (current.content.match(rules)?.[0] ?? '');
      await api.request('/api/profiles/' + bot.botId + '/soul', bot.botId, {
        method: 'PUT',
        body: JSON.stringify({ content }),
      });
      const managed = content.match(rules)?.[0];
      const role = managed ? content.slice(0, content.indexOf(managed)) : content;
      this.database.putBot({ ...bot, role: role.trimEnd() });
    } else {
      await mkdir(join(this.hermes.profileHome(bot.botId), 'memories'), { recursive: true });
      await api.request('/api/fs/write-text', bot.botId, {
        method: 'POST',
        body: JSON.stringify({
          path: this.documentPath(bot.botId, input.name),
          content: input.content,
          profile: bot.botId,
        }),
      });
    }
    return {};
  }
  private async session(botId: string) {
    const conversation = this.database
      .conversations()
      .find((c) => c.kind === 'dm' && c.botId === botId);
    if (!conversation)
      throw new NodeFault('not_found', 'Chat with this bot before refining memory');
    const result = await this.hermes.management.rpc<{ session_id: string }>('session.resume', {
      profile: botId,
      session_id: 'nk_dm_' + conversation.conversationId,
      eager_build: true,
      omit_messages: true,
    });
    return result.session_id;
  }
  refine(botId: string, focus: string) {
    this.bots.get(botId);
    if (this.database.runs().some((run) => run.botId === botId))
      throw new NodeFault(
        'conflict',
        'Wait for this bot to finish its current task before refining',
      );
    return this.operations.start('memory.refine', [botId], async (operation) => {
      const sessionId = await this.session(botId);
      // Hermes emits review.summary only when it writes something. Its own completion log
      // also covers a successful no-change review and provider failures.
      const logPath =
        '/api/logs?file=agent&search=' +
        encodeURIComponent(
          '[' +
            'nk_dm_' +
            this.database.conversations().find((c) => c.kind === 'dm' && c.botId === botId)!
              .conversationId +
            ']',
        ) +
        '&lines=100';
      const before = await this.hermes.management.request<{ lines: string[] }>(logPath, 'default');
      const baseline = before.lines.at(-1);
      await new Promise<void>((resolve, reject) => {
        const api = this.hermes.management;
        const finish = (error?: Error) => {
          clearTimeout(timer);
          clearInterval(poll);
          api.listeners.delete(listener);
          if (error) reject(error);
          else resolve();
        };
        const listener = (event: {
          type: string;
          session_id?: string;
          payload?: Record<string, unknown>;
        }) => {
          if (event.type === 'review.summary' && event.session_id === sessionId) {
            operation.detail = String(event.payload?.text ?? 'Hermes review completed');
            operation.results.push({ botId, ok: true, detail: operation.detail });
            finish();
          }
        };
        const timer = setTimeout(
          () =>
            finish(
              new NodeFault(
                'unavailable',
                'Hermes has not reported completion. Refresh the native memory and pending review.',
              ),
            ),
          15 * 60_000,
        );
        const poll = setInterval(() => {
          void api
            .request<{ lines: string[] }>(logPath, 'default')
            .then((value) => {
              const index = baseline ? value.lines.indexOf(baseline) : -1;
              const lines = value.lines.slice(index + 1);
              const complete = lines.find((line) => line.includes('Background review complete:'));
              const failed = lines.find(
                (line) =>
                  line.includes('Background memory/skill review failed:') ||
                  line.includes('Background review skipped:'),
              );
              if (failed || complete?.includes('result=error'))
                finish(
                  new NodeFault(
                    'unavailable',
                    'Hermes memory review failed. Check this profile’s model configuration.',
                  ),
                );
              else if (complete) {
                operation.detail = complete.includes('result=none')
                  ? 'Hermes review completed; no changes were needed.'
                  : 'Hermes review completed. Refresh to read memory and pending changes.';
                operation.results.push({ botId, ok: true, detail: operation.detail });
                finish();
              }
            })
            .catch((error: Error) => finish(error));
        }, 2000);
        api.listeners.add(listener);
        void api
          .rpc<{ output?: string }>(
            'slash.exec',
            {
              profile: botId,
              session_id: sessionId,
              command: '/refine' + (focus.trim() ? ' ' + focus.trim() : ''),
            },
            120_000,
          )
          .then((result) => {
            operation.detail = result.output ?? '';
            this.operations.save(operation);
            if (!/background|Reviewing/i.test(operation.detail))
              finish(new NodeFault('conflict', operation.detail));
          })
          .catch(finish);
      });
      await this.userMemory.sync();
    });
  }
  async review(input: RpcParams<'memory.review'>) {
    this.bots.get(input.botId);
    const session = await this.session(input.botId);
    const result = await this.hermes.management.rpc<{ output?: string }>('slash.exec', {
      profile: input.botId,
      session_id: session,
      command: `/${input.kind} ${input.action} ${input.reviewId}`,
    });
    if (input.action === 'approve') await this.userMemory.sync();
    return { output: result.output ?? '' };
  }
  restart(): Operation {
    if (this.database.runs().length)
      throw new NodeFault('conflict', 'Finish or stop active chats before restarting Hermes');
    return this.operations.start('hermes.restart', [], async (operation) => {
      await this.hermes.restart();
      operation.detail =
        'Hermes gateway and management restarted. Profiles, history and scheduled jobs were preserved.';
    });
  }
}
