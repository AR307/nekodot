import { z } from 'zod';

export const errorCodes = [
  'invalid_params',
  'unauthorized',
  'forbidden',
  'not_found',
  'conflict',
  'timeout',
  'unavailable',
  'internal_error',
] as const;
export const rpcErrorSchema = z.strictObject({ code: z.enum(errorCodes), message: z.string() });
export type RpcError = z.infer<typeof rpcErrorSchema>;
