import { mkdtemp } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash, randomBytes } from 'node:crypto';
import { createServer, type IncomingMessage } from 'node:http';
import { once } from 'node:events';
import { hash, argon2id } from 'argon2';
import { afterEach, expect, it } from 'vitest';
import { createRelay } from './server';
import { github, google, type OAuthIdentity, type OAuthProvider } from './oauth';

type Relay = Awaited<ReturnType<typeof createRelay>>;
const relays: Relay[] = [];
afterEach(async () => {
  for (const relay of relays.splice(0)) await relay.app.close();
});

async function relayWith(providers: Parameters<typeof createRelay>[0]['oauth']) {
  const relay = await createRelay({
    dataDir: await mkdtemp(join(tmpdir(), 'nekodot-oauth-')),
    jwtSecret: 'local-oauth-test-secret',
    publicUrl: 'https://relay.example.test',
    oauth: providers,
  });
  relays.push(relay);
  return relay;
}

/** A provider that vouches for whoever the test says signed in. */
function fakeProvider(next: () => OAuthIdentity | undefined | Error): OAuthProvider & {
  seen: string[];
} {
  const seen: string[] = [];
  return {
    authorize: 'https://provider.example.test/authorize',
    clientId: 'client-1',
    scope: 'email',
    seen,
    async identify(code, redirectUri) {
      seen.push(`${code} ${redirectUri}`);
      const result = next();
      if (result instanceof Error) throw result;
      return result;
    },
  };
}

const pkce = () => {
  const verifier = randomBytes(32).toString('base64url');
  return { verifier, challenge: createHash('sha256').update(verifier).digest('base64url') };
};
const loopback = 'http://127.0.0.1:53111/oauth';

/** Starts a sign-in as the app would, and plays the provider's redirect back. */
async function signIn(
  relay: Relay,
  provider: string,
  options: { returnTo?: string; code?: string; error?: string } = {},
) {
  const { verifier, challenge } = pkce();
  const returnTo = options.returnTo ?? loopback;
  const start = await relay.app.inject({
    method: 'GET',
    url: `/api/auth/oauth/${provider}?challenge=${challenge}&return=${encodeURIComponent(returnTo)}`,
  });
  expect(start.statusCode).toBe(302);
  const authorize = new URL(start.headers.location as string);
  const state = authorize.searchParams.get('state')!;
  const query = new URLSearchParams({ state });
  if (options.error) query.set('error', options.error);
  else query.set('code', options.code ?? 'provider-code');
  const callback = await relay.app.inject({
    method: 'GET',
    url: `/api/auth/oauth/${provider}/callback?${query}`,
  });
  const back = callback.headers.location ? new URL(callback.headers.location as string) : undefined;
  return { verifier, authorize, callback, back };
}
const redeem = (relay: Relay, code: string, verifier: string) =>
  relay.app.inject({
    method: 'POST',
    url: '/api/auth/oauth/token',
    headers: { 'content-type': 'application/json' },
    payload: JSON.stringify({ code, verifier }),
  });
const me = (relay: Relay, token: string) =>
  relay.app.inject({
    method: 'GET',
    url: '/api/me',
    headers: { authorization: 'Bearer ' + token },
  });
const login = (relay: Relay, email: string, password: string) =>
  relay.app.inject({
    method: 'POST',
    url: '/api/auth/login',
    headers: { 'content-type': 'application/json' },
    payload: JSON.stringify({ email, password }),
  });

it('lists only the providers the Relay has a client for', async () => {
  const none = await relayWith(undefined);
  expect((await none.app.inject({ url: '/api/auth/providers' })).json()).toEqual({ providers: [] });
  expect((await none.app.inject({ url: '/api/auth/oauth/google?challenge=x' })).statusCode).toBe(
    404,
  );
  const one = await relayWith({ github: fakeProvider(() => undefined) });
  expect((await one.app.inject({ url: '/api/auth/providers' })).json()).toEqual({
    providers: ['github'],
  });
});

it('signs a new person in, hands the code only to the app that holds the verifier, and never twice', async () => {
  let person: OAuthIdentity = { subject: 'g-1', email: 'New.Person@Example.test' };
  const provider = fakeProvider(() => person);
  const relay = await relayWith({ google: provider });

  const { verifier, authorize, back } = await signIn(relay, 'google');
  expect(authorize.origin + authorize.pathname).toBe('https://provider.example.test/authorize');
  expect(Object.fromEntries(authorize.searchParams)).toMatchObject({
    client_id: 'client-1',
    redirect_uri: 'https://relay.example.test/api/auth/oauth/google/callback',
    response_type: 'code',
    scope: 'email',
  });
  expect(provider.seen).toEqual([
    'provider-code https://relay.example.test/api/auth/oauth/google/callback',
  ]);
  expect(back!.origin + back!.pathname).toBe('http://127.0.0.1:53111/oauth');
  const code = back!.searchParams.get('code')!;

  // Someone who saw the code but not the verifier gets nothing, and the code is gone.
  expect((await redeem(relay, code, pkce().verifier)).json().error.code).toBe('invalid_code');
  expect((await redeem(relay, code, verifier)).statusCode).toBe(400);

  const second = await signIn(relay, 'google');
  const granted = await redeem(relay, second.back!.searchParams.get('code')!, second.verifier);
  expect(granted.statusCode).toBe(200);
  const token = granted.json<{ token: string }>().token;
  expect((await me(relay, token)).json().user.email).toBe('new.person@example.test');
  expect(relay.database.verified((await me(relay, token)).json().user.userId)).toBe(true);
  expect(
    (await redeem(relay, second.back!.searchParams.get('code')!, second.verifier)).statusCode,
  ).toBe(400);

  // The same provider identity keeps its account even if its email changes.
  const userId = (await me(relay, token)).json().user.userId;
  person = { subject: 'g-1', email: 'renamed@example.test' };
  const third = await signIn(relay, 'google');
  const again = await redeem(relay, third.back!.searchParams.get('code')!, third.verifier);
  expect((await me(relay, again.json().token)).json().user.userId).toBe(userId);
});

