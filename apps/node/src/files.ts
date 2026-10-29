import { randomUUID } from 'node:crypto';
import { mkdir, open, stat } from 'node:fs/promises';
import { createWriteStream } from 'node:fs';
import { pipeline } from 'node:stream/promises';
import { Readable } from 'node:stream';
import { basename, join, resolve, sep } from 'node:path';
import { lookup } from 'mime-types';
import {
  transferChunkBytes,
  type Attachment,
  type Message,
  type RpcParams,
  type TransferRequest,
  type TransferResponse,
} from '@nekodot/protocol';
import type { NodeDatabase } from './database';
import type { HermesRuntime } from './hermes/runtime';
import { NodeFault } from './fault';
import type { Operations } from './operations';

export function deliveryReferences(text: string): string[] {
  const found: string[] = [];
  for (const match of text.matchAll(
    /(?:^|\n)\s*MEDIA:\s*(?:"([^"]+)"|'([^']+)'|([^\r\n]+))|!?\[[^\]]*\]\(<?((?:sandbox:|file:\/\/|\/|\.\/|~\/)[^)>]+)>?\)/g,
  )) {
    let path = (match[1] ?? match[2] ?? match[3] ?? match[4] ?? '').trim();
    if (path.startsWith('sandbox:')) path = path.slice(8);
    if (path.startsWith('file://')) path = new URL(path).pathname;
    path = decodeURIComponent(path);
    if (path && !found.includes(path)) found.push(path);
  }
  return found;
}

export class FileLibrary {
  constructor(
    readonly database: NodeDatabase,
    readonly hermes: HermesRuntime,
    readonly operations: Operations,
  ) {}
  list(params: RpcParams<'files.list'>): Attachment[] {
    return this.database.db
      .prepare('SELECT data FROM attachments WHERE bot_id=? ORDER BY rowid DESC')
      .all(params.botId)
      .map((row) => JSON.parse(String(row.data)) as Attachment)
      .filter(
        (file) =>
          (!params.search || file.name.toLowerCase().includes(params.search.toLowerCase())) &&
          (!params.messageId || file.messageId === params.messageId) &&
          (!params.type ||
            (params.type === 'other'
              ? !/^(image\/|text\/|application\/pdf)/.test(file.mime)
              : file.mime.startsWith(params.type))),
      );
  }
  async capture(message: Extract<Message, { kind: 'text' }>) {
    if (message.author.type !== 'bot' || !message.author.id) return;
    const botId = message.author.id;
    const conversation = this.database
      .conversations()
      .find((item) => item.kind === 'dm' && item.botId === botId);
    if (!conversation) return;
    const sessionId = 'nk_dm_' + conversation.conversationId;
    const ids: string[] = [];
    for (const reference of deliveryReferences(message.content.text)) {
      const existing = this.database.db
        .prepare('SELECT file_id,data FROM attachments WHERE message_id=? AND reference=?')
        .get(message.messageId, reference);
      if (existing && (JSON.parse(String(existing.data)) as Attachment).available) {
        ids.push(String(existing.file_id));
        continue;
      }
      const fileId = existing ? String(existing.file_id) : randomUUID();
      const name = basename(reference) || 'attachment';
      const path = join(this.database.directory, 'library', fileId);
      let available = false,
        size = 0;
      let mime = lookup(name) || 'application/octet-stream';
      try {
        const response = await this.hermes.management.response(
          '/api/fs/download?path=' +
            encodeURIComponent(reference) +
            '&session_id=' +
            encodeURIComponent(sessionId),
          botId,
        );
        if (!response.body) throw new Error('No file content');
        await mkdir(join(this.database.directory, 'library'), { recursive: true, mode: 0o700 });
        await pipeline(
          Readable.fromWeb(response.body as import('node:stream/web').ReadableStream),
          createWriteStream(path, { mode: 0o600 }),
        );
        size = (await stat(path)).size;
        mime = response.headers.get('content-type')?.split(';')[0] ?? mime;
        available = true;
      } catch (error) {
        if (!(
          error instanceof NodeFault &&
          ['not_found', 'forbidden', 'unavailable'].includes(error.code)
        ))
          throw error;
      }
      const file: Attachment = {
        fileId,
        botId,
        conversationId: message.conversationId,
        messageId: message.messageId,
        name,
        mime,
        size,
        sentAt: message.createdAt,
        available,
      };
      this.database.db
        .prepare(
          'INSERT INTO attachments VALUES(?,?,?,?,?,?) ON CONFLICT(message_id,reference) DO UPDATE SET storage_path=excluded.storage_path,data=excluded.data',
        )
        .run(
          fileId,
          botId,
          message.messageId,
          reference,
          available ? path : null,
          JSON.stringify(file),
        );
      ids.push(fileId);
    }
    if (ids.length) message.content = { ...message.content, files: ids };
  }
  backfill(botId: string) {
    return this.operations.start('files.backfill', [botId], async (operation) => {
      const messages = this.database.db
        .prepare(
          "SELECT data FROM messages WHERE json_extract(data,'$.author.id')=? AND json_extract(data,'$.kind')='text' AND json_extract(data,'$.status')='done'",
        )
        .all(botId);
      let count = 0;
      for (const row of messages) {
        const message = JSON.parse(String(row.data)) as Extract<Message, { kind: 'text' }>;
        await this.capture(message);
        if (message.content.files?.length) {
          this.database.putMessage(message);
          count += message.content.files.length;
        }
      }
      operation.detail = `Indexed ${count} delivered files. Unreadable originals remain marked unavailable.`;
      operation.results.push({ botId, ok: true, detail: operation.detail });
    });
  }
  async createImport() {
    const importId = randomUUID();
    await mkdir(join(this.database.directory, 'imports', importId), {
      recursive: true,
      mode: 0o700,
    });
    return { importId };
  }
  async transfer(request: TransferRequest): Promise<TransferResponse> {
    if (request.action === 'read') {
      const row = this.database.db
        .prepare('SELECT storage_path,data FROM attachments WHERE file_id=?')
        .get(request.fileId);
      if (!row?.storage_path) throw new NodeFault('not_found', 'File is unavailable');
      const file = JSON.parse(String(row.data)) as Attachment;
      const handle = await open(String(row.storage_path), 'r');
      try {
        const buffer = Buffer.alloc(transferChunkBytes);
        const { bytesRead } = await handle.read(buffer, 0, buffer.length, request.offset);
        return {
          ok: true,
          data: buffer.subarray(0, bytesRead).toString('base64'),
          done: request.offset + bytesRead >= file.size,
          name: file.name,
          mime: file.mime,
          size: file.size,
        };
      } finally {
        await handle.close();
      }
    }
    const root = join(this.database.directory, 'imports', request.importId);
    await stat(root);
    const path = resolve(root, request.path);
    if (!path.startsWith(resolve(root) + sep))
      throw new NodeFault('invalid_params', 'Import path must stay inside its package');
    await mkdir(join(path, '..'), { recursive: true });
    const handle = await open(path, request.offset === 0 ? 'w' : 'r+');
    try {
      const bytes = Buffer.from(request.data, 'base64');
      await handle.write(bytes, 0, bytes.length, request.offset);
      return { ok: true };
    } finally {
      await handle.close();
    }
  }
}
