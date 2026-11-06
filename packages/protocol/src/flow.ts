import { z } from 'zod';

export const flowStateSchema = z.enum([
  'pending',
  'running',
  'waiting',
  'done',
  'failed',
  'cancelled',
  'paused',
  'unknown',
]);
export const flowStepSchema = z.strictObject({
  stepId: z.string(),
  runId: z.string(),
  sessionId: z.string(),
  botId: z.string(),
  kind: z.enum([
    'bot',
    'plan',
    'thinking',
    'reply',
    'browser',
    'search',
    'read',
    'write',
    'code',
    'terminal',
    'approval',
    'question',
    'tool',
  ]),
  state: flowStateSchema,
  after: z.array(z.string()),
  tool: z.string().optional(),
  messageId: z.string().optional(),
  title: z.string().optional(),
  parentStepId: z.string().optional(),
});
const flowHeader = {
  flowId: z.string(),
  conversationId: z.string(),
  sessionId: z.string().optional(),
  state: flowStateSchema,
  queuedBotIds: z.array(z.string()),
  seq: z.number().int().nonnegative(),
};
export const flowSnapshotSchema = z.strictObject({
  ...flowHeader,
  steps: z.array(flowStepSchema),
});
export const flowChangeSchema = z.strictObject({
  ...flowHeader,
  reset: z.boolean(),
  steps: z.array(flowStepSchema),
});
export type FlowSnapshot = z.infer<typeof flowSnapshotSchema>;
export type FlowStep = z.infer<typeof flowStepSchema>;
export type FlowChange = z.infer<typeof flowChangeSchema>;
