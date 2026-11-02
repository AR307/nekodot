import { expect, it } from 'vitest';
import { projectGatewayEvent } from './app';
import type { RunRecord } from './database';

const run = { runId: 'current-user-admission' } as RunRecord;

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
