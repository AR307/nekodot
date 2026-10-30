import { z } from 'zod';
import { approvalChoiceSchema } from './entities';
export const hermesSseEventSchema = z
  .looseObject({
    event: z.string().min(1),
    run_id: z.string(),
    timestamp: z.number(),
    seq: z.number().int().nonnegative(),
    delta: z.string().optional(),
    text: z.string().optional(),
    already_streamed: z.boolean().optional(),
    tool: z.string().optional(),
    preview: z.string().optional(),
    tool_call_id: z.string().optional(),
    duration: z.number().optional(),
    error: z.union([z.boolean(), z.string()]).optional(),
    output: z.string().optional(),
    turn_exit_reason: z.string().optional(),
    prompt_id: z.string().optional(),
    execution_generation: z.number().int().optional(),
    command: z.string().optional(),
    description: z.string().optional(),
    accepted: z.boolean().optional(),
    pending_steer: z.string().optional(),
    status: z.string().optional(),
    usage: z.unknown().optional(),
    runtime: z.unknown().optional(),
    choices: z.array(z.string()).optional(),
    question: z.string().optional(),
    multi_select: z.boolean().optional(),
    kind: z.string().optional(),
    role: z.string().optional(),
  })
  .superRefine((event, ctx) => {
    if ((event.event === 'tool.started' || event.event === 'tool.completed') && !event.tool_call_id)
      ctx.addIssue({
        code: 'custom',
        message: 'Tool events must include tool_call_id',
        path: ['tool_call_id'],
      });
  });
export const hermesSteerResponseSchema = z.looseObject({
  run_id: z.string(),
  accepted: z.boolean(),
});
export const hermesCreateRunSchema = z.strictObject({
  input: z.string().min(1),
  session_id: z.string().optional(),
  instructions: z.string().optional(),
});
export const hermesRunCreatedSchema = z.looseObject({ run_id: z.string(), status: z.string() });
export const hermesApprovalSchema = z.strictObject({
  request_id: z.string(),
  execution_generation: z.number().int().nonnegative(),
  choice: approvalChoiceSchema,
});
export const hermesControlResponseSchema = z.looseObject({
  run_id: z.string(),
  status: z.string(),
  prompt_id: z.string().optional(),
});
export const hermesRunStateSchema = z.looseObject({
  run_id: z.string(),
  status: z.string(),
  output: z.string().optional(),
  error: z.string().optional(),
  turn_exit_reason: z.string().optional(),
  pending_steer: z.string().optional(),
  execution_generation: z.number().int().optional(),
  pending_controls: z
    .array(
      z.looseObject({
        prompt_id: z.string(),
        kind: z.string(),
        execution_generation: z.number().int().optional(),
        choices: z.array(z.string()).optional(),
        question: z.string().optional(),
        multi_select: z.boolean().optional(),
        timeout_s: z.number().optional(),
      }),
    )
    .optional(),
});
export type HermesRunState = z.infer<typeof hermesRunStateSchema>;
export type HermesEvent = z.infer<typeof hermesSseEventSchema>;
export const hermesModelOptionsSchema = z.looseObject({
  provider: z.string(),
  providers: z.array(
    z.looseObject({
      slug: z.string(),
      models: z.array(z.string()),
      is_current: z.boolean().optional(),
      warning: z.string().nullable().optional(),
    }),
  ),
});
