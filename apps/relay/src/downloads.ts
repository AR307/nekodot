import { readFile, stat } from 'node:fs/promises';
import { createReadStream, existsSync } from 'node:fs';
import { join } from 'node:path';
import type { FastifyInstance } from 'fastify';
import { nodeReleaseSchema } from '@nekodot/protocol';

export async function latestNodeRelease(
  directory: string,
  log: Pick<FastifyInstance['log'], 'warn'>,
) {
  try {
    return nodeReleaseSchema.parse(
      JSON.parse(await readFile(join(directory, 'nekodot-node.json'), 'utf8')),
    );
  } catch (error) {
    if (!(error instanceof Error && 'code' in error && error.code === 'ENOENT'))
      log.warn('Published Node manifest is invalid or unreadable');
    return undefined;
  }
}

export function registerDownloads(app: FastifyInstance, directory: string, publicUrl: string) {
  app.get<{ Params: { version: string; file: string } }>(
    '/downloads/hermes/:version/:file',
    async (request, reply) => {
      const { version, file } = request.params;
      if (
        !/^v\d+\.\d+\.\d+-r\d+$/.test(version) ||
        !/^(win32-x64|darwin-arm64|linux-x64)\.(json|tar\.gz)$/.test(file)
      )
        return reply.code(404).send();
      const path = join(directory, 'hermes', version, file);
      if (!existsSync(path)) return reply.code(404).send();
      const { size } = await stat(path);
      reply.type(file.endsWith('.json') ? 'application/json' : 'application/gzip');
      reply.header('Accept-Ranges', 'bytes');
      const range = request.headers.range;
      if (range) {
        const match = /^bytes=(\d+)-(\d*)$/.exec(range);
        const start = match ? Number(match[1]) : -1;
        const end = match?.[2] ? Number(match[2]) : size - 1;
        if (start < 0 || start >= size || end < start || end >= size)
          return reply.code(416).header('Content-Range', `bytes */${size}`).send();
        return reply
          .code(206)
          .header('Content-Range', `bytes ${start}-${end}/${size}`)
          .header('Content-Length', end - start + 1)
          .send(createReadStream(path, { start, end }));
      }
      return reply.header('Content-Length', size).send(createReadStream(path));
    },
  );
  app.get('/downloads/nekodot-node.json', async (_request, reply) => {
    reply.header('Cache-Control', 'no-store');
    const release = await latestNodeRelease(directory, app.log);
    if (!release)
      return reply
        .code(404)
        .send({ error: { code: 'not_found', message: 'No Node release published' } });
    return release;
  });
  for (const [name, mime] of [
    ['nekodot-windows-x64.exe', 'application/vnd.microsoft.portable-executable'],
    ['nekodot-android-arm64.apk', 'application/vnd.android.package-archive'],
  ] as const) {
    app.get('/downloads/' + name, (_request, reply) => {
      const path = join(directory, name);
      if (!existsSync(path))
        return reply.code(404).send({
          error: { code: 'not_found', message: 'This client build has not been published' },
        });
      return reply
        .header('Content-Disposition', `attachment; filename="${name}"`)
        .type(mime)
        .send(createReadStream(path));
    });
  }
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
