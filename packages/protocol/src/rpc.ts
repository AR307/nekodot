import { z } from 'zod';
import { flowSnapshotSchema } from './flow';
import { secretRequestSchema, savedSecretSchema, secretEnvelopeSchema } from './secrets';
import {
  routineInputSchema,
  routineSchema,
  routineExecutionSchema,
  routineReceiptSchema,
  routineDeliveryRecordSchema,
} from './routines';
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
  providerInputSchema,
  providerOutputSchema,
  modelInfoSchema,
  hermesSettingsSchema,
  hermesSharedSettingsSchema,
} from './providers';
import { userMemorySaveSchema, userMemoryViewSchema } from './user-memory';
import {
  memoryDocumentSchema,
  nativeRecordSchema,
  operationSchema,
  extensionSchema,
  attachmentSchema,
} from './capabilities';
const empty = z.strictObject({});
/** USER.md is capped by the smallest native user_char_limit among the Bots sharing it. */
const userMemoryLimitedViewSchema = userMemoryViewSchema.extend({
  limit: z.number().int().positive(),
});
const botTarget = { botId: botSchema.shape.botId };
/** Hermes `computer_use` readiness on the computer a desktop-hosted node runs on. */
export const desktopControlSchema = z.strictObject({
  platformSupported: z.boolean(),
  installed: z.boolean(),
  ready: z.boolean().nullable(),
  canGrant: z.boolean(),
  detail: z.string(),
});
export const nodeCapabilitiesSchema = z.strictObject({
  platform: z.string().min(1),
  /** Hermes-owned independent Bot screens (Linux servers). */
  computerUse: z.boolean(),
  /** Where the node runs: a server, or the desktop client on the user's own computer. */
  host: z.enum(['server', 'desktop']),
  /** Operating this computer's real desktop; null on servers. */
  desktopControl: desktopControlSchema.nullable(),
});
const groupCreate = z
  .strictObject(groupFields)
  .refine((g) => g.botIds.includes(g.leadBotId), 'Lead must be a member');
