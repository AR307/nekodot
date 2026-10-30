import { describe, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import {
  botSchema,
  conversationSchema,
  envelopeSchema,
  eventSchema,
  groupSchema,
  helloSchema,
  liveSchema,
  messageSchema,
  providerOutputSchema,
  rpcContracts,
  rpcRequestSchema,
  rpcResponseSchema,
  avatarSchema,
  avatarShapes,
} from './index';
const date = '2026-10-27T08:00:00.000Z';
const bot = {
  botId: 'nk-abcdef',
  displayName: '研究员',
  handle: 'research',
  avatar: { shape: 'dot', color: '#E8603C' },
  role: '研究',
  model: 'custom-model',
  archived: false,
  createdAt: date,
};
const group = {
  groupId: 'group-1',
  name: '研究小队',
  botIds: ['nk-abcdef', 'nk-ghijkl'],
  leadBotId: 'nk-abcdef',
  archived: false,
  createdAt: date,
};
const conversation = { conversationId: 'dm-1', kind: 'dm', botId: bot.botId, createdAt: date };
const message = {
  messageId: 'msg-1',
  conversationId: 'dm-1',
  seq: 1,
  author: { type: 'bot', id: bot.botId },
  kind: 'text',
  status: 'streaming',
  content: { text: '你好' },
  createdAt: date,
};
describe('real product protocol journeys', () => {
  it('create bot, open DM, send, stream and reconcile full message', () => {
    expect(botSchema.parse(bot)).toEqual(bot);
    expect(conversationSchema.parse(conversation)).toEqual(conversation);
    expect(
      rpcRequestSchema.parse({
        method: 'messages.send',
        params: { conversationId: 'dm-1', text: '研究一下', clientMsgId: randomUUID() },
      }),
    ).toBeDefined();
    expect(
      liveSchema.parse({
        kind: 'delta',
        offset: 0,
        conversationId: 'dm-1',
        messageId: 'msg-1',
        text: '你好',
      }),
    ).toBeDefined();
    expect(eventSchema.parse({ seq: 1, kind: 'message.upserted', data: message })).toBeDefined();
    expect(
      rpcResponseSchema('messages.list').parse({ ok: true, result: { messages: [message] } }),
    ).toBeDefined();
  });
  it('approval card supports native Hermes scopes and streaming tool state', () => {
    expect(
      messageSchema.parse({
        ...message,
        kind: 'tool',
        content: { tool: 'terminal', preview: 'pwd', durationMs: 2, error: false },
      }),
    ).toBeDefined();
    expect(
      messageSchema.parse({
        ...message,
        kind: 'approval',
        content: {
          runId: 'run-1',
          botId: bot.botId,
          requestId: 'prompt-1',
          executionGeneration: 1,
          prompt: 'Write test file?',
        },
      }),
    ).toBeDefined();
    expect(
      rpcContracts['approvals.respond'].params.safeParse({ messageId: 'msg-1', choice: 'always' })
        .success,
    ).toBe(true);
    expect(messageSchema.safeParse({ ...message, status: 'running' }).success).toBe(false);
    expect(
      messageSchema.safeParse({ ...message, kind: 'approval', content: { text: '?' } }).success,
    ).toBe(false);
  });
  it('avatar accepts every shape and nothing else', () => {
    for (const shape of avatarShapes) {
      expect(avatarSchema.parse({ shape, color: '#E8603C' }).shape).toBe(shape);
    }
    expect(() => avatarSchema.parse({ shape: 'dragon', color: '#E8603C' })).toThrow();
  });

  it('group lead belongs to 2–6 unique members', () => {
    expect(groupSchema.parse(group)).toEqual(group);
    for (const changed of [
      { botIds: [bot.botId] },
      { leadBotId: 'nk-mnopqr' },
      { botIds: [bot.botId, bot.botId] },
    ])
      expect(groupSchema.safeParse({ ...group, ...changed }).success).toBe(false);
  });
  it('relay parses only envelope, destination and response identity', () => {
    expect(
      envelopeSchema.parse({
        v: 1,
        id: randomUUID(),
        nodeId: 'node-1',
        type: 'rpc.req',
        payload: { future: 'opaque to relay' },
      }),
    ).toBeDefined();
    expect(
      envelopeSchema.safeParse({ v: 1, id: randomUUID(), type: 'rpc.req', payload: {} }).success,
    ).toBe(false);
    expect(envelopeSchema.safeParse({ v: 1, id: 'bad', type: 'ping', payload: {} }).success).toBe(
      false,
    );
    expect(
      envelopeSchema.safeParse({ v: 1, id: randomUUID(), type: 'rpc.res', payload: {} }).success,
    ).toBe(false);
    expect(helloSchema.safeParse({ token: 'local-test-token' }).success).toBe(true);
    expect(helloSchema.safeParse({ token: '' }).success).toBe(false);
  });
  it('bounded history, sync and provider outputs', () => {
    expect(
      rpcContracts['messages.list'].params.safeParse({ conversationId: 'dm-1', limit: 51 }).success,
    ).toBe(false);
    expect(rpcContracts['sync.since'].params.safeParse({ seq: -1 }).success).toBe(false);
    expect(
      providerOutputSchema.safeParse({
        kind: 'custom',
        baseUrl: 'https://example.invalid/v1',
        apiKeyLast4: 'abcd',
        apiKey: 'secret',
      }).success,
    ).toBe(false);
    expect(rpcRequestSchema.safeParse({ method: 'unknown', params: {} }).success).toBe(false);
    expect(rpcResponseSchema('messages.send').safeParse({ ok: true, result: {} }).success).toBe(
      false,
    );
  });
});
