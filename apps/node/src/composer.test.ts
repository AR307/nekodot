import { randomUUID } from 'node:crypto';
import { mkdtemp, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { setTimeout as delay } from 'node:timers/promises';
import { expect, it } from 'vitest';
import { startFakeHermes, recordedManagementRuntime } from '@nekodot/fake-hermes';
import { rpcRequestSchema, type Operation } from '@nekodot/protocol';
import { NodeApplication } from './app';
import { HermesApi } from './hermes/api';

it('uploads a user file, sends images natively, and executes a selected group member’s native command', async () => {
  const home = await mkdtemp(join(tmpdir(), 'nekodot-composer-'));
  const key = 'composer-test-only';
  const fake = await startFakeHermes({
    fixturesDirectory: join(process.cwd(), 'docs/fixtures'),
    profiles: ['default'],
    apiKey: key,
    allowProfileCreate: true,
    eventDelayMs: 1,
    scenarioFor: () => 'runs-basic',
  });
  const runtime = {
    ...recordedManagementRuntime(fake.url, key, home, fake.pluginCatalog),
    start: async () => {},
    close: async () => {},
    approvalMode: async () => 'manual' as const,
    api: async (profile: string) => new HermesApi(fake.url + '/p/' + profile, key),
    configureBot: async (bot: { botId: string }) => {
      await fetch(fake.url + '/test/profiles', {
        method: 'POST',
        headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
        body: JSON.stringify({ profile: bot.botId }),
      });
    },
  };
  const app = new NodeApplication(home, runtime);
  const rpc = (method: string, params: unknown) =>
    app.handle(rpcRequestSchema.parse({ method, params }));
  const until = async (ready: () => boolean) => {
    const deadline = Date.now() + 8000;
    while (!ready() && Date.now() < deadline) await delay(10);
    expect(ready()).toBe(true);
  };
  try {
    const source = await app.providers.set({
      kind: 'custom',
      name: 'Recorded API',
      baseUrl: 'https://example.test/v1',
      apiKey: key,
    });
    const create = (handle: string) =>
      app.bots.create({
        sourceId: source.sourceId,
        displayName: handle,
        handle,
        role: 'Test assistant',
        model: 'recorded-model',
        avatar: { shape: 'dot', color: '#E8603C' },
      });
    const lead = await create('lead'),
      writer = await create('writer');
    const upload = async (name: string, bytes: Buffer) => {
      const { importId } = await app.files.createImport();
      await app.files.transfer({
        action: 'write',
        importId,
        path: name,
        offset: 0,
        data: bytes.toString('base64'),
      });
      return app.files.receive({
        conversationId: lead.conversation.conversationId,
        importId,
        path: name,
      });
    };
    const text = await upload('中文资料.txt', Buffer.from('Attached test content.'));
    const image = await upload('图片.png', Buffer.from('image-input-transport-specimen'));
    // The replay only verifies native image transport, never claims image recognition.
    const send = {
      conversationId: lead.conversation.conversationId,
      clientMsgId: randomUUID(),
      text: 'Inspect files',
      files: [text.fileId, image.fileId],
    };
    await expect(
      rpc('messages.send', { ...send, files: [text.fileId, randomUUID()] }),
    ).rejects.toThrow();
    expect(app.files.get(text.fileId).messageId).toBe(text.fileId);
    const sent = await rpc('messages.send', send);
    expect(await rpc('messages.send', send)).toEqual(sent);
    await until(() => !app.database.runs().length);
    expect(fake.inspectRuns()).toHaveLength(1);
    const input = fake.inspectRuns()[0]!.nativeInput;
    expect(typeof input).not.toBe('string');
    if (typeof input === 'string') throw new Error('Missing native multimodal input');
    expect(input[0]!.content.some((part) => part.type === 'image_url')).toBe(true);
    expect(app.files.list({ botId: lead.bot.botId })).toEqual([]);
    const received = await app.files.transfer({ action: 'read', fileId: text.fileId, offset: 0 });
    if (!received.ok) throw new Error(received.error);
    expect(Buffer.from(received.data!, 'base64').toString()).toBe('Attached test content.');
    expect(
      await readFile(
        join(runtime.profileHome(lead.bot.botId), 'uploads', text.fileId, text.name),
        'utf8',
      ),
    ).toBe('Attached test content.');
    const group = app.groups.create({
      name: 'Composer test',
      botIds: [lead.bot.botId, writer.bot.botId],
      leadBotId: lead.bot.botId,
    });
    const conversation = app.database
      .conversations()
      .find((c) => c.kind === 'group' && c.groupId === group.group.groupId)!;
    const command = {
      botId: writer.bot.botId,
      conversationId: conversation.conversationId,
      command: '/profile',
      clientMsgId: randomUUID(),
    };
    const operation = (await rpc('commands.execute', command)) as Operation;
    expect(await rpc('commands.execute', command)).toMatchObject({
      operationId: operation.operationId,
    });
    await until(() => app.operations.get(operation.operationId).status !== 'running');
    expect(app.operations.get(operation.operationId).status).toBe('done');
    expect(fake.inspectRuns()).toHaveLength(1);
    const newSession = (await rpc('commands.execute', {
      ...command,
      command: '/new',
      clientMsgId: randomUUID(),
    })) as Operation;
    await until(() => app.operations.get(newSession.operationId).status !== 'running');
    expect(app.operations.get(newSession.operationId)).toMatchObject({ status: 'failed' });
    expect(fake.inspectRuns()).toHaveLength(1);
    const plan = (await rpc('commands.execute', {
      ...command,
      command: '/plan Summarize the attached test file.',
      clientMsgId: randomUUID(),
    })) as Operation;
    await until(() => app.operations.get(plan.operationId).status !== 'running');
    await until(() => !app.database.runs().length);
    expect(app.operations.get(plan.operationId).status).toBe('done');
    expect(fake.inspectRuns().at(-1)?.profile).toBe(writer.bot.botId);
    const displayed = app.database
      .messages(conversation.conversationId)
      .find((message) => message.author.type === 'user');
    expect(displayed?.content).toEqual({ text: '/plan Summarize the attached test file.' });
  } finally {
    await app.close();
    runtime.management.close();
    await fake.close();
  }
});