export const rpcContracts = {
  'secrets.get': {
    params: z.strictObject({ ...botTarget, requestId: idSchema }),
    result: z.strictObject({
      request: secretRequestSchema,
      publicKey: z.string(),
      saved: z.array(savedSecretSchema),
    }),
  },
  'secrets.submit': {
    params: z
      .strictObject({
        ...botTarget,
        requestId: idSchema,
        envelope: secretEnvelopeSchema.optional(),
        credentialId: z.string().optional(),
        save: z.boolean(),
      })
      .refine(
        (p) => Boolean(p.envelope) !== Boolean(p.credentialId),
        'Submit encrypted fields or a saved credential',
      ),
    result: secretRequestSchema,
  },
  'secrets.cancel': {
    params: z.strictObject({ ...botTarget, requestId: idSchema }),
    result: secretRequestSchema,
  },
  'secrets.list': {
    params: z.strictObject(botTarget),
    result: z.strictObject({ credentials: z.array(savedSecretSchema) }),
  },
  'secrets.replace': {
    params: z.strictObject({ ...botTarget, credentialId: idSchema }),
    result: secretRequestSchema,
  },
  'secrets.disable': {
    params: z.strictObject({ ...botTarget, credentialId: idSchema }),
    result: empty,
  },
  'commands.list': {
    params: z.strictObject(botTarget),
    result: z.strictObject({
      commands: z.array(
        z.strictObject({
          name: z.string(),
          description: z.string(),
          availability: z.enum(['available', 'app', 'terminal', 'not-integrated']),
          unavailableReason: z.string().optional(),
          skill: z.boolean(),
        }),
      ),
      warning: z.string(),
    }),
  },
  'voice.status': {
    params: z.strictObject({ botId: botSchema.shape.botId }),
    result: nativeRecordSchema,
  },
  'voice.start': {
    params: z.strictObject({ botId: botSchema.shape.botId }),
    result: nativeRecordSchema,
  },
  'voice.feed': {
    params: z.strictObject({
      botId: botSchema.shape.botId,
      listenerId: z.uuid(),
      pcm: z.string().min(1),
    }),
    result: nativeRecordSchema,
  },
  'voice.stop': {
    params: z.strictObject({ botId: botSchema.shape.botId, listenerId: z.uuid() }),
    result: empty,
  },
  'voice.transcribe': {
    params: z.strictObject({
      botId: botSchema.shape.botId,
      audio: z.string().startsWith('data:audio/wav;base64,'),
    }),
    result: operationSchema,
  },
  'commands.execute': {
    params: z.strictObject({
      ...botTarget,
      conversationId: idSchema,
      command: z.string().regex(/^\/[^\s]+(?:\s[\s\S]*)?$/),
      clientMsgId: z.uuid(),
    }),
    result: operationSchema,
  },
  'sessions.list': {
    params: z.strictObject(botTarget),
    result: z.strictObject({ sessions: z.array(nativeRecordSchema), currentSessionId: z.string() }),
  },
  'sessions.history': {
    params: z.strictObject({ ...botTarget, sessionId: idSchema }),
    result: z.object({ messages: z.array(nativeRecordSchema) }),
  },
  'learning.list': {
    params: z.strictObject(botTarget),
    result: z.object({
      buckets: z.array(nativeRecordSchema),
      summary: z.array(z.string()),
      count: z.number(),
    }),
  },
  'learning.get': {
    params: z.strictObject({ ...botTarget, id: z.string().min(1) }),
    result: nativeRecordSchema,
  },
  'learning.save': {
    params: z.strictObject({ ...botTarget, id: z.string().min(1), content: z.string().min(1) }),
    result: nativeRecordSchema,
  },
  'pets.list': {
    params: z.strictObject(botTarget),
    result: nativeRecordSchema,
  },
  'pets.thumbnail': {
    params: z.strictObject({ ...botTarget, slug: z.string().min(1), url: z.string() }),
    result: nativeRecordSchema,
  },
  'pets.manage': {
    params: z.discriminatedUnion('action', [
      z.strictObject({ ...botTarget, action: z.literal('select'), slug: z.string().min(1) }),
      z.strictObject({ ...botTarget, action: z.literal('disable') }),
      z.strictObject({ ...botTarget, action: z.literal('scale'), scale: z.number().positive() }),
      z.strictObject({
        ...botTarget,
        action: z.literal('generate'),
        prompt: z.string().min(1),
        provider: z.string().optional(),
        count: z.number().int().min(1).max(4).optional(),
      }),
      z.strictObject({
        ...botTarget,
        action: z.literal('hatch'),
        token: z.string().min(1),
        index: z.number().int().min(0),
        name: z.string().min(1),
        prompt: z.string().optional(),
        provider: z.string().optional(),
      }),
    ]),
    result: operationSchema,
  },
  'subscription.get': {
    params: z.strictObject(botTarget),
    result: nativeRecordSchema,
  },
  'routines.list': {
    params: z.strictObject(botTarget),
    result: z.strictObject({ routines: z.array(routineSchema) }),
  },
  'routines.approvalRespond': {
    params: z.strictObject({
      ...botTarget,
      executionId: z.string(),
      promptId: z.string(),
      choice: z.enum(['once', 'deny']),
    }),
    result: empty,
  },
  'routines.get': {
    params: z.strictObject({ ...botTarget, routineId: idSchema }),
    result: z.strictObject({
      routine: routineSchema,
      executions: z.array(routineExecutionSchema),
      receipts: z.array(routineDeliveryRecordSchema),
    }),
  },
  'routines.create': { params: routineInputSchema, result: routineSchema },
  'routines.update': {
    params: routineInputSchema.extend({ routineId: z.uuid() }),
    result: routineSchema,
  },
  'routines.enable': {
    params: z.strictObject({ ...botTarget, routineId: z.uuid(), enabled: z.boolean() }),
    result: routineSchema,
  },
  'routines.grant': {
    params: z.strictObject({ ...botTarget, routineId: z.uuid() }),
    result: routineSchema,
  },
  'routines.credentials': {
    params: z.strictObject({ ...botTarget, routineId: z.uuid() }),
    result: z.strictObject({ url: z.string(), secret: z.string() }),
  },
  'routines.rotate': {
    params: z.strictObject({ ...botTarget, routineId: z.uuid() }),
    result: routineSchema,
  },
  'routines.test': {
    params: z.strictObject({
      ...botTarget,
      routineId: z.uuid(),
      payload: z.record(z.string(), z.unknown()),
      requestId: z.string().min(1).max(240),
    }),
    result: routineReceiptSchema,
  },
  'memory.get': {
    params: z.strictObject(botTarget),
    result: z.strictObject({
      documents: z.array(
        z.strictObject({
          name: memoryDocumentSchema,
          content: z.string(),
          exists: z.boolean(),
          /** Hermes' native character limit for MEMORY.md and USER.md. */
          limit: z.number().int().positive().optional(),
        }),
      ),
      pending: z.string(),
    }),
  },
  'memory.save': {
    params: z.strictObject({
      ...botTarget,
      name: z.enum(['SOUL.md', 'MEMORY.md']),
      content: z.string(),
    }),
    result: empty,
  },
  'memory.user.get': { params: empty, result: userMemoryLimitedViewSchema },
  'memory.user.save': { params: userMemorySaveSchema, result: userMemoryLimitedViewSchema },
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
      kind: z.enum(['skills', 'plugins']),
      botId: botSchema.shape.botId.optional(),
      name: idSchema,
      identifier: z.string().optional(),
    }),
    result: z.strictObject({
      content: z.string(),
      files: z.array(z.string()),
      repository: z.url().optional(),
      icon: z.string().optional(),
    }),
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
  'files.get': {
    params: z.strictObject({ fileId: z.uuid() }),
    result: attachmentSchema,
  },
  'files.receive': {
    params: z.strictObject({
      conversationId: idSchema,
      importId: z.uuid(),
      path: z.string().min(1),
    }),
    result: attachmentSchema,
  },
  'files.backfill': { params: z.strictObject(botTarget), result: operationSchema },
  'imports.create': { params: empty, result: z.strictObject({ importId: z.uuid() }) },
  'flow.get': {
    params: z.strictObject({ conversationId: idSchema }),
    result: z.strictObject({ flow: flowSnapshotSchema.nullable() }),
  },
  'sync.snapshot': {
    params: empty,
    result: z.strictObject({
      bots: z.array(botSchema),
      groups: z.array(groupSchema),
      conversations: z.array(conversationSchema),
      // Each conversation's newest words, so a list previews it before it is opened.
      latest: z.array(messageSchema),
      flows: z.array(flowSnapshotSchema),
      headSeq: seqSchema,
      node: nodeCapabilitiesSchema,
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
      text: z.string(),
      files: z.array(z.uuid()).optional(),
      routineExecutionId: z.string().min(1).optional(),
      clientMsgId: z.uuidv4(),
    }),
    result: z.strictObject({ messageId: idSchema }),
  },
  'runs.stop': { params: z.strictObject({ conversationId: idSchema }), result: empty },
  'approvals.respond': {
    params: z.strictObject({ messageId: idSchema, choice: approvalChoiceSchema }),
    result: empty,
  },
  'questions.respond': {
    params: z.strictObject({ messageId: idSchema, answer: z.string().min(1).max(16384) }),
    result: empty,
  },
  'bots.create': {
    params: z.strictObject({
      ...botFields,
      handle: z.union([z.literal(''), botFields.handle]).optional(),
      sourceId: idSchema,
      approvalMode: approvalModeSchema.optional(),
      archiveFileId: idSchema.optional(),
    }),
    result: z.strictObject({ bot: botSchema, conversation: conversationSchema }),
  },
  'bots.welcome.retry': {
    params: z.strictObject({ messageId: idSchema }),
    result: z.strictObject({ messageId: idSchema }),
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
  'providers.list': {
    params: empty,
    result: z.strictObject({
      sources: z.array(providerOutputSchema),
      oauth: z.array(nativeRecordSchema),
    }),
  },
  'providers.set': { params: providerInputSchema, result: providerOutputSchema },
  'providers.authorize': {
    params: z.strictObject({
      provider: idSchema,
      action: z.enum(['start', 'poll', 'cancel', 'disconnect']),
      sessionId: idSchema.optional(),
    }),
    result: nativeRecordSchema,
  },
  'models.options': {
    params: z.strictObject({ sourceId: idSchema, refresh: z.boolean().optional() }),
    result: z.strictObject({ models: z.array(z.string()), warning: z.string().optional() }),
  },
  'models.info': { params: z.strictObject(botTarget), result: modelInfoSchema },
  'models.assign': {
    params: z.strictObject({
      ...botTarget,
      key: z.string().min(1),
      sourceId: idSchema,
      model: z.string().min(1),
    }),
    result: z.strictObject({ saved: z.literal(true) }),
  },
  'hermes.settings.get': { params: z.strictObject(botTarget), result: hermesSettingsSchema },
  'hermes.settings.set': {
    params: z.strictObject({ ...botTarget, key: z.string().min(1), value: z.json() }),
    result: z.strictObject({ key: z.string(), saved: z.literal(true) }),
  },
  'hermes.shared.get': { params: empty, result: hermesSharedSettingsSchema },
  'hermes.shared.set': {
    params: z.strictObject({ key: z.string().min(1), value: z.json() }),
    result: z.strictObject({
      key: z.string(),
      saved: z.literal(true),
      profiles: z.number().int().nonnegative(),
    }),
  },
  'screen.status': {
    params: z.strictObject(botTarget),
    result: screenStatusSchema,
  },
  'desktop.status': { params: empty, result: nodeCapabilitiesSchema },
  'bots.desktopControl': {
    params: z.strictObject({ ...botTarget, enabled: z.boolean().optional() }),
    result: z.strictObject({ enabled: z.boolean() }),
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
