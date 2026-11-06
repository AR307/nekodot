import { expect, it } from 'vitest';
import { projectGatewayEvent } from './app';
import type { RunRecord } from './database';

const run = { runId: 'current-user-admission' } as RunRecord;

it('projects the native plan only for the current chat admission, not a background routine', () => {
  const frame = {
    type: 'todo.updated',
    admission_id: run.runId,
    payload: {
      todos: [{ id: 'inspect', content: 'Inspect files', status: 'in_progress' }],
      revision: 2,
    },
  };
  expect(projectGatewayEvent(run, frame)).toMatchObject({
    event: 'todo.updated',
    todo_state: frame.payload,
  });
  expect(projectGatewayEvent(run, { ...frame, admission_id: 'cron-admission' })).toBeUndefined();
});

it('shows native research tool arguments and results without verbose mode', () => {
  expect(
    projectGatewayEvent(run, {
      type: 'tool.start',
      admission_id: run.runId,
      payload: {
        tool_id: 'search',
        name: 'web_search',
        args: { query: 'tool output verification' },
      },
    }),
  ).toMatchObject({
    tool: 'web_search',
    preview: JSON.stringify({ query: 'tool output verification' }, null, 2),
  });
  expect(
    projectGatewayEvent(run, {
      type: 'tool.complete',
      admission_id: run.runId,
      payload: {
        tool_id: 'search',
        name: 'web_search',
        duration_s: 1.4,
        result: { results: [{ title: 'Research paper' }] },
      },
    }),
  ).toMatchObject({
    preview: JSON.stringify({ results: [{ title: 'Research paper' }] }, null, 2),
    error: false,
  });
  expect(
    projectGatewayEvent(run, {
      type: 'tool.complete',
      admission_id: run.runId,
      payload: {
        tool_id: 'code',
        name: 'execute_code',
        result: { success: false, error: 'Execution failed' },
      },
    }),
  ).toMatchObject({ error: true, preview: expect.stringContaining('Execution failed') });
  expect(
    projectGatewayEvent(run, {
      type: 'tool.complete',
      admission_id: run.runId,
      payload: {
        tool_id: 'python',
        name: 'terminal',
        result: { output: 'Traceback', exit_code: 1 },
      },
    }),
  ).toMatchObject({ error: true, preview: expect.stringContaining('Traceback') });
});

it('does not attach a child callback completion to the next user turn in the same session', () => {
  expect(
    projectGatewayEvent(run, {
      type: 'message.complete',
      admission_id: 'child-notification-admission',
      payload: { status: 'complete', text: 'The child was interrupted.' },
    }),
  ).toBeUndefined();
  expect(
    projectGatewayEvent(run, {
      type: 'message.delta',
      admission_id: 'child-notification-admission',
      payload: { text: 'Unrelated streamed reply' },
    }),
  ).toBeUndefined();
  expect(
    projectGatewayEvent(run, {
      type: 'message.complete',
      admission_id: run.runId,
      payload: { status: 'complete', text: 'The requested task finished.' },
    }),
  ).toMatchObject({ event: 'run.completed', output: 'The requested task finished.' });
});

it('accepts a native receipt completion identifying its admission inside the payload', () => {
  expect(
    projectGatewayEvent(run, {
      type: 'message.complete',
      payload: { admission_id: run.runId, status: 'interrupted' },
    }),
  ).toMatchObject({ event: 'run.interrupted', run_id: run.runId });
});

it('keeps Hermes’s one-line label of a step beside its full arguments', () => {
  expect(
    projectGatewayEvent(run, {
      type: 'tool.start',
      admission_id: run.runId,
      payload: {
        tool_id: 'open',
        name: 'browser_navigate',
        context: 'https://x.com/nekodot',
        args: { url: 'https://x.com/nekodot' },
      },
    }),
  ).toMatchObject({
    tool: 'browser_navigate',
    context: 'https://x.com/nekodot',
    preview: JSON.stringify({ url: 'https://x.com/nekodot' }, null, 2),
  });
});
