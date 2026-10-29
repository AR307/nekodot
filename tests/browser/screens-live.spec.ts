import { readFile } from 'node:fs/promises';
import { expect, test, type BrowserContext } from '@playwright/test';

// A private acceptance account paired to an isolated real Linux node, never a runtime fake switch.
const accessFile = process.env.NEKODOT_SCREEN_ACCEPTANCE_FILE;
test('real Linux screen: watch, two native viewers, handback, offline reconnect and responsive layout', async ({
  browser,
}) => {
  test.skip(
    !accessFile,
    'Requires an isolated real Linux screen and a local acceptance account file.',
  );
  test.setTimeout(180_000);
  const access = JSON.parse(await readFile(accessFile!, 'utf8')) as {
    token: string;
    nodeId: string;
    url: string;
    bots: { bot: { botId: string }; conversation: { conversationId: string } }[];
  };
  const contexts: BrowserContext[] = [];
  const errors: string[] = [];
  const open = async () => {
    const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
    contexts.push(context);
    await context.addInitScript((access) => {
      if (!location.protocol.startsWith('http')) return;
      localStorage.setItem('nekodot-token', access.token);
      localStorage.setItem('nekodot-language', 'en');
      localStorage.setItem('nekodot-node', access.nodeId);
      localStorage.setItem(
        'nekodot-conversation-' + access.nodeId,
        access.bots[0]!.conversation.conversationId,
      );
    }, access);
    const page = await context.newPage();
    page.on('pageerror', (error) => errors.push(error.message));
    await page.goto(access.url);
    await page
      .locator('.chat-header')
      .getByRole('button', { name: 'Bot screen', exact: true })
      .click();
    await expect(page.locator('.screen-control-bar')).toContainText(
      /Bot has control|Another viewer has control/,
      { timeout: 40_000 },
    );
    await expect(page.locator('.screen-viewport canvas')).toBeVisible();
    await expect(page.locator('.screen-keyboard textarea')).toBeDisabled();
    return { page, context };
  };
  try {
    const first = await open();
    await first.page.getByRole('button', { name: 'Take over', exact: true }).click();
    await expect(first.page.locator('.screen-control-bar')).toContainText('You have control');
    const second = await open();
    await second.page.getByRole('button', { name: 'Take over', exact: true }).click();
    await expect(second.page.locator('.screen-control-bar')).toContainText('You have control');
    await expect(first.page.locator('.screen-control-bar')).toContainText(
      'Another viewer has control',
    );
    await expect(first.page.locator('.screen-keyboard textarea')).toBeDisabled();
    await second.page.getByRole('button', { name: 'Hand back', exact: true }).click();
    await expect(first.page.locator('.screen-control-bar')).toContainText('Bot has control');
    await first.context.setOffline(true);
    await expect(first.page.getByRole('button', { name: 'Take over', exact: true })).toBeDisabled({
      timeout: 20_000,
    });
    await first.context.setOffline(false);
    await expect(first.page.getByRole('button', { name: 'Take over', exact: true })).toBeEnabled({
      timeout: 40_000,
    });
    await first.page.getByRole('button', { name: 'Take over', exact: true }).click();
    await expect(first.page.locator('.screen-control-bar')).toContainText('You have control');
    await first.context.setOffline(true);
    await expect(first.page.locator('.screen-keyboard textarea')).toBeDisabled();
    await first.context.setOffline(false);
    await expect(first.page.locator('.screen-control-bar')).toContainText('You have control', {
      timeout: 40_000,
    });
    // A dropped transport preserves the native lease, even when the document loses its viewer id.
    await first.context.setOffline(true);
    await expect(first.page.locator('.screen-keyboard textarea')).toBeDisabled();
    await first.page.goto('about:blank');
    await first.context.setOffline(false);
    await first.page.goto(access.url);
    await first.page
      .locator('.chat-header')
      .getByRole('button', { name: 'Bot screen', exact: true })
      .click();
    await expect(first.page.locator('.screen-control-bar')).toContainText(
      'Another viewer has control',
      { timeout: 40_000 },
    );
    await first.page.getByRole('button', { name: 'Force hand back', exact: true }).click();
    await expect(first.page.locator('.screen-control-bar')).toContainText('Bot has control');
    for (const width of [390, 768, 1440]) {
      await first.page.setViewportSize({ width, height: 900 });
      await expect(first.page.locator('.screen-panel')).toBeVisible();
      expect(
        await first.page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
      ).toBe(true);
      if (width === 1440)
        expect(
          Math.round(
            await first.page
              .locator('.screen-panel')
              .evaluate((el) => el.getBoundingClientRect().width),
          ),
        ).toBe(480);
    }
    await first.page.reload();
    await first.page
      .locator('.chat-header')
      .getByRole('button', { name: 'Bot screen', exact: true })
      .click();
    await expect(first.page.locator('.screen-control-bar')).toContainText('Bot has control', {
      timeout: 40_000,
    });
    await first.page.getByRole('button', { name: 'Take over', exact: true }).click();
    await expect(first.page.locator('.screen-control-bar')).toContainText('You have control');
    await first.page.locator('.screen-header').getByRole('button', { name: 'Close' }).click();
    await first.page
      .locator('.chat-header')
      .getByRole('button', { name: 'Bot screen', exact: true })
      .click();
    await expect(first.page.locator('.screen-control-bar')).toContainText('Bot has control', {
      timeout: 40_000,
    });
    await first.page.getByRole('button', { name: 'Stop screen', exact: true }).click();
    const start = first.page.getByRole('button', { name: 'Start screen', exact: true });
    await expect(start).toBeEnabled({ timeout: 40_000 });
    await start.click();
    await expect(first.page.locator('.screen-control-bar')).toContainText('Bot has control', {
      timeout: 60_000,
    });
    await expect(
      first.page.getByRole('button', { name: 'Stop screen', exact: true }),
    ).toBeEnabled();
    expect(errors).toEqual([]);
  } finally {
    for (const context of contexts) await context.close();
  }
});
