import { randomUUID } from 'node:crypto';
import type { NodeDatabase } from './database';
import type { HermesRuntime } from './hermes/runtime';
import type { GatewayFrame, HermesGateway } from './hermes/gateway';
import { openNativeSession } from './hermes/session';
import type { CommandResult } from './session-commands';
import { NodeFault } from './fault';

export const controlCommandNames = new Set([
  '/stop',
  '/steer',
  '/reload-mcp',
  '/rollback',
  '/browser',
  '/bg',
  '/btw',
  '/queue',
  '/wake',
]);

/** Side answers remain native detached work, never admissions in the main conversation. */
async function sideAnswer(gateway: HermesGateway, sessionId: string, name: string, text: string) {
  if (!text) throw new NodeFault('invalid_params', `Usage: ${name} <prompt>`);
  const eventType = name === '/bg' ? 'background.complete' : 'btw.complete';
  const events: GatewayFrame[] = [];
  let taskId = '',
    finish: (frame: GatewayFrame) => void;
  const completed = new Promise<GatewayFrame>((resolve) => {
    finish = resolve;
  });
  const receive = (frame: GatewayFrame) => {
    if (frame.type === 'gateway.disconnected' || frame.type === 'gateway.protocol_error')
      finish(frame);
    if (frame.session_id !== sessionId || frame.type !== eventType) return;
    if (!taskId) events.push(frame);
    else if (frame.payload?.task_id === taskId) finish(frame);
  };
  gateway.listeners.add(receive);
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const task = await gateway.rpc<{ task_id: string }>(
      name === '/bg' ? 'prompt.background' : 'prompt.btw',
      {
        session_id: sessionId,
        text,
      },
    );
    taskId = task.task_id;
    for (const frame of events) if (frame.payload?.task_id === taskId) finish!(frame);
    timer = setTimeout(() => finish({ type: 'timeout' }), 15 * 60_000);
    const frame = await completed;
    if (frame.type !== eventType)
      throw new NodeFault(
        'unavailable',
        'The native side-task result connection was lost. The task was not restarted. Check its native session before retrying.',
      );
    const output = String(frame.payload?.text ?? '');
    if (output.startsWith('error:')) throw new NodeFault('unavailable', output);
    return { output: `${name} · ${taskId}\n\n${output || '(Hermes returned no text)'}` };
  } finally {
    clearTimeout(timer);
    gateway.listeners.delete(receive);
  }
}

