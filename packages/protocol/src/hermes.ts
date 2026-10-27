import { z } from 'zod';
export const hermesSseEventSchema = z.looseObject({
  event: z.string().min(1),
  run_id: z.string(),
  timestamp: z.number(),
  seq: z.number().int().nonnegative(),
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
  choice: z.enum(['once', 'deny']),
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
  execution_generation: z.number().int().optional(),
  pending_controls: z
    .array(
      z.looseObject({
        prompt_id: z.string(),
        kind: z.string(),
        execution_generation: z.number().int().optional(),
      }),
    )
    .optional(),
});
export type HermesRunState = z.infer<typeof hermesRunStateSchema>;
