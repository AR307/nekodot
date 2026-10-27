import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { parseSseText, readSse } from './sse';

describe('real Hermes stream transport', () => {
  it('decodes JSON event names across byte chunks and CRLF boundaries', async () => {
    const recorded = await readFile(resolve('docs/fixtures/runs-tools-approval.sse'), 'utf8');
    const expected = parseSseText(recorded);
    const bytes = new TextEncoder().encode(': open\r\n\r\n' + recorded.replace(/\n/g, '\r\n'));
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        for (let index = 0; index < bytes.length; index += 7)
          controller.enqueue(bytes.slice(index, index + 7));
        controller.close();
      },
    });
    const actual = [];
    for await (const frame of readSse(new Response(stream))) actual.push(frame);
    expect(actual.map((frame) => ({ event: frame.event, data: frame.data }))).toEqual(
      expected.map((frame) => ({ event: frame.event, data: frame.data })),
    );
    expect(actual.some((frame) => frame.event === 'approval.request')).toBe(true);
  });
});
