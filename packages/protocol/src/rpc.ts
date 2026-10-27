import { z } from 'zod';
import {
  botFields,
  botSchema,
  conversationSchema,
  groupFields,
  groupSchema,
  idSchema,
  messageSchema,
  seqSchema,
} from './entities';
import { eventSchema } from './events';
import { rpcErrorSchema } from './errors';
const empty = z.strictObject({});
const groupCreate = z
  .strictObject(groupFields)
  .refine((g) => g.botIds.includes(g.leadBotId), 'Lead must be a member');
const providerSettings = {
  baseUrl: z.url().optional(),
  defaultModel: z.string().min(1).optional(),
};
export const providerInputSchema = z.discriminatedUnion('kind', [
  z.strictObject({ kind: z.literal('openrouter'), apiKey: z.string().min(1), ...providerSettings }),
  z.strictObject({
    kind: z.literal('custom'),
    apiKey: z.string().min(1),
    ...providerSettings,
    baseUrl: z.url(),
  }),
]);
export const providerOutputSchema = z.strictObject({
  kind: z.enum(['openrouter', 'custom']),
  ...providerSettings,
  apiKeyLast4: z.string().max(4),
});
export const rpcContracts = {
  'sync.snapshot': {
    params: empty,
    result: z.strictObject({
      bots: z.array(botSchema),
      groups: z.array(groupSchema),
      conversations: z.array(conversationSchema),
      headSeq: seqSchema,
      node: z.strictObject({ platform: z.string().min(1), computerUse: z.boolean() }),
    }),
  },
  'sync.since': {
    params: z.strictObject({ seq: seqSchema }),
    result: z.strictObject({
      events: z.array(eventSchema).max(1000),
      headSeq: seqSchema,
      resyncRequired: z.boolean(),
    }),
  },
  'messages.list': {
    params: z.strictObject({
      conversationId: idSchema,
      beforeSeq: seqSchema.optional(),
      limit: z.number().int().min(1).max(50),
    }),
    result: z.strictObject({ messages: z.array(messageSchema) }),
  },
  'messages.send': {
    params: z.strictObject({
      conversationId: idSchema,
      text: z.string().min(1),
      clientMsgId: z.uuidv4(),
    }),
    result: z.strictObject({ messageId: idSchema }),
  },
  'runs.stop': { params: z.strictObject({ conversationId: idSchema }), result: empty },
  'approvals.respond': {
    params: z.strictObject({ messageId: idSchema, choice: z.enum(['once', 'deny']) }),
    result: empty,
  },
  'bots.create': { params: z.strictObject(botFields), result: z.strictObject({ bot: botSchema }) },
  'bots.update': {
    params: z.strictObject({
      botId: botSchema.shape.botId,
      ...z.object(botFields).partial().shape,
    }),
    result: z.strictObject({ bot: botSchema }),
  },
  'bots.archive': { params: z.strictObject({ botId: botSchema.shape.botId }), result: empty },
  'groups.create': { params: groupCreate, result: z.strictObject({ group: groupSchema }) },
  'groups.update': {
    params: z
      .strictObject({ groupId: idSchema, ...z.object(groupFields).partial().shape })
      .refine(
        (g) => !g.botIds || !g.leadBotId || g.botIds.includes(g.leadBotId),
        'Lead must be a member',
      ),
    result: z.strictObject({ group: groupSchema }),
  },
  'groups.archive': { params: z.strictObject({ groupId: idSchema }), result: empty },
  'providers.get': { params: empty, result: providerOutputSchema.nullable() },
  'providers.set': { params: providerInputSchema, result: providerOutputSchema },
  'models.options': { params: empty, result: z.unknown() },
  'screen.status': {
    params: empty,
    result: z.strictObject({ available: z.boolean(), running: z.boolean() }),
  },
} as const;
export type RpcMethod = keyof typeof rpcContracts;
export type RpcParams<M extends RpcMethod> = z.infer<(typeof rpcContracts)[M]['params']>;
export type RpcResult<M extends RpcMethod> = z.infer<(typeof rpcContracts)[M]['result']>;
const requests = Object.entries(rpcContracts).map(([method, contract]) =>
  z.strictObject({ method: z.literal(method), params: contract.params }),
);
export const rpcRequestSchema = z.union(requests);
export function rpcResponseSchema<M extends RpcMethod>(method: M) {
  return z.discriminatedUnion('ok', [
    z.strictObject({ ok: z.literal(true), result: rpcContracts[method].result }),
    z.strictObject({ ok: z.literal(false), error: rpcErrorSchema }),
  ]);
}
