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
import type { SecretEnvelope, SecretRequest } from '@nekodot/protocol';
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
  const vault: { id: string; identifier: string; password: string }[] = [];
  const hermes = {
    management: {
      rpc: async (
        method: string,
        params: { id?: string; secret?: { identifier: string; password: string } },
      ) => {
        if (method === 'vault.list')
          return { items: vault.map(({ id, identifier }) => ({ id, identifier })) };
        if (method === 'vault.add') {
          const id = 'vault-' + vault.length;
          vault.push({ id, ...params.secret! });
          return { id };
        }
        if (method === 'vault.remove')
          vault.splice(
            vault.findIndex((v) => v.id === params.id),
            1,
          );
        return {};
      },
    },
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
  // One card at a time: the next one waits until this card is delivered or cancelled.
  await expect(local('request', { spec: { ...spec, purpose: 'Third' } })).rejects.toThrow(
    'still waiting',
  );
  service.cancel('nk-abcdef', changed.requestId);
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
  const deniedReuse = (await local('request', { spec })) as { requestId: string; state: string };
  expect(deniedReuse.state).toBe('pending');
  service.cancel('nk-abcdef', deniedReuse.requestId);
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
  await service.finish({
    ...db.runs()[0]!,
    submissionId: 'secret-delivery:' + yamlRequest.requestId,
  });

  // A real website login requires two sequential cards, not a persisted hidden username.
  const website = {
    service: 'QA login',
    purpose: 'Sign in',
    target: { kind: 'vault', origin: 'https://login.example.test' },
  };
  const accountSpec = {
    ...website,
    fields: [{ name: 'identifier', label: 'Account', kind: 'text' }],
  };
  const passwordSpec = {
    ...website,
    fields: [{ name: 'password', label: 'Password', kind: 'password' }],
  };
  const deliver = async (request: SecretRequest, values: Record<string, string>, save = false) =>
    service.submit('nk-abcdef', request.requestId, {
      envelope: encrypt(
        service.get('nk-abcdef', request.requestId).publicKey,
        'nk-abcdef',
        request.requestId,
        values,
      ),
      save,
    });
  let account = (await local('request', { spec: accountSpec })) as SecretRequest;
  await expect(local('request', { spec: passwordSpec })).rejects.toThrow();
  await expect(
    Promise.resolve().then(() => service.replace('nk-abcdef', credential.credentialId)),
  ).rejects.toThrow();
  await deliver(account, { identifier: 'ephemeral-account@example.test' });
  const persistedAccount = JSON.parse(
    String(
      db.db.prepare('SELECT data FROM secret_requests WHERE id=?').get(account.requestId)!.data,
    ),
  );
  expect(persistedAccount.account).toBeUndefined();
  expect(JSON.stringify(persistedAccount)).not.toContain('ephemeral-account@example.test');
  await expect(
    local('request', { spec: { ...passwordSpec, purpose: 'Another use' } }),
  ).rejects.toThrow('account card');
  let password = (await local('request', { spec: passwordSpec })) as SecretRequest;
  expect(password.state).toBe('pending');

  // Restart between cards: close the stale password and re-deliver the account first.
  service.close();
  service = new BotSecrets(db, hermes);
  service.bind('qa-node');
  service.onContinue = async () => {
    continuations++;
  };
  expect(service.get('nk-abcdef', password.requestId).request.state).toBe('expired');
  expect(service.get('nk-abcdef', account.requestId).request.state).toBe('redelivery');
  await deliver(account, { identifier: 'ephemeral-account@example.test' });
  password = (await local('request', { spec: passwordSpec })) as SecretRequest;
  await deliver(password, { password: 'qa-one-use-password' });
  expect(vault.at(-1)).toMatchObject({
    identifier: 'ephemeral-account@example.test',
    password: 'qa-one-use-password',
  });
  await service.finish({ ...db.runs()[0]!, submissionId: 'secret-delivery:' + password.requestId });
  expect(vault).toHaveLength(0);
  expect(service.scrub('nk-abcdef', 'ephemeral-account@example.test')).toBe(
    'ephemeral-account@example.test',
  );

  account = (await local('request', { spec: accountSpec })) as SecretRequest;
  await deliver(account, { identifier: 'saved-account@example.test' }, true);
  password = (await local('request', { spec: passwordSpec })) as SecretRequest;
  await deliver(password, { password: 'qa-saved-password' }, true);
  await service.finish({ ...db.runs()[0]!, submissionId: 'secret-delivery:' + password.requestId });
  expect(vault).toHaveLength(1);
  const reusedPassword = (await local('request', { spec: passwordSpec })) as SecretRequest;
  expect(reusedPassword.state).toBe('applied');
  const savedPassword = service
    .list('nk-abcdef')
    .credentials.find((c) => c.fields[0]?.name === 'password')!;
  const replacePassword = service.replace('nk-abcdef', savedPassword.credentialId);
  await deliver(replacePassword, { password: 'qa-replaced-password' }, true);
  expect(vault).toHaveLength(1);
  expect(vault[0]).toMatchObject({
    identifier: 'saved-account@example.test',
    password: 'qa-replaced-password',
  });
  service.close();
  service = new BotSecrets(db, hermes);
  expect(service.list('nk-abcdef').credentials[0]!.enabled).toBe(false);
  service.close();
  db.db.close();
});
