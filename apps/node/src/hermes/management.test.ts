import { createServer } from 'node:http';
import type { AddressInfo } from 'node:net';
import { expect, it } from 'vitest';
import { HermesManagement } from './management';

it('reports a management request that outlasts its deadline as a timeout fault, not a raw abort', async () => {
  // Hermes accepts the request but never answers, as a slow provider catalog probe does.
  const server = createServer(() => {});
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address() as AddressInfo;
  const management = new HermesManagement(`http://127.0.0.1:${port}`, 'management-test-only');
  try {
    await expect(
      management.request('/api/model/set', 'nk-test', {
        method: 'POST',
        body: '{}',
        signal: AbortSignal.timeout(50),
      }),
    ).rejects.toMatchObject({
      name: 'Error',
      code: 'timeout',
      message: 'Hermes did not respond in time. Try again.',
    });
  } finally {
    management.close();
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
  }
});
