import { SignJWT, jwtVerify } from 'jose';
import { hash, verify, argon2id } from 'argon2';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { authInputSchema, pairInputSchema } from '@nekodot/protocol';
import { RelayDatabase } from './database';

export class HttpFault extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly status = 400,
  ) {
    super(message);
  }
}
export function registerAuth(
  app: FastifyInstance,
  database: RelayDatabase,
  secret: string,
  publicUrl: string,
  online: (id: string) => boolean,
  revoke: (id: string) => void,
) {
  const key = new TextEncoder().encode(secret);
  const token = (id: string) =>
    new SignJWT({})
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject(id)
      .setIssuedAt()
      .setExpirationTime('30d')
      .sign(key);
  async function authenticate(request: FastifyRequest) {
    const bearer = request.headers.authorization?.replace(/^Bearer /, '');
    return authenticateToken(bearer ?? '');
  }
  async function authenticateToken(bearer: string) {
    let id: string | undefined;
    try {
      id = (await jwtVerify(bearer, key, { algorithms: ['HS256'] })).payload.sub;
    } catch {
      throw new HttpFault('unauthorized', 'Authentication required', 401);
    }
    const user = id ? database.userById(id) : undefined;
    if (!user) throw new HttpFault('unauthorized', 'Authentication required', 401);
    return user;
  }
  for (const action of ['signup', 'login'] as const) {
    app.post(
      '/api/auth/' + action,
      { config: { rateLimit: { max: 10, timeWindow: '1 minute' } } },
      async (request) => {
        const parsed = authInputSchema.safeParse(request.body);
        if (!parsed.success)
          throw new HttpFault(
            'invalid_params',
            'Valid email and password of at least 8 characters required',
          );
        const { email, password } = parsed.data;
        const existing = database.userByEmail(email);
        if (action === 'signup') {
          if (existing) throw new HttpFault('conflict', 'Email already registered', 409);
          const id = database.createUser(email, await hash(password, { type: argon2id }));
          return { token: await token(id) };
        }
        if (!existing || !(await verify(existing.password_hash, password)))
          throw new HttpFault('unauthorized', 'Email or password incorrect', 401);
        return { token: await token(existing.user_id) };
      },
    );
  }
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
      installCommand: `pnpm node:pair --relay ${publicUrl} --code ${result.code}`,
    };
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
  return { authenticateToken };
}
