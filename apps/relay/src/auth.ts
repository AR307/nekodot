import { SignJWT, jwtVerify } from 'jose';
import { hash, verify, argon2id } from 'argon2';
import { z } from 'zod';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { authInputSchema, pairInputSchema } from '@nekodot/protocol';
import { RelayDatabase } from './database';
import { EmailVerification, type SmtpConfiguration } from './email';

export class HttpFault extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly status = 400,
  ) {
    super(message);
  }
}
const dummyHash = hash('not-an-account-password', { type: argon2id });
const codeSchema = z.string().regex(/^\d{6}$/);
const verifiedInput = authInputSchema.extend({ code: codeSchema });
const codeRequest = z.strictObject({
  email: authInputSchema.shape.email,
  purpose: z.enum(['signup', 'verify', 'reset']),
  password: z.string().optional(),
});
export function registerAuth(
  app: FastifyInstance,
  database: RelayDatabase,
  secret: string,
  publicUrl: string,
  online: (id: string) => boolean,
  revoke: (id: string) => void,
  revokeUser: (userId: string, sessionId?: string) => void,
  smtp?: SmtpConfiguration,
) {
  const key = new TextEncoder().encode(secret);
  const emailCodes = new EmailVerification(database, secret, smtp);
  const token = (id: string) =>
    new SignJWT({})
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject(id)
      .setJti(database.createSession(id))
      .setIssuedAt()
      .setExpirationTime('30d')
      .sign(key);
  async function authenticate(request: FastifyRequest) {
    return authenticateToken(request.headers.authorization?.replace(/^Bearer /, '') ?? '');
  }
  async function authenticateToken(bearer: string) {
    let id: string | undefined, session: string | undefined;
    try {
      const { payload } = await jwtVerify(bearer, key, { algorithms: ['HS256'] });
      id = payload.sub;
      session = payload.jti;
    } catch {
      throw new HttpFault('unauthorized', 'Authentication required', 401);
    }
    const user = id ? database.userById(id) : undefined;
    if (!user || !session || !database.session(session, user.user_id))
      throw new HttpFault('unauthorized', 'Authentication required', 401);
    return { ...user, session_id: session };
  }
  function invalidate(userId: string, sessionId?: string) {
    database.revokeSessions(userId, sessionId);
    revokeUser(userId, sessionId);
  }
  const limited = { config: { rateLimit: { max: 10, timeWindow: '1 minute' } } };
  app.post('/api/auth/code', limited, async (request) => {
    const parsed = codeRequest.safeParse(request.body);
    if (!parsed.success)
      throw new HttpFault('invalid_params', 'Valid email and code purpose required');
    const { email, purpose, password } = parsed.data;
    const user = database.userByEmail(email);
    let eligible = purpose === 'signup' ? !user : !!user;
    if (purpose === 'verify') {
      const valid = await verify(user?.password_hash ?? (await dummyHash), password ?? '');
      eligible = !!user && valid && !database.verified(user.user_id);
    }
    await emailCodes.send(email, purpose, request.ip, eligible);
    return { sent: true, retryAfter: 60 };
  });
  app.post('/api/auth/signup', limited, async (request) => {
    const parsed = verifiedInput.safeParse(request.body);
    if (!parsed.success)
      throw new HttpFault('invalid_params', 'Email, password and 6-digit code required');
    const { email, password, code } = parsed.data;
    emailCodes.consume(email, 'signup', code);
    if (database.userByEmail(email))
      throw new HttpFault('invalid_code', 'Code is invalid or expired');
    const id = database.createUser(email, await hash(password, { type: argon2id }));
    database.verifyEmail(id);
    return { token: await token(id) };
  });
  app.post('/api/auth/login', limited, async (request) => {
    const parsed = authInputSchema.safeParse(request.body);
    if (!parsed.success) throw new HttpFault('invalid_params', 'Valid email and password required');
    const user = database.userByEmail(parsed.data.email);
    const valid = await verify(user?.password_hash ?? (await dummyHash), parsed.data.password);
    if (!user || !valid) throw new HttpFault('unauthorized', 'Email or password incorrect', 401);
    if (!database.verified(user.user_id))
      throw new HttpFault(
        'verification_required',
        'Verify your email to keep using this account',
        403,
      );
    return { token: await token(user.user_id) };
  });
  app.post('/api/auth/verify', limited, async (request) => {
    const parsed = verifiedInput.safeParse(request.body);
    if (!parsed.success)
      throw new HttpFault('invalid_params', 'Email, password and 6-digit code required');
    const { email, password, code } = parsed.data;
    const user = database.userByEmail(email);
    const valid = await verify(user?.password_hash ?? (await dummyHash), password);
    if (!user || !valid) throw new HttpFault('unauthorized', 'Email or password incorrect', 401);
    emailCodes.consume(email, 'verify', code);
    database.verifyEmail(user.user_id);
    return { token: await token(user.user_id) };
  });
  app.post('/api/auth/password/reset', limited, async (request) => {
    const parsed = verifiedInput.safeParse(request.body);
    if (!parsed.success)
      throw new HttpFault('invalid_params', 'Email, password and 6-digit code required');
    const { email, password, code } = parsed.data;
    emailCodes.consume(email, 'reset', code);
    const user = database.userByEmail(email);
    if (!user) throw new HttpFault('invalid_code', 'Code is invalid or expired');
    const encoded = await hash(password, { type: argon2id });
    database.db
      .prepare('UPDATE users SET password_hash=? WHERE user_id=?')
      .run(encoded, user.user_id);
    database.verifyEmail(user.user_id);
    invalidate(user.user_id);
    return {};
  });
  app.post('/api/auth/password/change', limited, async (request) => {
    const user = await authenticate(request);
    const parsed = z
      .strictObject({
        currentPassword: z.string().min(1),
        password: authInputSchema.shape.password,
      })
      .safeParse(request.body);
    if (!parsed.success)
      throw new HttpFault('invalid_params', 'Current and new passwords required');
    if (!(await verify(user.password_hash, parsed.data.currentPassword)))
      throw new HttpFault('unauthorized', 'Current password incorrect', 401);
    const encoded = await hash(parsed.data.password, { type: argon2id });
    database.db
      .prepare('UPDATE users SET password_hash=? WHERE user_id=?')
      .run(encoded, user.user_id);
    invalidate(user.user_id);
    return {};
  });
  app.post('/api/auth/logout', async (request) => {
    const user = await authenticate(request);
    invalidate(user.user_id, user.session_id);
    return {};
  });
  app.get('/api/me', async (request) => {
    const user = await authenticate(request);
    return {
      user: { userId: user.user_id, email: user.email },
      nodes: database.nodes(user.user_id).map((n) => ({
        nodeId: n.node_id,
        name: n.name,
        platform: n.platform,
        online: online(n.node_id),
      })),
    };
  });
  app.post('/api/pairing-codes', async (request) => {
    const user = await authenticate(request);
    const result = database.pairingCode(user.user_id);
    return {
      ...result,
      installCommand: `curl -fsSL '${publicUrl.replace(/\/$/, '')}/install.sh' | bash -s -- --pair ${result.code}`,
    };
  });
  app.post<{ Params: { code: string } }>('/api/pairing-codes/:code/extend', async (request) => {
    const user = await authenticate(request);
    const result = database.extendPairingCode(user.user_id, request.params.code);
    if (!result) throw new HttpFault('not_found', 'Unused pairing code not found', 404);
    return result;
  });
  app.post('/api/pair', async (request) => {
    const parsed = pairInputSchema.safeParse(request.body);
    if (!parsed.success)
      throw new HttpFault('invalid_params', 'Valid pairing code, node name and platform required');
    const result = database.pair(parsed.data.code, parsed.data.nodeName, parsed.data.platform);
    if (!result) throw new HttpFault('invalid_params', 'Pairing code expired or already used');
    return result;
  });
  app.delete<{ Params: { id: string } }>('/api/nodes/:id', async (request) => {
    const user = await authenticate(request);
    if (!database.owns(user.user_id, request.params.id))
      throw new HttpFault('not_found', 'Node not found', 404);
    database.revoke(user.user_id, request.params.id);
    revoke(request.params.id);
    return {};
  });
  app.addHook('onClose', async () => emailCodes.close());
  return { authenticateToken, authenticate };
}
