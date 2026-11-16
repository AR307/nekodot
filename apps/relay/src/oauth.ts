import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { hash, argon2id } from 'argon2';
import { z } from 'zod';
import type { FastifyInstance, FastifyReply } from 'fastify';
import { HttpFault } from './auth';
import type { RelayDatabase } from './database';

/** Who signed in, as the provider vouches for them: a stable id and a verified email. */
export interface OAuthIdentity {
  subject: string;
  email: string;
}

/**
 * A sign-in provider. The person is sent to `authorize`; the code they bring
 * back is turned into an identity, or into nothing when the provider has no
 * verified email for them.
 */
export interface OAuthProvider {
  authorize: string;
  clientId: string;
  scope: string;
  params?: Record<string, string>;
  identify(code: string, redirectUri: string): Promise<OAuthIdentity | undefined>;
}

export interface OAuthClient {
  clientId: string;
  clientSecret: string;
}

export const providerNames = ['google', 'github'] as const;
export type ProviderName = (typeof providerNames)[number];
export type OAuthProviders = Partial<Record<ProviderName, OAuthProvider>>;

const accessToken = z.object({ access_token: z.string().min(1) });

async function send(url: string, init: RequestInit) {
  const response = await fetch(url, {
    ...init,
    headers: { Accept: 'application/json', 'User-Agent': 'nekodot-relay', ...init.headers },
  });
  if (!response.ok) throw new Error(`${new URL(url).host} answered ${response.status}`);
  return response.json() as Promise<unknown>;
}
const exchange = (url: string, fields: Record<string, string>) =>
  send(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(fields).toString(),
  }).then((body) => accessToken.parse(body).access_token);
const read = (url: string, token: string) =>
  send(url, { headers: { Authorization: 'Bearer ' + token } });

export const googleEndpoints = {
  authorize: 'https://accounts.google.com/o/oauth2/v2/auth',
  token: 'https://oauth2.googleapis.com/token',
  user: 'https://openidconnect.googleapis.com/v1/userinfo',
};
const googleUser = z.object({
  sub: z.string().min(1),
  email: z.email().optional(),
  email_verified: z.boolean().optional(),
});
export function google(client: OAuthClient, endpoints = googleEndpoints): OAuthProvider {
  return {
    authorize: endpoints.authorize,
    clientId: client.clientId,
    scope: 'openid email',
    params: { prompt: 'select_account' },
    async identify(code, redirectUri) {
      const token = await exchange(endpoints.token, {
        grant_type: 'authorization_code',
        code,
        redirect_uri: redirectUri,
        client_id: client.clientId,
        client_secret: client.clientSecret,
      });
      const user = googleUser.parse(await read(endpoints.user, token));
      return user.email && user.email_verified === true
        ? { subject: user.sub, email: user.email }
        : undefined;
    },
  };
}

export const githubEndpoints = {
  authorize: 'https://github.com/login/oauth/authorize',
  token: 'https://github.com/login/oauth/access_token',
  api: 'https://api.github.com',
};
const githubUser = z.object({ id: z.number().int() });
const githubEmails = z.array(
  z.object({ email: z.string(), primary: z.boolean(), verified: z.boolean() }),
);
export function github(client: OAuthClient, endpoints = githubEndpoints): OAuthProvider {
  return {
    authorize: endpoints.authorize,
    clientId: client.clientId,
    scope: 'read:user user:email',
    async identify(code, redirectUri) {
      const token = await exchange(endpoints.token, {
        code,
        redirect_uri: redirectUri,
        client_id: client.clientId,
        client_secret: client.clientSecret,
      });
      const user = githubUser.parse(await read(endpoints.api + '/user', token));
      const emails = githubEmails.parse(await read(endpoints.api + '/user/emails', token));
      const primary = emails.find((entry) => entry.primary && entry.verified);
      return primary ? { subject: String(user.id), email: primary.email } : undefined;
    },
  };
}

// Where a sign-in may return to: the app's own loopback listener on a
// computer, or the app's link on a phone. Nothing else, so the Relay never
// sends a code to a page someone else chose.
const returnTo = z
  .string()
  .refine(
    (value) =>
      value === 'nekodot://oauth' || /^http:\/\/127\.0\.0\.1:([1-9]\d{3,4})\/oauth$/.test(value),
  );
const base64url = (bytes: Buffer) => bytes.toString('base64url');
const startQuery = z.strictObject({
  challenge: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
  return: returnTo,
});
const callbackQuery = z.object({
  state: z.string().min(1),
  code: z.string().min(1).optional(),
  error: z.string().optional(),
});
const tokenInput = z.strictObject({
  code: z.string().min(1).max(200),
  verifier: z.string().regex(/^[A-Za-z0-9_-]{43,128}$/),
});

interface Flow {
  provider: ProviderName;
  challenge: string;
  returnTo: string;
  expires: number;
}
interface Grant {
  userId: string;
  challenge: string;
  expires: number;
}

