import { expect, type Page } from '@playwright/test';
import { auditDialog, auditReducedMotion, auditSurface, type Finding } from './ergonomics';

/**
 * Walks every signed-in web surface the way a person reaches it (pointer, keyboard, touch)
 * and audits each one. Shared by the recorded probe and the live acceptance run so both
 * cover the same route. Each surface starts from a fresh home load.
 */
export async function walkSurfaces(
  page: Page,
  options: { url: string; touch: boolean; shots?: string },
): Promise<Finding[]> {
  const findings: Finding[] = [];
  // A covered or inert control must fail its surface quickly instead of stalling the walk.
  page.setDefaultTimeout(15_000);
  // The app reopens the last conversation on load (on phones that hides the list), so every
  // surface starts from the team list, as a person returning to the app home would.
  await page.addInitScript(() => {
    for (const key of Object.keys(localStorage))
      if (key.startsWith('nekodot-conversation-')) localStorage.removeItem(key);
  });
  const shot = async (name: string) => {
    if (options.shots) await page.screenshot({ path: `${options.shots}/${name}.png` });
  };
  const home = async () => {
    await page.goto(options.url);
    await expect(page.locator('.bot-row').first()).toBeVisible({ timeout: 30_000 });
    await page.waitForTimeout(500);
  };
  const step = async (surface: string, run: () => Promise<void>) => {
    try {
      await home();
      await run();
    } catch (error) {
      findings.push({
        surface,
        rule: 'probe',
        severity: 'P3',
        detail: 'probe could not reach surface: ' + String(error).split('\n')[0],
      });
      await shot(surface.replace('/', '-') + '-unreached').catch(() => undefined);
    }
  };
  const settle = (ms = 450) => page.waitForTimeout(ms);
  const dialogStep = async (
    surface: string,
    trigger: ReturnType<Page['locator']>,
    dialog: ReturnType<Page['locator']>,
  ) => {
    findings.push(
      ...(await auditDialog(page, surface, trigger, dialog, () => page.keyboard.press('Enter'))),
    );
    // If Escape failed to close it (already a finding), audit the dialog that is still open.
    if (!(await dialog.isVisible())) await trigger.click();
    await expect(dialog).toBeVisible();
    await settle();
    findings.push(...(await auditSurface(page, surface)));
    await shot(surface.replace('/', '-'));
  };

  await step('shell/home', async () => {
    findings.push(...(await auditSurface(page, 'shell/home')));
    await shot('shell-home');
    findings.push(...(await auditReducedMotion(page, 'shell/home')));
  });
  await step('shell/palette', async () => {
    const trigger = options.touch
      ? page.getByRole('button', { name: /^(搜索|Search)$/ }).first()
      : page.locator('.search-trigger').first();
    await dialogStep('shell/palette', trigger, page.locator('.palette'));
  });
  await step('shell/node-menu', async () => {
    await page.locator('.node-picker').first().click();
    await expect(page.locator('.node-menu')).toBeVisible();
    await settle();
    findings.push(...(await auditSurface(page, 'shell/node-menu')));
    await shot('shell-node-menu');
  });
  if (options.touch)
    await step('shell/new-menu', async () => {
      await page.locator('.fab').first().click();
      await settle();
      findings.push(...(await auditSurface(page, 'shell/new-menu')));
      await shot('shell-new-menu');
    });
  for (const [surface, name, index] of [
    ['bots/new-bot', /^(新建 bot|New bot)$/, 0],
    ['groups/new-group', /^(新建群组|New group)$/, 1],
  ] as const)
    await step(surface, async () => {
      if (options.touch) {
        await page.locator('.fab').first().click();
        await page.getByRole('menuitem').nth(index).click();
        await expect(page.locator('.sheet')).toBeVisible();
        await settle();
        findings.push(...(await auditSurface(page, surface)));
        await shot(surface.replace('/', '-'));
      } else
        await dialogStep(
          surface,
          page.getByRole('button', { name }).first(),
          page.locator('.sheet'),
        );
    });
  await step('chat/private', async () => {
    await page.locator('.bot-row').first().click();
    await expect(page.locator('.chat-title')).toBeVisible();
    await settle(600);
    findings.push(...(await auditSurface(page, 'chat/private')));
    await shot('chat-private');
    findings.push(...(await auditReducedMotion(page, 'chat/private')));
    await page.locator('textarea').first().focus();
    await settle();
    findings.push(...(await auditSurface(page, 'chat/composer')));
    await shot('chat-composer');
  });
  await step('bots/details', async () => {
    await page.locator('.bot-row').first().click();
    const dialog = page.locator('[role="dialog"]').filter({ has: page.locator('.details-tabs') });
    await dialogStep('bots/details', page.locator('.chat-title'), dialog);
    for (const [tab, key] of [
      [/^(记忆|Memory)$/, 'memory'],
      [/^(资料库|Library)$/, 'library'],
    ] as const) {
      await page.locator('.details-tabs').getByRole('button', { name: tab }).click();
      await settle(700);
      findings.push(...(await auditSurface(page, `bots/details-${key}`)));
      await shot(`bots-details-${key}`);
    }
  });
  for (const [kind, name] of [
    ['skills', /^Skills$/],
    ['plugins', /^(插件|Plugins)$/],
  ] as const)
    await step(`extensions/${kind}`, async () => {
      await page.getByRole('button', { name }).first().click();
      await expect(page.locator('.extension-card').first()).toBeVisible({ timeout: 30_000 });
      await settle(700);
      findings.push(...(await auditSurface(page, `extensions/${kind}`)));
      await shot(`extensions-${kind}`);
      await dialogStep(
        `extensions/${kind}-detail`,
        page.locator('.extension-card').first(),
        page.locator('.extension-detail'),
      );
    });
  await step('settings', async () => {
    await page
      .getByRole('button', { name: /^(设置|Settings)$/ })
      .first()
      .click();
    await settle(800);
    findings.push(...(await auditSurface(page, 'settings')));
    await shot('settings');
    findings.push(...(await auditReducedMotion(page, 'settings')));
  });
  await step('pair', async () => {
    await page.locator('.node-picker').first().click();
    await page.locator('.node-menu-add').click();
    await settle(800);
    findings.push(...(await auditSurface(page, 'pair')));
    await shot('pair');
  });
  return findings;
}
