import {
  createCipheriv,
  createPublicKey,
  diffieHellman,
  generateKeyPairSync,
  hkdfSync,
  randomBytes,
} from 'node:crypto';
import { mkdtemp, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { expect, it } from 'vitest';
import { parse } from 'yaml';
import type { SecretEnvelope } from '@nekodot/protocol';
import { NodeDatabase } from './database';
import { BotSecrets } from './secrets';
import { secretContext } from './secret-crypto';
import { installSecretsPlugin } from './hermes/secrets-plugin';
import type { HermesRuntime } from './hermes/runtime';
import type { HermesGateway } from './hermes/gateway';

function encrypt(
  publicKey: string,
  botId: string,
  requestId: string,
  fields: Record<string, string>,
): SecretEnvelope {
  const pair = generateKeyPairSync('x25519');
  const peer = createPublicKey({
    key: Buffer.concat([
      Buffer.from('302a300506032b656e032100', 'hex'),
      Buffer.from(publicKey, 'base64'),
    ]),
    type: 'spki',
    format: 'der',
  });
  const shared = diffieHellman({ privateKey: pair.privateKey, publicKey: peer });
  const salt = randomBytes(32),
    nonce = randomBytes(12),
    context = secretContext('qa-node', botId, requestId);
  const key = Buffer.from(hkdfSync('sha256', shared, salt, context, 32));
  const cipher = createCipheriv('aes-256-gcm', key, nonce);
  cipher.setAAD(context);
  return {
    version: 1,
    publicKey: pair.publicKey
      .export({ type: 'spki', format: 'der' })
      .subarray(-32)
      .toString('base64'),
    salt: salt.toString('base64'),
    nonce: nonce.toString('base64'),
    ciphertext: Buffer.concat([cipher.update(JSON.stringify(fields)), cipher.final()]).toString(
      'base64',
    ),
    tag: cipher.getAuthTag().toString('base64'),
  };
}

it('delivers a multiline key once, saves only when selected, and isolates references by Bot', async () => {
  const home = await mkdtemp(join(tmpdir(), 'nekodot-confidential-'));
  const db = new NodeDatabase(home);
  const gateways = new Map<string, Pick<HermesGateway, 'listeners' | 'onRequest'>>();
  const hermes = {
    gateway: (botId: string) => {
      if (!gateways.has(botId)) gateways.set(botId, { listeners: new Set(), onRequest: undefined });
      return gateways.get(botId)!;
    },
    profileHome: (bot: string) => join(home, 'profiles', bot),
    environment: async () => ({ NATIVE_QA: 'native-test-value' }),
  } as unknown as HermesRuntime;
  for (const botId of ['nk-abcdef', 'nk-bcdefg']) {
    db.putBot({
      botId,
      displayName: botId,
      handle: botId,
      role: '',
      model: 'qa',
      avatar: { shape: 'dot', color: '#E8603C' },
      archived: false,
      createdAt: new Date().toISOString(),
    });
    db.putConversation({
      kind: 'dm',
      botId,
      conversationId: botId,
      createdAt: new Date().toISOString(),
    });
    db.saveHermesSession({
      botId,
      conversationId: botId,
      storedSessionId: 'session-' + botId,
      replayEpoch: 'qa',
      lastSequence: 0,
    });
    db.saveRun({
      botId,
      conversationId: botId,
      inputMessageId: botId,
      runId: 'run-' + botId,
      sessionId: 'session-' + botId,
      storedSessionId: 'session-' + botId,
      state: 'thinking',
      lastSeq: 0,
    });
    await installSecretsPlugin(hermes.profileHome(botId));
  }
  let service = new BotSecrets(db, hermes);
  service.bind('qa-node');
  let continuations = 0;
  service.onContinue = async () => {
    continuations++;
  };
  const local = async (
    operation: string,
    extra: Record<string, unknown> = {},
    botId = 'nk-abcdef',
  ) =>
    service.local({
      botId,
      token: (
        await readFile(
          join(hermes.profileHome(botId), 'plugins/nekodot-secrets/bridge.token'),
          'utf8',
        )
      ).trim(),
      operation,
      sessionId: 'session-' + botId,
      ...extra,
    });
  const path = join(home, 'approved', 'test-key.pem');
  const spec = {
    service: 'Test SSH key',
    purpose: 'Write the test identity file',
    fields: [{ name: 'KEY', label: 'Private key', kind: 'private-key' }],
    target: { kind: 'file', path, format: 'raw' },
  };
  const request = (await local('request', { spec })) as { requestId: string };
  const { publicKey } = service.get('nk-abcdef', request.requestId);
  const raw = '-----BEGIN TEST PRIVATE KEY-----\n  meaningful spaces  \ntrailing\n';
  const envelope = encrypt(publicKey, 'nk-abcdef', request.requestId, { KEY: raw });
  await Promise.all([
    service.submit('nk-abcdef', request.requestId, { envelope, save: true }),
    service.submit('nk-abcdef', request.requestId, { envelope, save: true }),
  ]);
  expect(await readFile(path, 'utf8')).toBe(raw);
  expect(continuations).toBe(1);
  expect(service.list('nk-abcdef').credentials).toHaveLength(1);
  expect(JSON.stringify(db.messages('nk-abcdef'))).not.toContain(raw);
  expect(String(db.db.prepare('SELECT data FROM bot_credentials').get()!.data)).not.toContain(raw);
  expect(() => service.get('nk-bcdefg', request.requestId)).toThrow('not found');
  const reused = (await local('request', { spec })) as { state: string };
  expect(reused.state).toBe('applied');
  expect(continuations).toBe(1);
  const changed = (await local('request', {
    spec: { ...spec, purpose: 'A different purpose' },
  })) as { requestId: string; state: string };
  expect(changed.state).toBe('pending');
  await expect(
    service.submit('nk-abcdef', changed.requestId, { envelope, save: false }),
  ).rejects.toThrow('could not be opened');
  const credential = service.list('nk-abcdef').credentials[0]!;
  const replacement = service.replace('nk-abcdef', credential.credentialId);
  const replacementKey = service.get('nk-abcdef', replacement.requestId).publicKey;
  await service.submit('nk-abcdef', replacement.requestId, {
    envelope: encrypt(replacementKey, 'nk-abcdef', replacement.requestId, {
      KEY: raw + 'replacement',
    }),
    save: true,
  });
  expect(continuations).toBe(1);
  expect(service.list('nk-abcdef').credentials[0]!.credentialId).toBe(credential.credentialId);
  expect(await readFile(path, 'utf8')).toBe(raw + 'replacement');
  await service.disable('nk-abcdef', credential.credentialId);
  const deniedReuse = (await local('request', { spec })) as { state: string };
  expect(deniedReuse.state).toBe('pending');
  const nativeReply = hermes.gateway('nk-abcdef').onRequest!(
    'secret',
    { session_id: 'session-nk-abcdef', env_var: 'NATIVE_QA', prompt: 'Native setup' },
    'srq-qa',
  );
  const nativeRow = db.db
    .prepare('SELECT data FROM secret_requests')
    .all()
    .map((r) => JSON.parse(String(r.data)))
    .find((r) => r.nativeRequestId === 'srq-qa');
  const nativeKey = service.get('nk-abcdef', nativeRow.requestId).publicKey;
  await service.submit('nk-abcdef', nativeRow.requestId, {
    envelope: encrypt(nativeKey, 'nk-abcdef', nativeRow.requestId, {
      NATIVE_QA: 'native-test-value',
    }),
    save: false,
  });
  expect(await nativeReply).toEqual({ value: 'native-test-value' });
  expect(service.get('nk-abcdef', nativeRow.requestId).request.state).toBe('delivered');
  await service.finish(db.runs().find((r) => r.botId === 'nk-abcdef')!);
  expect(service.get('nk-abcdef', nativeRow.requestId).request.state).toBe('applied');
  const yamlPath = join(home, 'approved', 'service.yaml');
  const yamlRequest = (await local('request', {
    spec: {
      service: 'YAML service',
      purpose: 'Set the test service token',
      fields: [{ name: 'TOKEN', label: 'Token', kind: 'password' }],
      target: { kind: 'file', path: yamlPath, format: 'yaml' },
    },
  })) as { requestId: string };
  const yamlKey = service.get('nk-abcdef', yamlRequest.requestId).publicKey;
  await service.submit('nk-abcdef', yamlRequest.requestId, {
    envelope: encrypt(yamlKey, 'nk-abcdef', yamlRequest.requestId, { TOKEN: 'off' }),
    save: false,
  });
  expect(parse(await readFile(yamlPath, 'utf8'), { version: '1.1' })).toEqual({ TOKEN: 'off' });
  service.close();
  service = new BotSecrets(db, hermes);
  expect(service.list('nk-abcdef').credentials[0]!.enabled).toBe(false);
  service.close();
  db.db.close();
});