/** Sign-in with Google and GitHub for the apps; set up as described in deploy/README.md. */
export function registerOAuth(
  app: FastifyInstance,
  database: RelayDatabase,
  providers: OAuthProviders,
  publicUrl: string,
  issue: (userId: string) => Promise<string>,
) {
  const flows = new Map<string, Flow>();
  const grants = new Map<string, Grant>();
  const sweep = () => {
    const now = Date.now();
    for (const [key, flow] of flows) if (flow.expires < now) flows.delete(key);
    for (const [key, grant] of grants) if (grant.expires < now) grants.delete(key);
  };
  const callbackUrl = (name: ProviderName) =>
    new URL(`/api/auth/oauth/${name}/callback`, publicUrl).toString();
  const provider = (name: string) => {
    const found = (providerNames as readonly string[]).includes(name)
      ? providers[name as ProviderName]
      : undefined;
    if (!found) throw new HttpFault('not_found', 'Sign-in provider not available', 404);
    return { name: name as ProviderName, provider: found };
  };
  const back = (reply: FastifyReply, to: string, fields: Record<string, string>) => {
    const target = new URL(to);
    for (const [key, value] of Object.entries(fields)) target.searchParams.set(key, value);
    return reply.redirect(target.toString());
  };
  const limited = { config: { rateLimit: { max: 20, timeWindow: '1 minute' } } };

  /** The account a provider identity signs in to, made or linked on first use. */
  async function account(name: ProviderName, identity: OAuthIdentity) {
    const known = database.identityUser(name, identity.subject);
    if (known) return known;
    const email = identity.email.trim().toLowerCase();
    const existing = database.userByEmail(email);
    let userId: string;
    if (existing) {
      userId = existing.user_id;
      // An account never verified may have been set up by someone else with
      // this address: its password and sessions stop working before the
      // owner of the address takes it over.
      if (!database.verified(userId)) {
        database.setPassword(userId, await unusablePassword());
        database.revokeSessions(userId);
      }
    } else userId = database.createUser(email, await unusablePassword());
    database.verifyEmail(userId);
    database.linkIdentity(name, identity.subject, userId);
    return userId;
  }

  app.get('/api/auth/providers', () => ({
    providers: providerNames.filter((name) => providers[name]),
  }));

  app.get<{ Params: { provider: string } }>(
    '/api/auth/oauth/:provider',
    limited,
    async (request, reply) => {
      const { name, provider: chosen } = provider(request.params.provider);
      const parsed = startQuery.safeParse(request.query);
      if (!parsed.success)
        throw new HttpFault('invalid_params', 'Valid challenge and return required');
      sweep();
      const state = base64url(randomBytes(24));
      flows.set(state, {
        provider: name,
        challenge: parsed.data.challenge,
        returnTo: parsed.data.return,
        expires: Date.now() + 10 * 60_000,
      });
      const target = new URL(chosen.authorize);
      for (const [key, value] of Object.entries({
        client_id: chosen.clientId,
        redirect_uri: callbackUrl(name),
        response_type: 'code',
        scope: chosen.scope,
        state,
        ...chosen.params,
      }))
        target.searchParams.set(key, value);
      return reply.redirect(target.toString());
    },
  );

  app.get<{ Params: { provider: string } }>(
    '/api/auth/oauth/:provider/callback',
    limited,
    async (request, reply) => {
      const { name, provider: chosen } = provider(request.params.provider);
      const parsed = callbackQuery.safeParse(request.query);
      const flow = parsed.success ? flows.get(parsed.data.state) : undefined;
      if (parsed.success) flows.delete(parsed.data.state);
      if (!parsed.success || !flow || flow.provider !== name || flow.expires < Date.now())
        return reply
          .code(400)
          .type('text/html; charset=utf-8')
          .send(
            '<!doctype html><meta charset="utf-8"><title>nekodot</title>' +
              '<p>登录链接已失效，请回到 nekodot 重新登录。</p>' +
              '<p>This sign-in link has expired. Go back to nekodot and try again.</p>',
          );
      if (!parsed.data.code) return back(reply, flow.returnTo, { error: 'denied' });
      let identity: OAuthIdentity | undefined;
      try {
        identity = await chosen.identify(parsed.data.code, callbackUrl(name));
      } catch (error) {
        request.log.warn({ provider: name, error: String(error) }, 'oauth exchange failed');
        return back(reply, flow.returnTo, { error: 'failed' });
      }
      if (!identity) return back(reply, flow.returnTo, { error: 'unverified' });
      const userId = await account(name, identity);
      sweep();
      const code = base64url(randomBytes(24));
      grants.set(code, { userId, challenge: flow.challenge, expires: Date.now() + 2 * 60_000 });
      return back(reply, flow.returnTo, { code });
    },
  );

  app.post('/api/auth/oauth/token', limited, async (request) => {
    const parsed = tokenInput.safeParse(request.body);
    if (!parsed.success) throw new HttpFault('invalid_params', 'Code and verifier required');
    const grant = grants.get(parsed.data.code);
    grants.delete(parsed.data.code);
    const proof = Buffer.from(
      base64url(createHash('sha256').update(parsed.data.verifier).digest()),
    );
    if (
      !grant ||
      grant.expires < Date.now() ||
      proof.length !== grant.challenge.length ||
      !timingSafeEqual(proof, Buffer.from(grant.challenge))
    )
      throw new HttpFault('invalid_code', 'Code is invalid or expired');
    return { token: await issue(grant.userId) };
  });
}

/** A password nobody knows: the account signs in through its provider, or sets one by email. */
const unusablePassword = () => hash(randomBytes(32).toString('hex'), { type: argon2id });
