import Fastify from 'fastify';
import rateLimit from '@fastify/rate-limit';
import staticFiles from '@fastify/static';
import { RelayDatabase } from './database';
import { HttpFault, registerAuth } from './auth';
import { registerRouting } from './routing';
import { registerDownloads } from './downloads';
import { registerFileTransfer } from './files';

export interface RelayOptions {
  dataDir: string;
  jwtSecret: string;
  publicUrl: string;
  webDirectory?: string;
  distributionDirectory?: string;
  logger?: boolean;
}
export async function createRelay(options: RelayOptions) {
  const app = Fastify({
    logger: options.logger ? { redact: ['req.headers.authorization'] } : false,
  });
  const database = new RelayDatabase(options.dataDir);
  await app.register(rateLimit, { global: false });
  const auth = registerAuth(
    app,
    database,
    options.jwtSecret,
    options.publicUrl,
    (id) => routing.online(id),
    (id) => routing.revoke(id),
  );
  const routing = registerRouting(app.server, database, auth.authenticateToken);
  registerFileTransfer(app, auth.authenticate, routing.transfer, (userId, nodeId) =>
    database.owns(userId, nodeId),
  );
  app.get('/health', () => ({ service: 'nekodot-relay', phase: 3, status: 'ok' }));
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
  if (options.webDirectory) {
    await app.register(staticFiles, { root: options.webDirectory });
    app.setNotFoundHandler((request, reply) =>
      request.method === 'GET' && !request.url.startsWith('/api/')
        ? reply.sendFile('index.html')
        : reply.code(404).send({ error: { code: 'not_found', message: 'Route not found' } }),
    );
  }
  app.addHook('preClose', async () => routing.close());
  app.addHook('onClose', async () => database.db.close());
  return { app, database, routing };
}
