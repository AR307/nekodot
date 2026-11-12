import { randomUUID } from 'node:crypto';
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { join, extname } from 'node:path';
import { zipSync } from 'fflate';
import { z } from 'zod';
import { spaceOriginSchema, type RpcParams, type Attachment } from '@nekodot/protocol';
import type { NodeDatabase } from './database';
import type { HermesRuntime } from './hermes/runtime';
import { NodeFault } from './fault';

const requestSchema = z.strictObject({
  action: z.literal('space'),
  operation: z.enum(['prepare', 'publish', 'list', 'get']),
  botId: z.string(),
  token: z.string(),
  sessionId: z.string(),
  callId: z.string(),
  admissionId: z.string(),
  spaceId: z.uuid().optional(),
  name: z.string().trim().min(1).optional(),
  origins: z.array(spaceOriginSchema).optional(),
});
const assetTypes = new Set([
  '.html',
  '.css',
  '.js',
  '.mjs',
  '.json',
  '.svg',
  '.png',
  '.jpg',
  '.jpeg',
  '.webp',
  '.gif',
  '.ico',
  '.woff',
  '.woff2',
  '.ttf',
  '.mp3',
  '.wav',
  '.ogg',
  '.mp4',
  '.webm',
]);

export class Spaces {
  constructor(
    readonly database: NodeDatabase,
    readonly hermes: HermesRuntime,
  ) {}
  list() {
    return { spaces: this.database.spaces().filter((space) => space.version > 0) };
  }
  get(id: string) {
    const space = this.database.space(id);
    if (!space) throw new NodeFault('not_found', 'Space not found');
    return space;
  }
  update(p: RpcParams<'spaces.update'>) {
    const space = this.get(p.spaceId);
    return this.database.putSpace({
      ...space,
      ...(p.name === undefined ? {} : { name: p.name }),
      ...(p.archived === undefined ? {} : { archived: p.archived }),
      updatedAt: new Date().toISOString(),
    });
  }
  authorize(p: RpcParams<'spaces.authorize'>) {
    const space = this.get(p.spaceId);
    if (p.origins.some((origin) => !space.origins.includes(origin)))
      throw new NodeFault('invalid_params', 'Website was not requested by this space');
    return this.database.putSpace({ ...space, allowedOrigins: [...new Set(p.origins)] });
  }
  read(id: string) {
    this.get(id);
    return this.database.spaceData(id);
  }
  write(p: RpcParams<'spaces.data.write'>) {
    this.get(p.spaceId);
    return this.database.putSpaceRecords(p.spaceId, p.mutationId, p.records);
  }
  async local(value: unknown) {
    const p = requestSchema.parse(value);
    if (!this.database.bot(p.botId)) throw new NodeFault('not_found', 'Bot not found');
    const token = await readFile(
      join(this.hermes.profileHome(p.botId), 'plugins', 'nekodot-secrets', 'bridge.token'),
      'utf8',
    );
    if (p.token !== token.trim())
      throw new NodeFault('forbidden', 'Profile does not own this request');
    const receipt = `space-call:${p.botId}:${p.sessionId}:${p.admissionId}:${p.callId}`;
    const previous = this.database.setting<{ result: unknown }>(receipt);
    if (previous) return previous.result;
    const run = this.database
      .runs()
      .find(
        (run) =>
          run.botId === p.botId &&
          (run.sessionId === p.sessionId || run.storedSessionId === p.sessionId) &&
          run.runId === p.admissionId,
      );
    const conversation =
      run?.conversationId ??
      this.database.conversations().find((c) => c.kind === 'dm' && c.botId === p.botId)
        ?.conversationId;
    if (!conversation) throw new NodeFault('not_found', 'Space needs an owning chat');
    if (p.operation === 'list')
      return this.database.spaces().filter((space) => space.botId === p.botId);
    let space = p.spaceId ? this.get(p.spaceId) : undefined;
    if (space && space.botId !== p.botId)
      throw new NodeFault('forbidden', 'Space belongs to another Dot');
    if (!space && p.operation !== 'prepare')
      throw new NodeFault('invalid_params', 'Prepare a space first');
    if (!space) {
      if (!p.name) throw new NodeFault('invalid_params', 'Space name is required');
      const now = new Date().toISOString();
      space = {
        spaceId: randomUUID(),
        botId: p.botId,
        conversationId: conversation,
        name: p.name,
        version: 0,
        origins: [],
        allowedOrigins: [],
        archived: false,
        createdAt: now,
        updatedAt: now,
      };
    }
    const directory = join(this.hermes.profileHome(p.botId), 'spaces', space.spaceId, 'site');
    let result: unknown;
    if (p.operation === 'get') return { space, directory, data: this.read(space.spaceId) };
    if (p.operation === 'prepare') {
      await mkdir(directory, { recursive: true });
      this.database.putSpace(space);
      result = { space, directory };
    } else {
      if (space.archived) throw new NodeFault('invalid_params', 'Space is archived');
      const files: Record<string, Uint8Array> = {};
      const visit = async (path: string, prefix = '') => {
        for (const entry of await readdir(path, { withFileTypes: true })) {
          const name = prefix + entry.name;
          if (entry.name.startsWith('.') || entry.isSymbolicLink())
            throw new NodeFault('invalid_params', 'Space contains a hidden file or symlink');
          if (entry.isDirectory()) await visit(join(path, entry.name), name + '/');
          else if (entry.isFile() && assetTypes.has(extname(entry.name).toLowerCase()))
            files[name] = await readFile(join(path, entry.name));
          else throw new NodeFault('invalid_params', 'Unsupported space resource: ' + name);
        }
      };
      await visit(directory);
      if (!files['index.html']) throw new NodeFault('invalid_params', 'Space needs index.html');
      const fileId = randomUUID(),
        storage = join(this.database.directory, 'library', fileId);
      const bytes = zipSync(files);
      await mkdir(join(storage, '..'), { recursive: true });
      await writeFile(storage, bytes);
      const file: Attachment = {
        fileId,
        botId: p.botId,
        conversationId: space.conversationId,
        messageId: fileId,
        name: `${space.spaceId}.zip`,
        mime: 'application/zip',
        size: bytes.length,
        sentAt: new Date().toISOString(),
        available: true,
      };
      this.database.db
        .prepare('INSERT INTO attachments VALUES(?,?,?,?,?,?)')
        .run(
          fileId,
          p.botId,
          fileId,
          `space:${space.spaceId}:${space.version + 1}`,
          storage,
          JSON.stringify(file),
        );
      const origins = p.origins ?? space.origins;
      space = {
        ...space,
        name: p.name ?? space.name,
        version: space.version + 1,
        fileId,
        origins: [...new Set(origins)],
        allowedOrigins: space.allowedOrigins.filter((origin) => origins.includes(origin)),
        updatedAt: new Date().toISOString(),
      };
      this.database.putSpace(space);
      this.database.db
        .prepare('INSERT OR IGNORE INTO space_publications VALUES(?,?)')
        .run(run?.inputMessageId ?? 'native:' + p.sessionId, space.spaceId);
      result = { space, published: true };
    }
    this.database.setSetting(receipt, { result });
    return result;
  }
}
