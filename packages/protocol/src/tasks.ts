import { z } from 'zod';

/** A user requirement, not a second model execution engine. */
export const dotTaskSchema = z.strictObject({
  taskId: z.string().min(1),
  conversationId: z.string().min(1),
  botId: z.string().min(1),
  title: z.string().min(1),
  source: z.enum(['chat', 'group', 'schedule', 'webhook']),
  inputMessageId: z.string(),
  state: z.enum([
    'queued',
    'running',
    'waiting_approval',
    'waiting_question',
    'unknown',
    'completed',
    'failed',
    'cancelled',
  ]),
  executionId: z.string(),
  resultMessageId: z.string().optional(),
  reportMessageId: z.string().optional(),
  routineId: z.string().optional(),
  routineExecutionId: z.string().optional(),
  groupChainId: z.string().optional(),
  createdAt: z.string(),
  updatedAt: z.string(),
});

export type DotTask = z.infer<typeof dotTaskSchema>;
