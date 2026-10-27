import { hermesSseEventSchema } from '@nekodot/protocol';

export interface SseFrame {
  event: string;
  data: Record<string, unknown>;
  raw: string;
}
export function parseSseFrame(raw: string): SseFrame | undefined {
  const lines = raw.replace(/\r\n/g, '\n').split('\n');
  const data = lines
    .filter((line) => line.startsWith('data:'))
    .map((line) => line.slice(5).trimStart())
    .join('\n');
  if (!data) return;
  const dataObject = hermesSseEventSchema.parse(JSON.parse(data));
  const event = dataObject.event;
  return { event, data: dataObject, raw: raw + '\n\n' };
}
export function parseSseText(text: string): SseFrame[] {
  return text
    .replace(/\r\n/g, '\n')
    .split(/\n\n/)
    .flatMap((raw) => {
      const frame = parseSseFrame(raw);
      return frame ? [frame] : [];
    });
}
export async function* readSse(response: Response): AsyncGenerator<SseFrame> {
  if (!response.body) throw new Error('Missing Hermes SSE body');
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let pending = '';
  try {
    while (true) {
      const { value, done } = await reader.read();
      pending = (pending + decoder.decode(value, { stream: !done })).replace(/\r\n/g, '\n');
      let boundary: number;
      while ((boundary = pending.indexOf('\n\n')) >= 0) {
        const raw = pending.slice(0, boundary);
        pending = pending.slice(boundary + 2);
        const frame = parseSseFrame(raw);
        if (frame) yield frame;
      }
      if (done) {
        if (pending.trim()) {
          const frame = parseSseFrame(pending);
          if (frame) yield frame;
        }
        break;
      }
    }
  } finally {
    await reader.cancel();
    reader.releaseLock();
  }
}
