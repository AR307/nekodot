/** Hermes STT accepts mono, 16 kHz PCM in a standard WAV container. */
export function pcmWave(samples: Float32Array): ArrayBuffer {
  const wav = new ArrayBuffer(44 + samples.length * 2);
  const view = new DataView(wav);
  const label = (offset: number, text: string) => {
    for (let i = 0; i < text.length; i++) view.setUint8(offset + i, text.charCodeAt(i));
  };
  label(0, 'RIFF');
  view.setUint32(4, wav.byteLength - 8, true);
  label(8, 'WAVEfmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, 16000, true);
  view.setUint32(28, 32000, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  label(36, 'data');
  view.setUint32(40, samples.length * 2, true);
  samples.forEach((sample, i) => {
    const clipped = Math.max(-1, Math.min(1, sample));
    view.setInt16(44 + i * 2, clipped * (clipped < 0 ? 32768 : 32767), true);
  });
  return wav;
}