it('signs in to the account that already has the email, and takes over one never verified', async () => {
  const relay = await relayWith({ github: fakeProvider(() => identity) });
  let identity: OAuthIdentity = { subject: '42', email: 'owner@example.test' };
  const owner = relay.database.createUser(
    'owner@example.test',
    await hash('owner-password', { type: argon2id }),
  );
  relay.database.verifyEmail(owner);
  const first = await signIn(relay, 'github', { returnTo: 'nekodot://oauth' });
  expect(first.back!.protocol).toBe('nekodot:');
  const token = (await redeem(relay, first.back!.searchParams.get('code')!, first.verifier)).json()
    .token as string;
  expect((await me(relay, token)).json().user.userId).toBe(owner);
  expect((await login(relay, 'owner@example.test', 'owner-password')).statusCode).toBe(200);

  // Someone registered this address long ago and never verified it.
  const squatter = relay.database.createUser(
    'victim@example.test',
    await hash('squatter-password', { type: argon2id }),
  );
  identity = { subject: '43', email: 'victim@example.test' };
  const taken = await signIn(relay, 'github');
  const owned = (await redeem(relay, taken.back!.searchParams.get('code')!, taken.verifier)).json()
    .token as string;
  expect((await me(relay, owned)).json().user.userId).toBe(squatter);
  expect((await login(relay, 'victim@example.test', 'squatter-password')).statusCode).toBe(401);
});

it('sends refusals and problems back to the app, and expired links nowhere', async () => {
  let outcome: OAuthIdentity | undefined | Error = undefined;
  const relay = await relayWith({ google: fakeProvider(() => outcome) });
  expect(
    (await signIn(relay, 'google', { error: 'access_denied' })).back!.searchParams.get('error'),
  ).toBe('denied');
  expect((await signIn(relay, 'google')).back!.searchParams.get('error')).toBe('unverified');
  outcome = new Error('provider down');
  expect((await signIn(relay, 'google')).back!.searchParams.get('error')).toBe('failed');

  const stale = await relay.app.inject({
    url: '/api/auth/oauth/google/callback?state=unknown&code=x',
  });
  expect(stale.statusCode).toBe(400);
  expect(stale.headers.location).toBeUndefined();
  expect(stale.body).toContain('expired');

  // Only the app's own loopback listener or its link may receive a code.
  const { challenge } = pkce();
  for (const to of [
    'https://evil.example.test/oauth',
    'http://127.0.0.1.evil.example.test:5000/oauth',
    'http://localhost:53111/oauth',
    'nekodot://other',
  ])
    expect(
      (
        await relay.app.inject({
          url: `/api/auth/oauth/google?challenge=${challenge}&return=${encodeURIComponent(to)}`,
        })
      ).statusCode,
    ).toBe(400);
});

/** A local stand-in for Google's and GitHub's token and profile endpoints. */
async function providerServer(answers: Record<string, unknown>) {
  const requests: { path: string; body: string; authorization?: string }[] = [];
  const server = createServer((request: IncomingMessage, response) => {
    let body = '';
    request.on('data', (chunk) => (body += String(chunk)));
    request.on('end', () => {
      const path = request.url!.split('?')[0]!;
      requests.push({ path, body, authorization: request.headers.authorization });
      const answer = answers[path];
      response.writeHead(answer === undefined ? 404 : 200, { 'content-type': 'application/json' });
      response.end(JSON.stringify(answer ?? {}));
    });
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('not listening');
  return { base: `http://127.0.0.1:${address.port}`, requests, close: () => server.close() };
}

it('reads a verified email from Google and from GitHub', async () => {
  const googleSide = await providerServer({
    '/token': { access_token: 'google-access' },
    '/userinfo': { sub: 'g-7', email: 'g@example.test', email_verified: true },
  });
  const githubSide = await providerServer({
    '/login/oauth/access_token': { access_token: 'github-access' },
    '/user': { id: 99 },
    '/user/emails': [
      { email: 'other@example.test', primary: false, verified: true },
      { email: 'gh@example.test', primary: true, verified: true },
    ],
  });
  try {
    const client = { clientId: 'id-1', clientSecret: 'secret-1' };
    const g = google(client, {
      authorize: googleSide.base + '/auth',
      token: googleSide.base + '/token',
      user: googleSide.base + '/userinfo',
    });
    expect(await g.identify('code-1', 'https://relay/cb')).toEqual({
      subject: 'g-7',
      email: 'g@example.test',
    });
    const exchange = new URLSearchParams(googleSide.requests[0]!.body);
    expect(Object.fromEntries(exchange)).toEqual({
      grant_type: 'authorization_code',
      code: 'code-1',
      redirect_uri: 'https://relay/cb',
      client_id: 'id-1',
      client_secret: 'secret-1',
    });
    expect(googleSide.requests[1]!.authorization).toBe('Bearer google-access');

    const h = github(client, {
      authorize: githubSide.base + '/login/oauth/authorize',
      token: githubSide.base + '/login/oauth/access_token',
      api: githubSide.base,
    });
    expect(await h.identify('code-2', 'https://relay/cb')).toEqual({
      subject: '99',
      email: 'gh@example.test',
    });
    expect(githubSide.requests.map((request) => request.path)).toEqual([
      '/login/oauth/access_token',
      '/user',
      '/user/emails',
    ]);
  } finally {
    googleSide.close();
    githubSide.close();
  }
});
