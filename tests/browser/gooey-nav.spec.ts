import { expect, test, type Locator } from '@playwright/test';
import { userMemoryEnvironment } from '../support/user-memory-environment';

test('Gooey Nav keeps all three navigation groups controlled, accessible and aligned', async ({
  page,
}) => {
  test.setTimeout(90_000);
  // Recorded management only: this supplements live navigation acceptance.
  const environment = await userMemoryEnvironment();
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  const aligned = async (root: Locator) => {
    await expect(root.locator('[aria-current="page"]')).toHaveCount(1);
    await expect
      .poll(async () => {
        const selected = await root.locator('[aria-current="page"]').boundingBox();
        const pill = await root.locator('.gooey-nav__effect').boundingBox();
        if (!selected || !pill) return false;
        return (['x', 'y', 'width', 'height'] as const).every(
          (key) => Math.abs(selected[key] - pill[key]) < 1,
        );
      })
      .toBe(true);
  };
  try {
    await page.addInitScript(
      ({ token, nodeId }) => {
        localStorage.setItem('nekodot-token', token);
        localStorage.setItem('nekodot-node', nodeId);
        localStorage.setItem('nekodot-language', 'zh');
      },
      {
        token: environment.accounts[0]!.token,
        nodeId: environment.nodes[0]!.credentials.nodeId,
      },
    );
    await page.setViewportSize({ width: 1440, height: 960 });
    await page.goto(environment.url);
    const main = page.getByRole('navigation', { name: 'nekoDOT', exact: true });
    await main.getByRole('button', { name: 'Skills', exact: true }).click();
    await expect(page.locator('.extensions-page h1')).toHaveText('Skills');
    await aligned(main);
    await page.keyboard.press('Control+k');
    await page.locator('.palette input').fill('插件');
    await page.keyboard.press('Enter');
    await expect(main.locator('[aria-current="page"]')).toHaveText('插件');
    await aligned(main);
    await main.getByRole('button', { name: '聊天', exact: true }).click();
    await page.locator('.bot-row').filter({ hasText: 'Maple' }).click();
    await page.locator('.chat-title').click();
    const details = page.locator('.details-tabs .gooey-nav');
    await details.getByRole('button', { name: '记忆', exact: true }).click();
    const documents = page.locator('.document-tabs.gooey-nav');
    await documents.getByRole('button', { name: 'USER.md', exact: true }).click();
    await expect(page.locator('#shared-user-memory-editor')).toBeVisible();
    await aligned(documents);
    await documents.getByRole('button', { name: 'SOUL.md', exact: true }).focus();
    await page.keyboard.press('ArrowRight');
    await expect(documents.locator('[aria-current="page"]')).toHaveText('MEMORY.md');
    await aligned(documents);
    await page.keyboard.press('End');
    await expect(documents.locator('[aria-current="page"]')).toHaveText('USER.md');
    await page.keyboard.press('Home');
    await expect(documents.locator('[aria-current="page"]')).toHaveText('SOUL.md');
    for (const width of [320, 390, 768, 1440]) {
      await page.setViewportSize({ width, height: 960 });
      await aligned(details);
      await aligned(documents);
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
        true,
      );
      for (const root of [details, documents]) {
        const buttons = root.getByRole('button');
        for (const button of await buttons.all()) {
          const box = await button.boundingBox();
          expect(box!.height).toBeGreaterThanOrEqual(44);
          expect(box!.x).toBeGreaterThanOrEqual(0);
          expect(box!.x + box!.width).toBeLessThanOrEqual(width);
        }
      }
      await page.screenshot({ path: `.runtime/gooey-details-${width}.png` });
    }
    await details.getByRole('button', { name: '资料库', exact: true }).click();
    await expect(documents).toHaveCount(0);
    await aligned(details);
    await details.getByRole('button', { name: '记忆', exact: true }).click();
    // A new document navigation starts on its controlled SOUL.md selection.
    await expect(documents.locator('[aria-current="page"]')).toHaveText('SOUL.md');
    await aligned(documents);
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await documents.getByRole('button', { name: 'MEMORY.md', exact: true }).click();
    await expect(documents).toHaveAttribute('data-reduced-motion', 'true');
    await expect(documents.locator('.gooey-nav__particle')).toHaveCount(0);
    await expect(documents.locator('.gooey-nav__effect')).toHaveCSS('transition-duration', '0s');
    await aligned(documents);
    await page.emulateMedia({ reducedMotion: 'no-preference' });
    for (let i = 0; i < 8; i++) {
      await documents
        .getByRole('button', { name: i % 2 ? 'USER.md' : 'SOUL.md', exact: true })
        .click();
    }
    await expect(documents.locator('.gooey-nav__particle')).toHaveCount(0, { timeout: 4_000 });
    await aligned(documents);
    expect(errors).toEqual([]);
  } finally {
    await environment.close();
  }
});
