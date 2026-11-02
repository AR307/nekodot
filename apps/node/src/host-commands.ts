import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import type { NodeDatabase } from './database';
import type { HermesRuntime } from './hermes/runtime';
import { openNativeSession } from './hermes/session';
import type { CommandResult } from './session-commands';
import { NodeFault } from './fault';

export const hostCommandNames = new Set(['/logs', '/export', '/snapshot', '/worktree', '/update']);

/** Fixed official management operations, never a URL or shell-command proxy. */
export async function hostCommand(
  database: NodeDatabase,
  hermes: HermesRuntime,
  botId: string,
  name: string,
  arg: string,
): Promise<CommandResult> {
  const management = hermes.management;
  if (name === '/logs') {
    const parts = arg ? arg.split(/\s+/) : [];
    const file = parts[0] && !/^\d+$/.test(parts[0]) ? parts.shift()! : 'gateway';
    const lines = parts[0] ? Number(parts.shift()) : 100;
    if (parts.length || !Number.isInteger(lines) || lines < 1 || lines > 500)
      throw new NodeFault(
        'invalid_params',
        'Usage: /logs [gateway|agent|errors|gui|desktop|mcp] [1-500]',
      );
    const result = await management.request<{ lines: string[] }>(
      `/api/logs?file=${encodeURIComponent(file)}&lines=${lines}`,
      botId,
    );
    return {
      output: `Hermes profile ${file} log\n${result.lines.join('\n') || '(no log entries)'}`,
    };
  }
  if (name === '/export') {
    if (arg)
      throw new NodeFault(
        'invalid_params',
        'Use /export to download this Bot’s native profile archive. Credentials are excluded by Hermes.',
      );
    const result = await management.request<{ archive: string }>(
      `/api/profiles/${encodeURIComponent(botId)}/export`,
      botId,
      { method: 'POST', body: '{}' },
    );
    return {
      output:
        'Hermes profile exported. This native archive excludes credentials; download it from the file card.',
      artifact: result.archive,
    };
  }
  if (name === '/snapshot') {
    if (arg && arg !== 'create')
      throw new NodeFault(
        'invalid_params',
        'Use /snapshot create for a native backup. Restore/prune can replace or delete data and are not offered by this App.',
      );
    const action = await management.request<{ name: string; archive: string }>(
      '/api/ops/backup',
      botId,
      { method: 'POST', body: '{}' },
    );
    const end = Date.now() + 15 * 60_000;
    while (Date.now() < end) {
      const state = await management.request<{
        running: boolean;
        exit_code: number | null;
        lines: string[];
      }>(`/api/actions/${encodeURIComponent(action.name)}/status`, botId);
      if (!state.running) {
        if (state.exit_code !== 0)
          throw new NodeFault(
            'unavailable',
            `Hermes backup failed: ${state.lines.slice(-6).join('\n')}`,
          );
        return {
          output:
            'Hermes native backup created. Unlike a shareable profile export, a backup may contain private state; keep it private. Restore is not performed.',
          artifact: action.archive,
        };
      }
      await delay(500);
    }
    throw new NodeFault(
      'unavailable',
      'Hermes backup is still running. It was not restarted. Check /logs before retrying.',
    );
  }
  if (name === '/update') {
    if (arg && arg !== 'check')
      throw new NodeFault(
        'invalid_params',
        'Use /update check. Installing an update belongs to the Node’s managed release process, not a chat command that replaces a running server.',
      );
    const result = await management.request<Record<string, unknown>>(
      '/api/hermes/update/check',
      botId,
    );
    return {
      output: `Hermes update check\n${JSON.stringify(result, null, 2)}\nInstallation uses this Node’s managed release process; no running task or service was changed.`,
    };
  }
  const [action = 'list', ...rest] = arg ? arg.split(/\s+/) : [];
  if (!['list', 'new'].includes(action) || (action === 'list' && rest.length))
    throw new NodeFault(
      'invalid_params',
      'Usage: /worktree [list | new [name]]. Pruning deletes files and is not offered.',
    );
  const dm = database.conversations().find((row) => row.kind === 'dm' && row.botId === botId)!;
  const gateway = hermes.gateway(botId);
  const session = await openNativeSession(database, hermes, botId, dm.conversationId);
  const params = { session_id: session.session_id };
  const info = await gateway.rpc<{ cwd: string }>('session.info', params);
  if (action === 'list') {
    const result = await management.request<Record<string, unknown>>(
      `/api/git/worktrees?path=${encodeURIComponent(info.cwd)}`,
      botId,
    );
    return { output: `Hermes worktrees\n${JSON.stringify(result, null, 2)}` };
  }
  if (session.running)
    throw new NodeFault('conflict', 'Finish this Bot’s turn before switching its workspace.');
  const worktree = await management.request<{ path: string; branch: string }>(
    '/api/git/worktree/add',
    botId,
    {
      method: 'POST',
      body: JSON.stringify({ path: info.cwd, ...(rest.length ? { name: rest.join(' ') } : {}) }),
    },
  );
  await gateway.rpc('session.mutate', {
    ...params,
    request_id: randomUUID(),
    expected_revision: session.revision,
    expected_generation: session.execution_generation,
    operation: 'workspace',
    payload: { cwd: worktree.path },
  });
  return {
    output: `Hermes workspace switched to ${worktree.path}\nBranch: ${worktree.branch}\nThe original checkout and completed tool effects were retained.`,
  };
}
