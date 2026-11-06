import { readFileSync } from 'node:fs';
import { mkdir, writeFile } from 'node:fs/promises';
import { expect, test } from '@playwright/test';
import { auditDialog, auditSurface, type Finding } from '../support/ergonomics';

/**
 * Live group chat with real models (criteria E2, E4, E5, E10). Runs only with a private
 * NEKODOT_LIVE_ACCEPTANCE_FILE. Through the product UI it creates a second bot and a group
 * only when the computer has none, then sends one real group message and follows the relay.
 * Each run calls real models; created bots and groups stay on the node (archivable).
 */
const file = process.env.NEKODOT_LIVE_ACCEPTANCE_FILE;
const live = file
  ? (JSON.parse(readFileSync(file, 'utf8')) as { url: string; token: string; nodeId: string })
  : undefined;
const model = process.env.NEKODOT_LIVE_MODEL ?? 'gpt-6-sol';

test('live group chat ergonomics · zh-desktop-light', async ({ browser }) => {
  test.skip(!live, 'Set NEKODOT_LIVE_ACCEPTANCE_FILE to run against a real environment.');
  test.setTimeout(10 * 60_000);
  const shots = '.runtime/ergonomics/live-group';
  await mkdir(shots, { recursive: true });
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const errors: string[] = [];
  const findings: Finding[] = [];
  try {
    await context.addInitScript(
      ({ token, nodeId }) => {
        localStorage.setItem('nekodot-token', token);
        localStorage.setItem('nekodot-node', nodeId);
        localStorage.setItem('nekodot-language', 'zh');
        localStorage.setItem('nekodot-theme', 'light');
      },
      { token: live!.token, nodeId: live!.nodeId },
    );
    const page = await context.newPage();
    page.on('pageerror', (error) => errors.push(error.message));
    await page.goto(live!.url);
    const bots = page.locator('.bot-row:not(.group-row)');
    await bots.first().waitFor({ state: 'visible', timeout: 30_000 });

    if ((await bots.count()) < 2) {
      // E10: with one bot the group entry explains what is missing.
      await expect(page.locator('#group-unavailable')).toContainText('至少需要 2 个 bot');
      await page.screenshot({ path: `${shots}/0-needs-bots.png` });
      await page.getByRole('button', { name: '新建 bot', exact: true }).first().click();
      const sheet = page.locator('.sheet');
      await expect(sheet).toBeVisible();
      await sheet.getByLabel('名字').fill('小核');
      await sheet.getByLabel('它负责什么？').fill('负责核对事实与数据来源，回答简短直接。');
      const source = sheet.getByLabel('模型来源', { exact: true });
      const options = await source.locator('option:not([disabled])').allTextContents();
      const chosen = options.find((label) => /chatgpt|codex|openai/i.test(label)) ?? options[0]!;
      await source.selectOption({ label: chosen });
      await sheet.getByLabel('模型', { exact: true }).fill(model);
      await page.screenshot({ path: `${shots}/1-new-bot.png` });
      await sheet.locator('footer').getByRole('button', { name: /^创建/ }).click();
      await expect(sheet).toBeHidden({ timeout: 60_000 });
      await expect(bots).toHaveCount(2, { timeout: 60_000 });
    }

    if (!(await page.locator('.group-row').count())) {
      const trigger = page.getByRole('button', { name: '新建群组', exact: true }).first();
      await expect(trigger).toBeEnabled();
      findings.push(
        ...(await auditDialog(page, 'groups/new-group', trigger, page.locator('.sheet'), () =>
          page.keyboard.press('Enter'),
        )),
      );
      await trigger.click();
      const sheet = page.locator('.sheet');
      await expect(sheet).toBeVisible();
      await page.waitForTimeout(500);
      findings.push(...(await auditSurface(page, 'groups/new-group')));
      await sheet.getByLabel('群组名称', { exact: true }).fill('核对小组');
      for (const box of await sheet.locator('.member-option input[type="checkbox"]').all())
        if (!(await box.isChecked())) await box.check();
      await page.screenshot({ path: `${shots}/2-new-group.png` });
      await sheet.locator('footer').getByRole('button').last().click();
      await expect(sheet).toBeHidden({ timeout: 30_000 });
    }

    await page.locator('.group-row').first().click();
    await expect(page.locator('.chat-title')).toBeVisible();
    await page.waitForTimeout(1_500);
    findings.push(...(await auditSurface(page, 'groups/chat')));
    const composer = page.locator('.composer-wrap textarea').first();
    await composer.click();
    await composer.fill('请用一句话说说怎样安排专注的一天，然后交给另一位成员补充一句。');
    const before = {
      users: await page.locator('.user-bubble').count(),
      handoffs: await page.locator('.handoff-tag').count(),
      replies: await page.locator('.message .bot-copy').count(),
    };
    const timing = page.evaluate(
      (before) =>
        new Promise<Record<string, number>>((resolve) => {
          const start = performance.now();
          const marks: Record<string, number> = {};
          let quietSince = 0;
          const check = () => {
            const now = performance.now() - start;
            if (
              !marks.ownMessage &&
              document.querySelectorAll('.user-bubble').length > before.users
            )
              marks.ownMessage = now;
            const busy = document.querySelector('.run-banner, .stream-cursor, .thinking-row');
            if (!marks.working && busy) marks.working = now;
            if (
              !marks.handoff &&
              document.querySelectorAll('.handoff-tag').length > before.handoffs
            )
              marks.handoff = now;
            if (marks.working && !busy) {
              quietSince ||= now;
              // The relay may pause between members; settle after 6s without activity.
              if (now - quietSince > 6_000) {
                marks.done = quietSince;
                return resolve(marks);
              }
            } else quietSince = 0;
            if (now > 420_000) return resolve(marks);
            requestAnimationFrame(check);
          };
          requestAnimationFrame(check);
        }),
      before,
    );
    await composer.press('Enter');
    await page.waitForTimeout(500);
    await page.screenshot({ path: `${shots}/3-working.png` });
    await page
      .locator('.handoff-tag')
      .nth(before.handoffs)
      .waitFor({ timeout: 180_000 })
      .then(() => page.screenshot({ path: `${shots}/4-relay.png` }))
      .catch(() => undefined);
    const marks = await timing;
    const newReplies = (await page.locator('.message .bot-copy').count()) - before.replies;
    await page.screenshot({ path: `${shots}/5-done.png` });
    const pinned = await page.evaluate(() => {
      const scroller = document.querySelector('.message-scroll')!;
      return Math.round(scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight);
    });
    findings.push(...(await auditSurface(page, 'groups/chat-after-relay')));
    await writeFile(
      `${shots}/report.json`,
      JSON.stringify({ marks, newReplies, pinnedDistance: pinned, findings }, null, 2),
    );
    expect(marks.ownMessage).toBeLessThan(400);
    expect(marks.working).toBeLessThan(1_500);
    expect(marks.handoff, 'this round displayed a new handoff').toBeGreaterThanOrEqual(
      marks.ownMessage!,
    );
    expect(newReplies, 'both members replied in this round').toBeGreaterThanOrEqual(2);
    expect(marks.done, 'group round finished').toBeTruthy();
    expect(pinned).toBeLessThan(4);
    expect(findings.filter((item) => item.severity === 'P0' || item.severity === 'P1')).toEqual([]);
    expect(errors).toEqual([]);
  } finally {
    await context.close();
  }
});
