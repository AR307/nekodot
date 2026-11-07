import { mkdtemp } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { expect, it } from 'vitest';
import { NodeDatabase, type RunRecord } from '../database';
import { RunMessages } from './messages';

it('keeps live deltas, then releases completed, stopped and failed replies after storage', async () => {
  const database = new NodeDatabase(await mkdtemp(join(tmpdir(), 'nekodot-buffer-')));
  const messages = new RunMessages(database, () => {});
  const run: RunRecord = {
    conversationId: 'chat',
    botId: 'bot',
    inputMessageId: 'input',
    runId: 'turn',
    lastSeq: 0,
    state: 'thinking',
  };
  for (const status of ['done', 'cancelled', 'failed'] as const) {
    const reply = messages.newText(run, '', 'streaming');
    messages.persistText(run, reply, 1);
    messages.append(run, reply, 'Actual streamed answer', 2);
    expect(messages.buffered(reply.messageId)).toBe('Actual streamed answer');
    reply.status = status;
    messages.persistText(run, reply, 3);
    expect(messages.buffered(reply.messageId)).toBeUndefined();
    expect(database.message(reply.messageId)?.content).toMatchObject({
      text: 'Actual streamed answer',
    });
  }
  const beforeTool = messages.newText(run, 'I will inspect the file.', 'streaming');
  messages.persistText(run, beforeTool, 4);
  database.putMessage({ ...beforeTool, kind: 'commentary', status: 'done' }, { runId: run.runId });
  messages.release(beforeTool.messageId);
  expect(messages.buffered(beforeTool.messageId)).toBeUndefined();
  expect(database.message(beforeTool.messageId)?.kind).toBe('commentary');
  database.db.close();
});
