import { expect, test, type Page } from '@playwright/test';
import { userMemoryEnvironment } from '../support/user-memory-environment';

/**
 * Keyboard ergonomics of the shell (criterion E4): menu-button and menu patterns, the
 * command palette's focus containment and where focus lands in read-only drawers.
 * Recorded management data; this supplements live acceptance.
 */
const focused = (page: Page) =>
  page.evaluate(() => {
    const element = document.activeElement;
    return {
      role: element?.getAttribute('role') ?? element?.tagName.toLowerCase(),
      text: (element?.textContent ?? '').trim().replace(/\s+/g, ' ').slice(0, 40),
      className: element?.className.toString() ?? '',
    };
  });

test('shell menus, palette and drawers follow keyboard patterns', async ({ browser }) => {
  test.setTimeout(120_000);
  const environment = await userMemoryEnvironment();
  try {
    const signIn = async (width: number, touch: boolean) => {
      const context = await browser.newContext({
        viewport: { width, height: 900 },
        hasTouch: touch,
        isMobile: touch,
      });
      await context.addInitScript(
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
      const page = await context.newPage();
      await page.goto(environment.url);
      await expect(page.locator('.bot-row').first()).toBeVisible({ timeout: 30_000 });
      return { context, page };
    };

    // Desktop: computer menu (role="menu") moves with arrows, Escape returns to its trigger.
    const desktop = await signIn(1440, false);
    let page = desktop.page;
    await page.locator('.node-picker summary').focus();
    await page.keyboard.press('Enter');
    await expect(page.locator('.node-menu')).toBeVisible();
    await page.keyboard.press('ArrowDown');
    expect((await focused(page)).role).toBe('menuitemradio');
    await page.keyboard.press('End');
    expect((await focused(page)).text).toContain('添加电脑');
    await page.keyboard.press('ArrowDown');
    expect((await focused(page)).role).toBe('menuitemradio');
    await page.keyboard.press('ArrowUp');
    expect((await focused(page)).text).toContain('添加电脑');
    await page.keyboard.press('Escape');
    await expect(page.locator('.node-menu')).toBeHidden();
    expect((await focused(page)).role).toBe('summary');

    // Palette: Tab stays on the combobox, Escape closes and focus returns to the trigger.
    await page.locator('.search-trigger').focus();
    await page.keyboard.press('Enter');
    await expect(page.locator('.palette')).toBeVisible();
    expect((await focused(page)).role).toBe('combobox');
    for (let i = 0; i < 4; i++) await page.keyboard.press(i % 2 ? 'Shift+Tab' : 'Tab');
    expect((await focused(page)).role).toBe('combobox');
    await page.keyboard.type('Maple');
    await expect(page.locator('.palette [role="option"]')).toHaveCount(1);
    await page.keyboard.press('Escape');
    await expect(page.locator('.palette')).toBeHidden();
    expect((await focused(page)).className).toContain('search-trigger');

    // Read-only drawer: focus starts on the panel, not on an action button.
    await page.locator('.bot-row').filter({ hasText: 'Maple' }).click();
    await page.locator('.chat-title').focus();
    await page.keyboard.press('Enter');
    await expect(page.locator('.details-tabs')).toBeVisible();
    expect((await focused(page)).role).toBe('dialog');
    await page.keyboard.press('Escape');
    await expect(page.locator('.details-tabs')).toBeHidden();
    await desktop.context.close();

    // Phone: the + menu moves focus into its items and Escape hands it back to +.
    const phone = await signIn(390, true);
    page = phone.page;
    await page.locator('.fab').click();
    await expect(page.locator('.fab-menu')).toBeVisible();
    expect((await focused(page)).text).toContain('新建 bot');
    await page.keyboard.press('ArrowDown');
    // "New group" is disabled with a single bot on this computer, so focus wraps.
    expect((await focused(page)).text).toContain('新建 bot');
    await page.keyboard.press('Escape');
    await expect(page.locator('.fab-menu')).toBeHidden();
    expect((await focused(page)).className).toContain('fab');
    await phone.context.close();
  } finally {
    await environment.close();
  }
});
