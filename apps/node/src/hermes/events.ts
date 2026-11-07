import { hermesTodoStateSchema, type HermesEvent } from '@nekodot/protocol';
import type { RunRecord } from '../database';
import type { GatewayFrame } from './gateway';

export function projectGatewayEvent(run: RunRecord, frame: GatewayFrame): HermesEvent | undefined {
  const payload = frame.payload ?? {};
  // Native background completions share the session stream, not this admission.
  if (frame.admission_id !== run.runId && payload.admission_id !== run.runId) return;
  const base = {
    run_id: run.runId ?? '',
    timestamp: Date.now() / 1000,
    seq: frame.seq ?? 0,
  };
  const text = typeof payload.text === 'string' ? payload.text : undefined;
  switch (frame.type) {
    case 'todo.updated':
      return { ...base, event: 'todo.updated', todo_state: hermesTodoStateSchema.parse(payload) };
    case 'message.delta':
      return { ...base, event: 'message.delta', ...(text !== undefined ? { delta: text } : {}) };
    case 'message.interim':
      return {
        ...base,
        event: 'message.interim',
        ...(text !== undefined ? { text } : {}),
        already_streamed: payload.already_streamed !== false,
      };
    case 'tool.start':
      return {
        ...base,
        event: 'tool.started',
        tool_call_id: String(payload.tool_id ?? ''),
        tool: String(payload.name ?? 'tool'),
        preview: String(
          payload.preview ??
            payload.args_text ??
            (payload.args ? JSON.stringify(payload.args, null, 2) : (payload.context ?? '')),
        ),
        ...(typeof payload.context === 'string' && payload.context.trim()
          ? { context: payload.context.trim() }
          : {}),
      };
    case 'tool.complete': {
      const result = payload.result;
      return {
        ...base,
        event: 'tool.completed',
        tool_call_id: String(payload.tool_id ?? ''),
        preview: String(
          payload.result_text ??
            payload.summary ??
            (typeof result === 'string' ? result : JSON.stringify(result ?? '', null, 2)),
        ),
        duration: typeof payload.duration_s === 'number' ? payload.duration_s : 0,
        error:
          payload.error === true ||
          payload.is_error === true ||
          (result !== null &&
            typeof result === 'object' &&
            (('error' in result && !!result.error) ||
              ('success' in result && result.success === false) ||
              ('ok' in result && result.ok === false) ||
              ('exit_code' in result &&
                typeof result.exit_code === 'number' &&
                result.exit_code !== 0))),
      };
    }
    case 'tool.generating':
      return {
        ...base,
        event: 'tool.generating',
        tool: String(payload.name ?? 'tool'),
      };
    case 'approval.request':
    case 'clarify.request':
      return {
        ...base,
        event: frame.type,
        prompt_id: String(payload.prompt_id ?? ''),
        execution_generation:
          frame.execution_generation ?? Number(payload.execution_generation ?? 0),
        ...(typeof payload.command === 'string' ? { command: payload.command } : {}),
        ...(typeof payload.description === 'string' ? { description: payload.description } : {}),
        ...(Array.isArray(payload.choices)
          ? {
              choices: payload.choices.filter(
                (choice): choice is string => typeof choice === 'string',
              ),
            }
          : {}),
        ...(typeof payload.question === 'string' ? { question: payload.question } : {}),
        ...(typeof payload.multi_select === 'boolean'
          ? { multi_select: payload.multi_select }
          : {}),
      };
    case 'approval.settled':
    case 'clarify.settled':
      return { ...base, event: frame.type, prompt_id: String(payload.prompt_id ?? '') };
    case 'message.complete': {
      const status = payload.status;
      const event =
        status === 'error'
          ? 'run.failed'
          : status === 'interrupted'
            ? 'run.interrupted'
            : 'run.completed';
      const output = typeof payload.text === 'string' ? payload.text : undefined;
      return {
        ...base,
        event: run.stopRequested && status === 'interrupted' ? 'run.cancelled' : event,
        ...(output !== undefined ? { output } : {}),
        ...(typeof payload.error === 'string' ? { error: payload.error } : {}),
        ...(typeof payload.failure_reason === 'string'
          ? { turn_exit_reason: payload.failure_reason }
          : {}),
      };
    }
    default:
      return undefined;
  }
}
