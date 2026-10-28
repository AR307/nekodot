import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import type { FastifyInstance } from 'fastify';

export function registerDownloads(app: FastifyInstance, directory: string, publicUrl: string) {
  app.get('/install.sh', async (_request, reply) => {
    const script = await readFile(join(directory, 'install.sh'), 'utf8');
    return reply
      .header('Cache-Control', 'no-store')
      .type('text/x-shellscript; charset=utf-8')
      .send(script.replaceAll('__NEKODOT_RELAY_URL__', publicUrl.replace(/\/$/, '')));
  });
  app.get('/downloads/nekodot-node.cjs', async (_request, reply) =>
    reply
      .header('Cache-Control', 'no-store')
      .type('application/javascript; charset=utf-8')
      .send(await readFile(join(directory, 'nekodot-node.cjs'))),
  );
}
