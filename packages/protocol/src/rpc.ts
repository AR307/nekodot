import { z } from 'zod';
import {
  botFields,
  approvalChoiceSchema,
  approvalModeSchema,
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
import { screenStatusSchema } from './screen';
import {
  memoryDocumentSchema,
  nativeRecordSchema,
  operationSchema,
  extensionSchema,
  attachmentSchema,
} from './capabilities';
const empty = z.strictObject({});
const botTarget = { botId: botSchema.shape.botId };
const groupCreate = z
  .strictObject(groupFields)
  .refine((g) => g.botIds.includes(g.leadBotId), 'Lead must be a member');
const providerSettings = {
  baseUrl: z.url().optional(),
  defaultModel: z.string().min(1).optional(),
};
export const providerInputSchema = z.discriminatedUnion('kind', [
  z.strictObject({
    kind: z.literal('openrouter'),
    apiKey: z.string().min(1).optional(),
    ...providerSettings,
  }),
  z.strictObject({
    kind: z.literal('custom'),
    apiKey: z.string().min(1).optional(),
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
  'bots.jobs': {
    params: z.strictObject(botTarget),
    result: z.strictObject({ jobs: z.array(nativeRecordSchema) }),
  },
  'bots.jobs.runs': {
    params: z.strictObject({ ...botTarget, jobId: idSchema }),
    result: z.strictObject({ job: nativeRecordSchema, runs: z.array(nativeRecordSchema) }),
  },
  'memory.get': {
    params: z.strictObject(botTarget),
    result: z.strictObject({
      documents: z.array(
        z.strictObject({ name: memoryDocumentSchema, content: z.string(), exists: z.boolean() }),
      ),
      pending: z.string(),
    }),
  },
  'memory.save': {
    params: z.strictObject({ ...botTarget, name: memoryDocumentSchema, content: z.string() }),
    result: empty,
  },
  'memory.refine': {
    params: z.strictObject({ ...botTarget, focus: z.string() }),
    result: operationSchema,
  },
  'memory.review': {
    params: z.strictObject({
      ...botTarget,
      kind: z.enum(['memory', 'skills']),
      action: z.enum(['approve', 'reject']),
      reviewId: z.string().regex(/^[a-zA-Z0-9_-]+$/),
    }),
    result: z.strictObject({ output: z.string() }),
  },
  'operations.get': { params: z.strictObject({ operationId: z.uuid() }), result: operationSchema },
  'operations.list': {
    params: empty,
    result: z.strictObject({ operations: z.array(operationSchema) }),
  },
  'extensions.list': {
    params: z.strictObject({ kind: z.enum(['skills', 'plugins']) }),
    result: z.strictObject({ entries: z.array(extensionSchema) }),
  },
  'extensions.content': {
    params: z.strictObject({
      botId: botSchema.shape.botId.optional(),
      name: idSchema,
      identifier: z.string().optional(),
    }),
    result: z.strictObject({ content: z.string() }),
  },
  'extensions.install': {
    params: z
      .strictObject({
        kind: z.enum(['skills', 'plugins']),
        botIds: z.array(botSchema.shape.botId).min(1),
        identifier: z.string().optional(),
        importId: z.uuid().optional(),
      })
      .refine((v) => Boolean(v.identifier) !== Boolean(v.importId), 'Choose one source'),
    result: operationSchema,
  },
  'extensions.toggle': {
    params: z.strictObject({
      kind: z.enum(['skills', 'plugins']),
      botIds: z.array(botSchema.shape.botId).min(1),
      name: idSchema,
      enabled: z.boolean(),
    }),
    result: operationSchema,
  },
  'extensions.configure': {
    params: z.strictObject({
      ...botTarget,
      name: idSchema,
      values: z.record(z.string(), z.json()),
    }),
    result: operationSchema,
  },
  'hermes.restart': { params: empty, result: operationSchema },
  'files.list': {
    params: z.strictObject({
      ...botTarget,
      search: z.string().optional(),
      type: z.string().optional(),
      messageId: idSchema.optional(),
    }),
    result: z.strictObject({ files: z.array(attachmentSchema) }),
  },
  'files.backfill': { params: z.strictObject(botTarget), result: operationSchema },
  'imports.create': { params: empty, result: z.strictObject({ importId: z.uuid() }) },
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
      aroundMessageId: idSchema.optional(),
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
    params: z.strictObject({ messageId: idSchema, choice: approvalChoiceSchema }),
    result: empty,
  },
  'bots.create': {
    params: z.strictObject({ ...botFields, approvalMode: approvalModeSchema.optional() }),
    result: z.strictObject({ bot: botSchema, conversation: conversationSchema }),
  },
  'bots.update': {
    params: z.strictObject({
      botId: botSchema.shape.botId,
      ...z.object(botFields).partial().shape,
      approvalMode: approvalModeSchema.optional(),
    }),
    result: z.strictObject({ bot: botSchema }),
  },
  'bots.archive': { params: z.strictObject({ botId: botSchema.shape.botId }), result: empty },
  'bots.permissions.get': {
    params: z.strictObject({ botId: botSchema.shape.botId }),
    result: z.strictObject({ mode: approvalModeSchema }),
  },
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
  'models.options': {
    params: z.strictObject({ refresh: z.boolean().optional() }),
    result: z.strictObject({ models: z.array(z.string()), warning: z.string().optional() }),
  },
  'screen.status': {
    params: z.strictObject(botTarget),
    result: screenStatusSchema,
  },
  'screen.start': { params: z.strictObject(botTarget), result: operationSchema },
  'screen.stop': {
    params: z.strictObject({ ...botTarget, force: z.boolean().optional() }),
    result: operationSchema,
  },
  'screen.control': {
    params: z.strictObject({
      ...botTarget,
      sessionId: z.uuid().optional(),
      action: z.enum(['take', 'release', 'force-release']),
    }),
    result: screenStatusSchema,
  },
} as const;
export type RpcMethod = keyof typeof rpcContracts;
export type RpcParams<M extends RpcMethod> = z.infer<(typeof rpcContracts)[M]['params']>;
export type RpcResult<M extends RpcMethod> = z.infer<(typeof rpcContracts)[M]['result']>;
const requests = Object.entries(rpcContracts).map(([method, contract]) =>
  z.strictObject({ method: z.literal(method), params: contract.params }),
);
export type RpcRequest = { [M in RpcMethod]: { method: M; params: RpcParams<M> } }[RpcMethod];
export const rpcRequestSchema = z.union(requests) as z.ZodType<RpcRequest>;
export function rpcResponseSchema<M extends RpcMethod>(
  method: M,
): z.ZodType<
  { ok: true; result: RpcResult<M> } | { ok: false; error: z.infer<typeof rpcErrorSchema> }
> {
  return z.discriminatedUnion('ok', [
    z.strictObject({ ok: z.literal(true), result: rpcContracts[method].result }),
    z.strictObject({ ok: z.literal(false), error: rpcErrorSchema }),
  ]) as z.ZodType<
    { ok: true; result: RpcResult<M> } | { ok: false; error: z.infer<typeof rpcErrorSchema> }
  >;
}
