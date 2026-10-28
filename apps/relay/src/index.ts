import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
import { createRelay } from './server';
const port = Number(process.env.PORT ?? 4319);
if (!process.env.JWT_SECRET) throw new Error('Set JWT_SECRET before starting Relay');
const { app } = await createRelay({
  dataDir: process.env.DATA_DIR ?? join(homedir(), '.nekodot-relay'),
  jwtSecret: process.env.JWT_SECRET,
  publicUrl: process.env.PUBLIC_URL ?? `http://127.0.0.1:${port}`,
  logger: true,
  distributionDirectory: resolve(process.env.DISTRIBUTION_DIR ?? 'dist/distribution'),
  ...(process.env.WEB_DIR ? { webDirectory: resolve(process.env.WEB_DIR) } : {}),
});
await app.listen({ host: process.env.HOST ?? '127.0.0.1', port });
for (const signal of ['SIGINT', 'SIGTERM'] as const)
  process.once(signal, () => {
    void app.close();
  });
