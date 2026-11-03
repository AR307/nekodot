import { readFile, stat } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { join } from 'node:path';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import product from '../../../package.json';

export const relayRelease = {
  version: product.version,
  build: process.env.NEKODOT_BUILD_NUMBER ?? 'development',
};
const artifact = z.object({
  path: z.string().regex(/^releases\/[0-9.]+-[0-9]+\/[a-z0-9.-]+$/),
  size: z.number().int().positive(),
  build: z.number().int().positive(),
});
export const productReleaseSchema = z.object({
  schema: z.literal(1),
  version: z.string().regex(/^\d+\.\d+\.\d+$/),
  build: z.number().int().positive(),
  publishedAt: z.iso.datetime(),
  notes: z.string(),
  artifacts: z.object({
    windows: artifact,
    android: artifact,
    relay: artifact.extend({ image: z.string().regex(/^nekodot-relay:[a-zA-Z0-9_.-]+$/) }),
  }),
});

export function registerReleases(app: FastifyInstance, directory?: string) {
  const latest = async () => {
    if (!directory) return null;
    try {
      return productReleaseSchema.parse(
        JSON.parse(await readFile(join(directory, 'latest.json'), 'utf8')),
      );
    } catch (error) {
      if (error instanceof Error && 'code' in error && error.code === 'ENOENT') return null;
      throw error;
    }
  };
  app.get('/api/releases', async (_request, reply) => {
    reply.header('Cache-Control', 'no-store');
    return { relay: relayRelease, latest: await latest() };
  });
  app.get('/downloads/latest.json', async (_request, reply) => {
    reply.header('Cache-Control', 'no-store');
    const release = await latest();
    if (!release)
      return reply.code(404).send({ error: { message: 'No product release published' } });
    return release;
  });
  app.get<{ Params: { release: string; name: string } }>(
    '/downloads/releases/:release/:name',
    async (request, reply) => {
      const release = await latest();
      const path = `releases/${request.params.release}/${request.params.name}`;
      const entry = release && Object.values(release.artifacts).find((item) => item.path === path);
      if (!directory || !entry)
        return reply.code(404).send({ error: { message: 'Release not found' } });
      const file = join(directory, entry.path);
      const info = await stat(file);
      return reply
        .header('Content-Length', info.size)
        .header('Content-Disposition', `attachment; filename="${request.params.name}"`)
        .type('application/octet-stream')
        .send(createReadStream(file));
    },
  );
}
