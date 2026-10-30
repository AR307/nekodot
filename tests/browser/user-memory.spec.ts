import { expect, test } from '@playwright/test';
import { USER_MEMORY_SEPARATOR } from '@nekodot/protocol';
import { userMemoryEnvironment } from '../support/user-memory-environment';

test('shared USER.md: confirm originals, switch computers, resolve competing offline edits and keep drafts', async ({
  page,
}) => {
  test.setTimeout(120_000);
  const environment = await userMemoryEnvironment();
  const [a, b, other] = environment.nodes;
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  const openMemory = async (name: string) => {
    await page.locator('.bot-row').filter({ hasText: name }).click();
    await page.locator('.chat-title').click();
    await page.locator('.details-tabs').getByRole('button', { name: '记忆', exact: true }).click();
    await page
      .locator('.document-tabs')
      .getByRole('button', { name: 'USER.md', exact: true })
      .click();
    await expect(page.locator('#shared-user-memory-editor')).toBeVisible();
  };
  const editor = page.locator('#shared-user-memory-editor');
  try {
    await page.addInitScript(
      ({ token, nodeId }) => {
        localStorage.setItem('nekodot-token', token);
        if (!localStorage.getItem('nekodot-node')) localStorage.setItem('nekodot-node', nodeId);
      },
      { token: environment.accounts[0]!.token, nodeId: a!.credentials.nodeId },
    );
    await page.goto(environment.url);
    await openMemory('Maple');
    await expect(page.getByRole('heading', { name: '确认已有用户记忆' })).toBeVisible();
    await expect(editor).toHaveValue(
      'Prefers concise answers.' + USER_MEMORY_SEPARATOR + 'Uses metric units.',
    );
    expect(await b!.read()).toBe('Uses metric units.');
    await page.getByRole('button', { name: '保存并确认以上内容', exact: true }).click();
    await expect(page.getByText('记忆已保存', { exact: true })).toBeVisible();
    await expect.poll(() => b!.read()).toContain('Prefers concise answers.');
    await page
      .locator('.details-header')
      .getByRole('button', { name: '关闭', exact: true })
      .click();
    await page.locator('.node-picker > summary').click();
    await page.getByRole('menuitemradio', { name: /Computer B/ }).click();
    await openMemory('Cedar');
    const original = await b!.read();
    await b!.disconnect();
    await a!.write(original + USER_MEMORY_SEPARATOR + 'Likes mint tea.');
    await a!.app.userMemory.sync();
    await b!.write(original + USER_MEMORY_SEPARATOR + 'Prefers local times.');
    b!.reconnect();
    await expect
      .poll(async () => {
        await b!.app.userMemory.sync();
        return b!.read();
      })
      .toContain('Likes mint tea.');
    await a!.app.userMemory.sync();
    const base = await a!.read();
    await b!.disconnect();
    await a!.write(base.replace('Likes mint tea.', 'Likes jasmine tea.'));
    await a!.app.userMemory.sync();
    await b!.write(base.replace('Likes mint tea.', 'Likes black tea.'));
    b!.reconnect();
    await expect
      .poll(async () => {
        await b!.app.userMemory.sync();
        return b!.app.userMemory.view().shared!.conflicts.length;
      })
      .toBe(1);
    await page
      .locator('.shared-user-memory')
      .getByRole('button', { name: '刷新', exact: true })
      .click();
    await expect(page.getByRole('heading', { name: '同一条记忆有不同修改' })).toBeVisible();
    await expect(page.locator('section.memory-proposals')).toContainText('Likes black tea.');
    for (const width of [1440, 768, 390]) {
      await page.setViewportSize({ width, height: 1000 });
      await page.locator('.details-scroll').evaluate((el) => {
        el.scrollTop = 0;
      });
      await page.getByRole('heading', { name: '同一条记忆有不同修改' }).scrollIntoViewIfNeeded();
      await page.screenshot({
        path: `docs/evidence/side-phase3-user-memory-${width}.png`,
        animations: 'disabled',
      });
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
        true,
      );
    }
    await editor.fill(base.replace('Likes mint tea.', 'Likes jasmine tea and black tea.'));
    await page
      .locator('.shared-user-memory')
      .getByRole('button', { name: '刷新', exact: true })
      .click();
    await expect(editor).toHaveValue(
      base.replace('Likes mint tea.', 'Likes jasmine tea and black tea.'),
    );
    await page.getByRole('button', { name: '保存并确认以上内容', exact: true }).click();
    await expect(page.getByText('记忆已保存', { exact: true })).toBeVisible();
    await expect.poll(() => a!.read()).toContain('Likes jasmine tea and black tea.');
    await page.getByText('已保留的原件与处理记录', { exact: true }).click();
    await expect(page.locator('.shared-user-memory')).toContainText('Maple · USER.md');
    await b!.restart();
    await page.setViewportSize({ width: 1440, height: 1000 });
    await page.reload();
    await openMemory('Cedar');
    await expect(editor).toHaveValue(
      base.replace('Likes mint tea.', 'Likes jasmine tea and black tea.'),
    );
    await page.evaluate(() => {
      localStorage.setItem('nekodot-language', 'en');
      localStorage.setItem('nekodot-theme', 'dark');
    });
    await page.reload();
    await page.locator('.bot-row').filter({ hasText: 'Cedar' }).click();
    await page.locator('.chat-title').click();
    await page
      .locator('.details-tabs')
      .getByRole('button', { name: 'Memory', exact: true })
      .click();
    await page
      .locator('.document-tabs')
      .getByRole('button', { name: 'USER.md', exact: true })
      .click();
    await page.emulateMedia({ colorScheme: 'dark', reducedMotion: 'reduce' });
    await page.setViewportSize({ width: 390, height: 1000 });
    await expect(editor).toBeVisible();
    await page.screenshot({
      path: 'docs/evidence/side-phase3-user-memory-dark-en.png',
      animations: 'disabled',
    });
    expect(await other!.read()).toBe('OTHER_ACCOUNT_ONLY');
    expect(errors).toEqual([]);
  } finally {
    await environment.close();
  }
});
