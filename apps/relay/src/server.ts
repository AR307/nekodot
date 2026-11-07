import Fastify from 'fastify';
import rateLimit from '@fastify/rate-limit';
import cors from '@fastify/cors';
import { RelayDatabase } from './database';
import { HttpFault, registerAuth } from './auth';
import { registerRouting } from './routing';
import { registerDownloads, latestNodeRelease } from './downloads';
import { registerFileTransfer } from './files';
import { registerTunnels } from './tunnels';
import { registerNotifications } from './notifications';
import type { SmtpConfiguration } from './email';
import { registerReleases, relayRelease } from './releases';

export interface RelayOptions {
  dataDir: string;
  jwtSecret: string;
  publicUrl: string;
  distributionDirectory?: string;
  logger?: boolean;
  clientOrigins?: string[];
  firebaseCredentials?: string;
  smtp?: SmtpConfiguration;
  trustedProxy?: string[];
}
export async function createRelay(options: RelayOptions) {
  const app = Fastify({
    trustProxy: options.trustedProxy ?? false,
    logger: options.logger ? { redact: ['req.headers.authorization'] } : false,
  });
  const database = new RelayDatabase(options.dataDir);
  await app.register(cors, {
    origin: options.clientOrigins ?? [],
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Authorization', 'Content-Type'],
  });
  await app.register(rateLimit, { global: false });
  const auth = registerAuth(
    app,
    database,
    options.jwtSecret,
    options.publicUrl,
    (id) => routing.online(id),
    (id) => routing.revoke(id),
    (userId, sessionId) => {
      routing.revokeUser(userId, sessionId);
      tunnels.revokeUser(userId, sessionId);
    },
    options.smtp,
    (id) => routing.needsManualUpdate(id),
  );
  const notify = registerNotifications(
    app,
    database,
    auth.authenticate,
    options.firebaseCredentials,
  );
  const routing = registerRouting(
    app.server,
    database,
    auth.authenticateToken,
    notify,
    () =>
      options.distributionDirectory
        ? latestNodeRelease(options.distributionDirectory, app.log)
        : Promise.resolve(undefined),
    options.publicUrl,
  );
  const tunnels = registerTunnels(app, database, auth.authenticate, routing);
  routing.usage.register(app, auth.authenticate, routing);
  routing.routines.register(app, routing.deliverRoutine);
  registerFileTransfer(app, auth.authenticate, routing.transfer, (userId, nodeId) =>
    database.owns(userId, nodeId),
  );
  app.get('/health', () => ({ service: 'nekodot-relay', status: 'ok', ...relayRelease }));
  registerReleases(app, options.distributionDirectory);
  if (options.distributionDirectory)
    registerDownloads(app, options.distributionDirectory, options.publicUrl);
  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof HttpFault)
      return reply.code(error.status).send({ error: { code: error.code, message: error.message } });
    if (error && typeof error === 'object' && 'statusCode' in error && error.statusCode === 429)
      return reply
        .code(429)
        .send({ error: { code: 'unavailable', message: 'Too many login attempts' } });
    return reply.code(500).send({ error: { code: 'internal_error', message: 'Request failed' } });
  });
  app.addHook('preClose', async () => {
    tunnels.close();
    routing.close();
  });
  app.addHook('onClose', async () => database.db.close());
  return { app, database, routing };
}
