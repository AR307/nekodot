import { expect, it } from 'vitest';
import { join } from 'node:path';
import { startFakeHermes } from './server';
import { HermesManagement } from '../../../apps/node/src/hermes/management';

it('replays captured native display state per profile and broadcasts native lease changes', async () => {
  const fake = await startFakeHermes({
    fixturesDirectory: join(process.cwd(), 'docs/fixtures'),
    apiKey: 'display-replay-key',
    profiles: ['default'],
  });
  const management = new HermesManagement(fake.url, 'display-replay-key');
  try {
    const maple = await management.rpc<Record<string, unknown>>('display.status', {
      profile: 'nk-abcdef',
    });
    expect(maple).toMatchObject({ running: true, installed: true, geometry: '1440x900' });
    const viewer = await management.rpc<{ viewer_id: string }>('display.observe', {
      profile: 'nk-abcdef',
    });
    expect(viewer.viewer_id.length).toBeGreaterThan(0);
    const changed = new Promise<unknown>((resolve) =>
      management.listeners.add((event) => {
        if (event.type === 'display.lease') resolve(event.payload);
      }),
    );
    await management.rpc('display.lease.acquire', {
      profile: 'nk-abcdef',
      viewer_id: viewer.viewer_id,
    });
    expect(await changed).toMatchObject({ lease: { holder: 'human' } });
    expect(await management.rpc('display.status', { profile: 'nk-ghijkl' })).toMatchObject({
      lease: { holder: 'agent' },
    });
    await management.rpc('display.lease.release', {
      profile: 'nk-abcdef',
      viewer_id: viewer.viewer_id,
    });
    expect(await management.rpc('display.status', { profile: 'nk-abcdef' })).toMatchObject({
      lease: { holder: 'agent' },
    });
    await management.rpc('display.stop', { profile: 'nk-abcdef' });
    expect(await management.rpc('display.status', { profile: 'nk-abcdef' })).toMatchObject({
      running: false,
    });
  } finally {
    management.close();
    await fake.close();
  }
});
