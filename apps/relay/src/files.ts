import { Readable } from 'node:stream';
import { z } from 'zod';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { transferChunkBytes, type TransferRequest, type TransferResponse } from '@nekodot/protocol';
import { HttpFault } from './auth';

const pathSchema = z.strictObject({ nodeId: z.string().min(1), fileId: z.uuid() });
const uploadSchema = z.strictObject({ nodeId: z.string().min(1), importId: z.uuid() });
export function registerFileTransfer(
  app: FastifyInstance,
  authenticate: (request: FastifyRequest) => Promise<{ user_id: string }>,
  transfer: (userId: string, nodeId: string, payload: TransferRequest) => Promise<TransferResponse>,
  owns: (userId: string, nodeId: string) => boolean,
) {
  app.addContentTypeParser(
    'application/octet-stream',
    { parseAs: 'buffer', bodyLimit: transferChunkBytes },
    (_request, body, done) => done(null, body),
  );
  app.get('/api/nodes/:nodeId/files/:fileId', async (request, reply) => {
    const user = await authenticate(request);
    const parsed = pathSchema.safeParse(request.params);
    if (!parsed.success) throw new HttpFault('invalid_params', 'Invalid file reference');
    const { nodeId, fileId } = parsed.data;
    if (!owns(user.user_id, nodeId)) throw new HttpFault('forbidden', 'Node is not yours', 403);
    const first = await transfer(user.user_id, nodeId, { action: 'read', fileId, offset: 0 });
    if (!first.ok) throw new HttpFault('not_found', first.error, 404);
    reply.header('Content-Type', first.mime ?? 'application/octet-stream');
    reply.header(
      'Content-Disposition',
      "attachment; filename*=UTF-8''" + encodeURIComponent(first.name ?? 'file'),
    );
    reply.header('X-Content-Type-Options', 'nosniff');
    reply.header('Cache-Control', 'no-store');
    if (first.size !== undefined) reply.header('Content-Length', first.size);
    async function* chunks() {
      let current = first;
      let offset = 0;
      while (current.ok) {
        const bytes = Buffer.from(current.data ?? '', 'base64');
        if (bytes.length) yield bytes;
        offset += bytes.length;
        if (current.done || request.raw.destroyed) return;
        current = await transfer(user.user_id, nodeId, { action: 'read', fileId, offset });
      }
      throw new Error('File transfer interrupted');
    }
    return reply.send(Readable.from(chunks()));
  });
  app.put(
    '/api/nodes/:nodeId/imports/:importId',
    { bodyLimit: transferChunkBytes },
    async (request) => {
      const user = await authenticate(request);
      const parsed = uploadSchema.safeParse(request.params);
      const query = z
        .strictObject({ path: z.string().min(1), offset: z.coerce.number().int().nonnegative() })
        .safeParse(request.query);
      if (!parsed.success || !query.success || !Buffer.isBuffer(request.body))
        throw new HttpFault('invalid_params', 'Invalid import chunk');
      const { nodeId, importId } = parsed.data;
      if (!owns(user.user_id, nodeId)) throw new HttpFault('forbidden', 'Node is not yours', 403);
      const result = await transfer(user.user_id, nodeId, {
        action: 'write',
        importId,
        ...query.data,
        data: request.body.toString('base64'),
      });
      if (!result.ok) throw new HttpFault('invalid_params', result.error);
      return {};
    },
  );
}
