import { z } from 'zod';
import { idSchema } from './entities';
import { eventSchema, liveSchema } from './events';
import { rpcRequestSchema } from './rpc';
import { rpcErrorSchema } from './errors';
import { notificationSchema } from './notifications';
export const envelopeSchema = z
  .strictObject({
    v: z.literal(1),
    id: z.uuidv4(),
    type: z.enum([
      'hello',
      'hello.ok',
      'rpc.req',
      'rpc.res',
      'event',
      'live',
      'error',
      'ping',
      'pong',
      'node.status',
      'transfer.req',
      'transfer.res',
      'tunnel.open',
      'notify',
      'notify.ack',
    ]),
    nodeId: idSchema.optional(),
    replyTo: z.uuidv4().optional(),
    payload: z.unknown(),
  })
  .superRefine((value, ctx) => {
    if (value.type === 'rpc.res' && !value.replyTo)
      ctx.addIssue({
        code: 'custom',
        path: ['replyTo'],
        message: 'Response requires request identity',
      });
    if (value.type === 'rpc.req' && !value.nodeId)
      ctx.addIssue({
        code: 'custom',
        path: ['nodeId'],
        message: 'Client RPC requires destination node',
      });
  });
export const helloSchema = z.union([
  z.strictObject({ token: z.string().min(1) }),
  z.strictObject({ nodeToken: z.string().min(1), version: z.string().min(1) }),
]);
export const payloadSchemas = {
  hello: helloSchema,
  'hello.ok': z.strictObject({}),
  'rpc.req': rpcRequestSchema,
  'rpc.res': z.discriminatedUnion('ok', [
    z.strictObject({ ok: z.literal(true), result: z.unknown() }),
    z.strictObject({ ok: z.literal(false), error: rpcErrorSchema }),
  ]),
  event: eventSchema,
  live: liveSchema,
  error: rpcErrorSchema,
  ping: z.strictObject({}),
  pong: z.strictObject({}),
  'node.status': z.strictObject({ online: z.boolean() }),
  notify: notificationSchema,
  'notify.ack': z.strictObject({ notificationId: z.string().min(1).max(240) }),
};
export const protocolTimings = {
  helloMs: 5000,
  pingMs: 25000,
  pongTimeoutMs: 60000,
  rpcTimeoutMs: 30000,
} as const;
export type Envelope = z.infer<typeof envelopeSchema>;