export async function commandControl(
  database: NodeDatabase,
  hermes: HermesRuntime,
  botId: string,
  name: string,
  arg: string,
): Promise<CommandResult> {
  if (name === '/tools') {
    const [action, ...names] = arg.split(/\s+/);
    if (!['enable', 'disable'].includes(action!) || !names.length)
      throw new NodeFault(
        'invalid_params',
        'Usage: /tools [list | enable|disable <toolset or server:tool> ...]',
      );
    const enabled = action === 'enable';
    const changed: string[] = [],
      unknown: string[] = [],
      missing: string[] = [];
    const catalog = await hermes.management.request<{ name: string }[]>(
      '/api/tools/toolsets',
      botId,
    );
    for (const target of names.filter((value) => !value.includes(':'))) {
      if (!catalog.some((row) => row.name === target)) {
        unknown.push(target);
        continue;
      }
      // tools.configure ignores profile in v0.22.5. The official REST writer
      // scopes the write correctly and keeps native install-on-enable behavior.
      await hermes.management.request(`/api/tools/toolsets/${encodeURIComponent(target)}`, botId, {
        method: 'PUT',
        body: JSON.stringify({ enabled }),
      });
      changed.push(target);
    }
    const targets = names.filter((value) => value.includes(':'));
    if (targets.length) {
      const { servers } = await hermes.management.rpc<{
        servers: { name: string; source: string; tools?: { exclude?: string[] } }[];
      }>('mcp.servers.list', { profile: botId });
      const patch: Record<string, { tools: { exclude: string[] } }> = {};
      for (const target of targets) {
        const separator = target.indexOf(':'),
          serverName = target.slice(0, separator),
          tool = target.slice(separator + 1);
        const server = servers.find((row) => row.name === serverName);
        if (!server || !tool) {
          missing.push(target);
          continue;
        }
        if (server.source === 'plugin')
          throw new NodeFault(
            'invalid_params',
            `Hermes manages ${serverName} through its plugin settings.`,
          );
        const exclude = patch[serverName]?.tools.exclude ?? server.tools?.exclude ?? [];
        patch[serverName] = {
          tools: {
            exclude: enabled
              ? exclude.filter((value) => value !== tool)
              : [...new Set([...exclude, tool])],
          },
        };
        changed.push(target);
      }
      // Native config PUT deep-merges only these filter lists. Credentials and
      // all other server settings remain untouched; no masked values are copied.
      if (Object.keys(patch).length)
        await hermes.management.request('/api/config', botId, {
          method: 'PUT',
          body: JSON.stringify({ config: { mcp_servers: patch } }),
        });
    }
    return {
      output: `Hermes profile tools: ${changed.join(', ') || 'no changes'}\nUnknown: ${unknown.join(', ') || 'none'}\nMissing servers/tools: ${missing.join(', ') || 'none'}\nNative profile configuration saved. Existing context is not rebuilt; use /new for its new tool policy.`,
    };
  }
  const dm = database.conversations().find((row) => row.kind === 'dm' && row.botId === botId)!;
  const gateway = hermes.gateway(botId);
  const current = await openNativeSession(database, hermes, botId, dm.conversationId);
  const params = { session_id: current.session_id };
  if (name === '/wake') {
    if (arg && arg !== 'status')
      throw new NodeFault(
        'invalid_params',
        'Use /wake status to inspect native requirements. App microphone streaming is not connected; starting a server-local listener would not hear this device.',
      );
    const result = await gateway.rpc<Record<string, unknown>>('wake.status', {
      profile: botId,
      surface: 'gui',
      client_capture: true,
    });
    return {
      output: `Hermes wake-word requirements\n${JSON.stringify(result, null, 2)}\nScope: native detector on this Node. Client microphone capture is not connected; no listener was started.`,
    };
  }
  if (name === '/agents') {
    const [action, id, ...rest] = arg.split(/\s+/);
    if ((action === 'pause' || action === 'resume') && !id) {
      const result = await gateway.rpc<{ paused: boolean }>('delegation.pause', {
        ...params,
        paused: action === 'pause',
      });
      return {
        output: `Hermes delegation spawning: ${result.paused ? 'paused' : 'enabled'}. Scope: every chat and profile on this Node’s shared gateway; running subagents are unchanged.`,
      };
    }
    if (action === 'tail' && id && !rest.length) {
      const result = await gateway.rpc<Record<string, unknown>>('subagent.tail', {
        ...params,
        subagent_id: id,
      });
      return { output: JSON.stringify(result, null, 2) };
    }
    if (action === 'stop' && id && !rest.length) {
      const result = await gateway.rpc<{ found: boolean }>('subagent.interrupt', {
        ...params,
        subagent_id: id,
      });
      return {
        output: result.found
          ? 'Native subagent interrupted.'
          : 'That subagent is not active in this session.',
      };
    }
    if (action === 'steer' && id && rest.length) {
      const result = await gateway.rpc<{ status: string }>('subagent.steer', {
        ...params,
        subagent_id: id,
        text: rest.join(' '),
      });
      return { output: `Native subagent steer: ${result.status}` };
    }
    if (action === 'kill' && id && !rest.length) {
      const result = await gateway.rpc<{ status: string }>('process.kill', {
        ...params,
        process_id: id,
      });
      return { output: `Native session process: ${result.status}` };
    }
    throw new NodeFault(
      'invalid_params',
      'Usage: /agents [tail|stop <subagent-id> | steer <subagent-id> <message> | kill <process-id> | pause|resume]',
    );
  }
  if (name === '/bg' || name === '/btw') return sideAnswer(gateway, current.session_id, name, arg);
  if (name === '/steer') {
    if (!arg || !current.running)
      throw new NodeFault(
        'conflict',
        '/steer needs a running Hermes turn and a message. No new task was started.',
      );
    const result = await gateway.rpc<{ status: string }>('session.steer', {
      ...params,
      execution_generation: current.execution_generation,
      text: arg,
    });
    return { output: `Hermes steer: ${result.status}` };
  }
  if (name === '/stop') {
    if (arg)
      throw new NodeFault(
        'invalid_params',
        '/stop stops this session’s background processes and subagents. Use the chat Stop button to stop the main turn.',
      );
    const result = await gateway.rpc<{ killed: number; delegations: number }>(
      'process.stop',
      params,
    );
    return {
      output: `Hermes stopped ${result.killed} background processes and ${result.delegations} delegations. The chat Stop button controls the main turn.`,
    };
  }
  if (name === '/reload-mcp') {
    if (arg && arg !== 'confirm')
      throw new NodeFault('invalid_params', 'Usage: /reload-mcp [confirm]');
    const result = await gateway.rpc<Record<string, unknown>>(
      'reload.mcp',
      { ...params, ...(arg ? { confirm: true } : {}) },
      120_000,
    );
    return {
      output:
        result.status === 'confirm_required'
          ? `${result.message}\nUse /reload-mcp confirm to proceed.`
          : `Hermes MCP reload\n${JSON.stringify(result, null, 2)}`,
    };
  }
  if (name === '/rollback') {
    const parts = arg.split(/\s+/);
    if (!arg || arg === 'list') {
      const result = await gateway.rpc<{
        enabled: boolean;
        checkpoints: { hash: string; timestamp: string; message: string }[];
      }>('rollback.list', params);
      return {
        output: !result.enabled
          ? 'Hermes filesystem checkpoints are disabled.'
          : result.checkpoints.length
            ? result.checkpoints
                .map((row, index) => `${index + 1}. ${row.hash} ${row.timestamp} ${row.message}`)
                .join('\n')
            : 'No Hermes filesystem checkpoints yet.',
      };
    }
    if (parts[0] === 'diff' && parts.length === 2) {
      const result = await gateway.rpc<{ stat: string; diff: string }>('rollback.diff', {
        ...params,
        hash: parts[1],
      });
      return { output: `${result.stat}\n${result.diff}` };
    }
    throw new NodeFault(
      'invalid_params',
      'Use /rollback list or /rollback diff <checkpoint>. Restoring may delete files; it requires separate authorization under this project’s no-deletion rule.',
    );
  }
  if (name === '/browser') {
    const [action = 'status', value, ...rest] = arg ? arg.split(/\s+/) : [];
    if (
      !['status', 'connect', 'disconnect', 'use'].includes(action) ||
      rest.length ||
      (action === 'use' && value && !['on', 'off'].includes(value)) ||
      (['status', 'disconnect'].includes(action) && value)
    )
      throw new NodeFault(
        'invalid_params',
        'Usage: /browser status|connect [CDP URL]|disconnect|use [on|off]',
      );
    const result = await hermes.management.rpc<{
      connected: boolean;
      browser_use?: boolean;
      messages?: string[];
    }>(
      'browser.manage',
      {
        profile: botId,
        action,
        ...(action === 'connect' && value ? { url: value } : {}),
        ...(action === 'use' && value ? { enabled: value === 'on' } : {}),
      },
      5 * 60_000,
    );
    return {
      output: `Hermes browser: ${result.connected ? 'connected' : 'disconnected'}\nBrowser Use: ${result.browser_use ?? 'unknown'}\n${result.messages?.join('\n') ?? ''}`,
    };
  }
  if (name === '/queue') {
    const snapshot = await gateway.rpc<{
      pending: {
        admission_id: string;
        status: string;
        text?: string;
        payload?: { text?: string };
      }[];
    }>('session.resume', { ...params, omit_messages: true, defer_history: true });
    if (!arg || arg === 'list')
      return {
        output: snapshot.pending.length
          ? snapshot.pending
              .map(
                (row, i) =>
                  `${i + 1}. [${row.status}] ${row.admission_id}: ${row.text ?? row.payload?.text ?? ''}`,
              )
              .join('\n')
          : 'No pending Hermes admissions.',
      };
    const match = /^rm\s+(\d+)$/.exec(arg);
    if (match) {
      const row = snapshot.pending[Number(match[1]) - 1];
      if (!row || row.status !== 'queued')
        throw new NodeFault('invalid_params', 'That queued admission is no longer pending.');
      await gateway.rpc('prompt.cancel', { ...params, admission_id: row.admission_id });
      return { output: 'Native queued admission cancelled. The running turn was not interrupted.' };
    }
    throw new NodeFault(
      'invalid_params',
      'Supported: /queue list, /queue rm N. Enqueueing and reordering are not connected to the App transcript yet; no task was submitted.',
    );
  }
  // `/model model-id [--provider name] [--reasoning level]` is a native session pick.
  if (name === '/model') {
    const [model, ...flags] = arg.split(/\s+/),
      payload: Record<string, string> = { model: model! };
    for (let i = 0; i < flags.length; i += 2) {
      if (!['--provider', '--reasoning'].includes(flags[i]!) || !flags[i + 1])
        throw new NodeFault(
          'invalid_params',
          'Usage: /model <id> [--provider name] [--reasoning level]. For persistent Bot changes use /model without arguments.',
        );
      payload[flags[i]!.slice(2)] = flags[i + 1]!;
    }
    const result = await gateway.rpc<Record<string, unknown>>('session.mutate', {
      ...params,
      request_id: randomUUID(),
      expected_revision: current.revision,
      expected_generation: current.execution_generation,
      operation: 'model',
      payload,
    });
    return { output: `Hermes session model\n${JSON.stringify(result, null, 2)}` };
  }
  throw new NodeFault('invalid_params', 'Unknown native control');
}
