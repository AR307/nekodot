import { z } from 'zod';

export const routineInputSchema = z.strictObject({
  botId: z.string().regex(/^nk-[a-z2-7]{6}$/),
  name: z.string().trim().min(1),
  description: z.string(),
  prompt: z.string().min(1),
  events: z.array(z.string()).default([]),
  skills: z.array(z.string()).default([]),
  cronJobId: z.string().optional(),
});
export const routineSchema = routineInputSchema.extend({
  routineId: z.string(),
  conversationId: z.string().optional(),
  trigger: z.enum(['schedule', 'webhook', 'both']),
  enabled: z.boolean(),
  granted: z.boolean(),
  url: z.string(),
  createdAt: z.string(),
  permissions: z.string(),
  native: z.record(z.string(), z.unknown()).optional(),
});
export const routineExecutionSchema = z.strictObject({
  executionId: z.string(),
  routineId: z.string(),
  sessionId: z.string(),
  admissionId: z.string().optional(),
  requestId: z.string().optional(),
  state: z.enum([
    'running',
    'waiting_approval',
    'waiting_question',
    'completed',
    'failed',
    'cancelled',
  ]),
  originSessionId: z.string().optional(),
  text: z.string(),
  reason: z.string().optional(),
  updatedAt: z.string(),
});
export const cronApprovalPolicySchema = z.strictObject({
  default: z.enum(['ask', 'approve', 'deny']),
  timezone: z.string().min(1),
  windows: z
    .array(
      z.strictObject({
        start: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/),
        end: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/),
        days: z.array(z.number().int().min(0).max(6)).min(1),
        mode: z.enum(['ask', 'approve', 'deny']),
      }),
    )
    .max(12),
});
export type CronApprovalPolicy = z.infer<typeof cronApprovalPolicySchema>;
export const routineRouteSchema = z.strictObject({
  routineId: z.uuid(),
  botId: z.string(),
  digest: z.string().regex(/^[a-f0-9]{64}$/),
  enabled: z.boolean(),
});
export const routineDeliverySchema = z.strictObject({
  routineId: z.uuid(),
  digest: z.string(),
  requestId: z.string().min(1).max(240),
  body: z.string().max(1_048_576),
});
export const routineReceiptSchema = z.strictObject({
  status: z.number().int().min(200).max(599),
  body: z.record(z.string(), z.unknown()),
});
export const routineDeliveryRecordSchema = routineReceiptSchema.extend({
  requestId: z.string(),
  receivedAt: z.string(),
});
export type Routine = z.infer<typeof routineSchema>;
export type RoutineInput = z.infer<typeof routineInputSchema>;
export type RoutineExecution = z.infer<typeof routineExecutionSchema>;
export type RoutineRoute = z.infer<typeof routineRouteSchema>;
export type RoutineDelivery = z.infer<typeof routineDeliverySchema>;
export type RoutineReceipt = z.infer<typeof routineReceiptSchema>;
