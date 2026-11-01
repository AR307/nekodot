import { randomUUID } from 'node:crypto';
import { mkdir, open, stat, copyFile, readFile } from 'node:fs/promises';
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
import type { HermesInput } from './hermes/api';

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
  get(fileId: string): Attachment {
    const row = this.database.db
      .prepare('SELECT data FROM attachments WHERE file_id=?')
      .get(fileId);
    if (!row) throw new NodeFault('not_found', 'Attachment not found');
    return JSON.parse(String(row.data)) as Attachment;
  }
  async receive(input: RpcParams<'files.receive'>): Promise<Attachment> {
    if (!this.database.conversation(input.conversationId))
      throw new NodeFault('not_found', 'Conversation not found');
    const root = resolve(this.database.directory, 'imports', input.importId);
    const source = resolve(root, input.path);
    if (!source.startsWith(root + sep))
      throw new NodeFault('invalid_params', 'Invalid upload path');
    const info = await stat(source);
    if (!info.isFile()) throw new NodeFault('invalid_params', 'Upload must be a file');
    const previous = this.database.db
      .prepare('SELECT data FROM attachments WHERE reference=? AND bot_id=?')
      .get('upload:' + input.importId + '/' + input.path, '');
    if (previous) return JSON.parse(String(previous.data)) as Attachment;
    const fileId = randomUUID();
    const storage = join(this.database.directory, 'library', fileId);
    await mkdir(join(storage, '..'), { recursive: true, mode: 0o700 });
    await copyFile(source, storage);
    const file: Attachment = {
      fileId,
      conversationId: input.conversationId,
      messageId: fileId,
      name: basename(input.path),
      mime: lookup(input.path) || 'application/octet-stream',
      size: info.size,
      sentAt: new Date().toISOString(),
      available: true,
    };
    this.database.db
      .prepare(
        'INSERT INTO attachments(file_id,bot_id,message_id,reference,storage_path,data) VALUES(?,?,?,?,?,?)',
      )
      .run(
        fileId,
        '',
        file.messageId,
        'upload:' + input.importId + '/' + input.path,
        storage,
        JSON.stringify(file),
      );
    return file;
  }
  attach(message: Extract<Message, { kind: 'text' }>, ids: string[]) {
    for (const id of ids) {
      const file = this.get(id);
      if (
        file.botId ||
        file.conversationId !== message.conversationId ||
        (file.messageId !== file.fileId && file.messageId !== message.messageId)
      )
        throw new NodeFault(
          'invalid_params',
          'Attachment is not an unsent file in this conversation',
        );
    }
    message.content.files = [...new Set(ids)];
  }
  async input(botId: string, text: string, ids: string[] = []): Promise<HermesInput> {
    if (!ids.length) return text;
    const parts: Exclude<HermesInput, string>[number]['content'] = [];
    const paths: string[] = [];
    for (const id of ids) {
      const file = this.get(id);
      const row = this.database.db
        .prepare('SELECT storage_path FROM attachments WHERE file_id=?')
        .get(id)!;
      const path = join(this.hermes.profileHome(botId), 'uploads', id, file.name);
      await mkdir(join(path, '..'), { recursive: true, mode: 0o700 });
      await copyFile(String(row.storage_path), path);
      paths.push(`[Attached file: ${JSON.stringify(path)} (${file.mime})]`);
      if (/^image\/(png|jpeg|webp|gif)$/.test(file.mime)) {
        parts.push({
          type: 'image_url',
          image_url: {
            url: `data:${file.mime};base64,${(await readFile(path)).toString('base64')}`,
          },
        });
      }
    }
    const content = (text || 'Please inspect the attached files.') + '\n\n' + paths.join('\n');
    return parts.length
      ? [{ role: 'user', content: [{ type: 'text', text: content }, ...parts] }]
      : content;
  }
  async gatewayInput(botId: string, text: string, ids: string[] = []) {
    const references: string[] = [];
    const attachments: { path: string; mime: string }[] = [];
    for (const id of ids) {
      const file = this.get(id);
      const row = this.database.db
        .prepare('SELECT storage_path FROM attachments WHERE file_id=?')
        .get(id)!;
      const profileHome = this.hermes.profileHome(botId);
      const path = join(profileHome, 'uploads', id, file.name);
      await mkdir(join(path, '..'), { recursive: true, mode: 0o700 });
      await copyFile(String(row.storage_path), path);
      references.push(`[Attached file: ${JSON.stringify(path)} (${file.mime})]`);
      const extension =
        file.mime === 'image/png'
          ? '.png'
          : file.mime === 'image/jpeg'
            ? '.jpg'
            : file.mime === 'image/webp'
              ? '.webp'
              : file.mime === 'image/gif'
                ? '.gif'
                : undefined;
      if (extension) {
        const imagePath = join(profileHome, 'cache', 'images', id + extension);
        await mkdir(join(imagePath, '..'), { recursive: true, mode: 0o700 });
        await copyFile(String(row.storage_path), imagePath);
        attachments.push({ path: imagePath, mime: file.mime });
      }
    }
    return {
      text:
        (text || 'Please inspect the attached files.') +
        (references.length ? '\n\n' + references.join('\n') : ''),
      attachments,
    };
  }
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
    const sessionId = this.database.hermesSession(conversation.conversationId)?.storedSessionId;
    if (!sessionId) return;
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
