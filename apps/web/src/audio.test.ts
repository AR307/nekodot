import { expect, test } from 'vitest';
import { pcmWave } from './audio';

test('creates a mono 16kHz WAV and clips samples to signed PCM16', () => {
  const wav = pcmWave(new Float32Array([-2, -1, 0, 1, 2]));
  const view = new DataView(wav);
  expect(new TextDecoder().decode(wav.slice(0, 4))).toBe('RIFF');
  expect(view.getUint32(4, true)).toBe(46);
  expect(view.getUint16(22, true)).toBe(1);
  expect(view.getUint32(24, true)).toBe(16000);
  expect(view.getUint32(40, true)).toBe(10);
  expect(Array.from({ length: 5 }, (_, i) => view.getInt16(44 + i * 2, true))).toEqual([
    -32768, -32768, 0, 32767, 32767,
  ]);
});
