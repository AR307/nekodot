import { test, expect } from '@playwright/test';
import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { createRelay } from '../../apps/relay/src/server';
import { connectRelay } from '../../apps/node/src/connection';
import { pairNode } from '../../apps/node/src/pair';
import { seedVerifiedAccount } from '../support/account';

test('Edge shows a copyable legacy command and removes it when the same computer upgrades', async ({
  page,
}) => {
  const home = await mkdtemp(join(tmpdir(), 'nekodot-update-browser-'));
  const email = `update-${randomUUID()}@example.test`,
    password = randomUUID();
  const relay = await createRelay({
    dataDir: join(home, 'relay'),
    jwtSecret: randomUUID(),
    publicUrl: 'http://127.0.0.1:4398',
    webDirectory: join(process.cwd(), 'apps/web/dist'),
  });
  await relay.app.listen({ host: '127.0.0.1', port: 4398 });
  await seedVerifiedAccount(relay.database, email, password);
  const login = await relay.app.inject({
    method: 'POST',
    url: '/api/auth/login',
    payload: { email, password },
  });
  const code = await relay.app.inject({
    method: 'POST',
    url: '/api/pairing-codes',
    headers: { authorization: 'Bearer ' + login.json().token },
    payload: {},
  });
  const credentials = await pairNode(
    join(home, 'node'),
    'http://127.0.0.1:4398',
    code.json().code,
    'Update computer',
  );
  // This UI test uses empty conversation data; real legacy bundles/systemd are tested separately.
  const node = (version: string) =>
    connectRelay({
      version,
      credentials,
      handleRpc: async (request) =>
        request.method === 'sync.snapshot'
          ? {
              node: {
                platform: 'linux',
                computerUse: false,
              },
              bots: [],
              groups: [],
              conversations: [],
              headSeq: 0,
            }
          : request.method === 'sync.since'
            ? { events: [], resyncRequired: false }
            : {},
    });
  let connection = node('1.0.0');
  try {
    await page.goto('http://127.0.0.1:4398');
    await page.getByRole('button', { name: '已有账号？登录', exact: true }).click();
    await page.getByLabel('邮箱', { exact: true }).fill(email);
    await page.getByLabel('密码', { exact: true }).fill(password);
    await page.getByRole('button', { name: '继续', exact: true }).click();
    const notice = page.locator('.node-update-notice');
    await expect(notice).toContainText('这台电脑需要更新一次');
    await expect(notice.locator('code')).toHaveText(
      "curl -fsSL 'http://127.0.0.1:4398/install.sh' | bash",
    );
    await notice.getByRole('button').click();
    await expect(notice).toContainText('已复制');
    connection.close();
    connection = node('20261031010000');
    await expect(notice).toHaveCount(0);
    await expect(page.locator('.node-picker summary')).toContainText('Update computer');
  } finally {
    connection.close();
    await relay.app.close();
  }
});
