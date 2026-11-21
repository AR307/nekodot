import { expect, it } from 'vitest';
import { projectGatewayEvent } from './hermes/events';
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

it('passes the reasoning of the current admission on for the Dot’s status', () => {
  const frame = { type: 'reasoning.delta', admission_id: run.runId, payload: { text: 'Plan. ' } };
  expect(projectGatewayEvent(run, frame)).toMatchObject({
    event: 'reasoning.delta',
    delta: 'Plan. ',
  });
  expect(
    projectGatewayEvent(run, { ...frame, type: 'reasoning.available', payload: { text: 'All.' } }),
  ).toMatchObject({ event: 'reasoning.available', delta: 'All.' });
  expect(projectGatewayEvent(run, { ...frame, payload: { text: '' } })).toBeUndefined();
  expect(projectGatewayEvent(run, { ...frame, admission_id: 'cron-admission' })).toBeUndefined();
});

it('names the process a terminal call left running in the background', () => {
  const complete = (name: string, result: unknown) =>
    projectGatewayEvent(run, {
      type: 'tool.complete',
      admission_id: run.runId,
      payload: { tool_id: 'call', name, result },
    });
  const started = {
    output: 'Background process started',
    session_id: 'proc_4dae91c03b2f',
    pid: 4242,
    exit_code: 0,
    error: null,
    notify_on_complete: true,
  };
  expect(complete('terminal', started)).toMatchObject({ process_id: 'proc_4dae91c03b2f' });
  // Hermes moved a long foreground command to the background.
  expect(
    complete(
      'terminal',
      JSON.stringify({
        output: 'still running',
        exit_code: null,
        status: 'yielded_to_background',
        session_id: 'proc_0123456789ab',
      }),
    ),
  ).toMatchObject({ process_id: 'proc_0123456789ab' });
  expect(complete('terminal', { output: 'done', exit_code: 0 })).not.toHaveProperty('process_id');
  expect(complete('web_search', started)).not.toHaveProperty('process_id');
});
