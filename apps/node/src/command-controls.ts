import { randomUUID } from 'node:crypto';
import type { NodeDatabase } from './database';
import type { HermesRuntime } from './hermes/runtime';
import type { GatewayFrame, HermesGateway } from './hermes/gateway';
import { openNativeSession } from './hermes/session';
import type { CommandResult } from './session-commands';
import { NodeFault } from './fault';

export const controlCommandNames = new Set([
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
  const dm = database.conversations().find((row) => row.kind === 'dm' && row.botId === botId)!;
  const gateway = hermes.gateway(botId);
  const current = await openNativeSession(database, hermes, botId, dm.conversationId);
  const params = { session_id: current.session_id };
  if (name === '/wake') {
    if (arg && arg !== 'status')
      throw new NodeFault(
        'invalid_params',
        'Use /wake to open this device’s microphone page, or /wake status for native requirements.',
      );
    const result = await gateway.rpc<Record<string, unknown>>('wake.status', {
      profile: botId,
      surface: 'gui',
      client_capture: true,
    });
    return {
      output: `Hermes wake-word requirements\n${JSON.stringify(result, null, 2)}\nScope: native detector on this Node. Open /wake to stream this device’s microphone; no listener was started by this status query.`,
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
    const usage =
      'Usage: /queue <prompt> | list | rm N | edit N <prompt> | steer N. Editing moves the replacement to the native FIFO tail.';
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
    const match = /^(rm|edit|steer)\s+(\d+)(?:\s+([\s\S]+))?$/.exec(arg);
    if (match) {
      const row = snapshot.pending[Number(match[2]) - 1];
      if (!row || row.status !== 'queued')
        throw new NodeFault('invalid_params', 'That queued admission is no longer pending.');
      if (match[1] === 'edit') {
        if (!match[3]?.trim()) throw new NodeFault('invalid_params', usage);
        return { type: 'queue', target: row.admission_id, message: match[3] };
      }
      if (match[3]) throw new NodeFault('invalid_params', usage);
      if (match[1] === 'steer') {
        const result = await gateway.rpc<{ status: string }>('prompt.steer_queued', {
          ...params,
          admission_id: row.admission_id,
        });
        return {
          output: `Hermes queued steer: ${result.status}. The native owner decides whether this input is consumed or returns to its queue position.`,
        };
      }
      await gateway.rpc('prompt.cancel', { ...params, admission_id: row.admission_id });
      return { output: 'Native queued admission cancelled. The running turn was not interrupted.' };
    }
    if (/^(rm|edit|steer|move|reorder)(?:\s|$)/.test(arg))
      throw new NodeFault('invalid_params', usage + ' This Hermes version has no reorder API.');
    return { type: 'queue', message: arg };
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
