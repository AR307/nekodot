import { readFileSync } from 'node:fs';
import { mkdir, writeFile } from 'node:fs/promises';
import { expect, test } from '@playwright/test';
import { auditSurface, type Finding } from '../support/ergonomics';

/**
 * Live private chat with the real model behind the selected bot (criteria E2, E5, E6, E8).
 * Runs only with a private NEKODOT_LIVE_ACCEPTANCE_FILE; every run sends real prompts.
 * Measures what a person waits for: their own message, the first sign of work, the first
 * streamed words and the finished reply, and whether the view stays on the newest content.
 */
const file = process.env.NEKODOT_LIVE_ACCEPTANCE_FILE;
const live = file
  ? (JSON.parse(readFileSync(file, 'utf8')) as { url: string; token: string; nodeId: string })
  : undefined;

const variants = [
  {
    name: 'zh-desktop-light',
    width: 1440,
    height: 900,
    dark: false,
    touch: false,
    prompt: '用两三句话说说你能帮我做什么，再列出三个要点。',
  },
  {
    name: 'en-phone-dark',
    width: 390,
    height: 844,
    dark: true,
    touch: true,
    prompt: 'In two short sentences, what is a good way to plan a focused workday?',
  },
] as const;

for (const variant of variants) {
  test(`live chat ergonomics · ${variant.name}`, async ({ browser }) => {
    test.skip(!live, 'Set NEKODOT_LIVE_ACCEPTANCE_FILE to run against a real environment.');
    test.setTimeout(6 * 60_000);
    const shots = `.runtime/ergonomics/live-chat/${variant.name}`;
    await mkdir(shots, { recursive: true });
    const context = await browser.newContext({
      viewport: { width: variant.width, height: variant.height },
      hasTouch: variant.touch,
      isMobile: variant.touch,
    });
    const errors: string[] = [];
    try {
      await context.addInitScript(
        ({ token, nodeId, dark, lang }) => {
          localStorage.setItem('nekodot-token', token);
          localStorage.setItem('nekodot-node', nodeId);
          localStorage.setItem('nekodot-language', lang);
          localStorage.setItem('nekodot-theme', dark ? 'dark' : 'light');
        },
        {
          token: live!.token,
          nodeId: live!.nodeId,
          dark: variant.dark,
          lang: variant.name.startsWith('zh') ? 'zh' : 'en',
        },
      );
      const page = await context.newPage();
      page.on('pageerror', (error) => errors.push(error.message));
      await page.goto(live!.url);
      // Phones open on the team list; desktops show the list beside the conversation.
      await page.locator('.bot-row').first().waitFor({ state: 'visible', timeout: 30_000 });
      await page.locator('.bot-row').first().click();
      await expect(page.locator('.chat-title')).toBeVisible({ timeout: 30_000 });
      // E8: opening a conversation lands on its newest content even after late file cards load.
      await page.waitForTimeout(2_500);
      const openPinned = await page.evaluate(() => {
        const scroller = document.querySelector('.message-scroll')!;
        return Math.round(scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight);
      });
      await page.screenshot({ path: `${shots}/0-opened.png` });
      const composer = page.locator('.composer-wrap textarea').first();
      await composer.click();
      await composer.fill(variant.prompt);
      const before = await page.locator('.user-bubble').count();
      const assistantBefore = await page.locator('.message .bot-copy').count();

      // Timestamps are taken inside the page so they measure what the person sees.
      const timing = page.evaluate(
        ({ before, assistantBefore }) =>
          new Promise<Record<string, number>>((resolve) => {
            const start = performance.now();
            const marks: Record<string, number> = {};
            const check = () => {
              const now = performance.now() - start;
              if (!marks.ownMessage && document.querySelectorAll('.user-bubble').length > before)
                marks.ownMessage = now;
              if (
                !marks.working &&
                document.querySelector('.run-banner, .thinking-row, .chat-status .thinking-dots')
              )
                marks.working = now;
              const replies = document.querySelectorAll('.message .bot-copy');
              const latest = replies[replies.length - 1];
              if (
                !marks.firstWords &&
                replies.length > assistantBefore &&
                (latest?.textContent ?? '').trim().length > 0
              )
                marks.firstWords = now;
              if (
                marks.firstWords &&
                !document.querySelector('.stream-cursor') &&
                !document.querySelector('.run-banner')
              ) {
                marks.done = now;
                return resolve(marks);
              }
              if (now > 240_000) return resolve(marks);
              requestAnimationFrame(check);
            };
            requestAnimationFrame(check);
          }),
        { before, assistantBefore },
      );
      await composer.press('Enter');
      await page.waitForTimeout(400);
      await page.screenshot({ path: `${shots}/1-working.png` });
      await expect(page.locator('.stream-cursor').first())
        .toBeVisible({ timeout: 120_000 })
        .then(() => page.screenshot({ path: `${shots}/2-streaming.png` }))
        .catch(() => undefined);
      const marks = await timing;
      await page.waitForTimeout(600);
      await page.screenshot({ path: `${shots}/3-done.png` });
      const pinned = await page.evaluate(() => {
        const scroller = document.querySelector('.message-scroll')!;
        return Math.round(scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight);
      });
      const findings: Finding[] = await auditSurface(page, 'chat/after-reply');
      await writeFile(
        `.runtime/ergonomics/live-chat/${variant.name}.json`,
        JSON.stringify({ marks, openPinned, pinnedDistance: pinned, findings }, null, 2),
      );
      // E5: the person's own message shows at once and some sign of work follows quickly.
      expect(marks.ownMessage).toBeLessThan(400);
      expect(marks.working ?? marks.firstWords).toBeLessThan(1_500);
      expect(marks.done, 'reply finished').toBeTruthy();
      // E8: the newest content stays in view on open and after the reply completes.
      expect(openPinned).toBeLessThan(4);
      expect(pinned).toBeLessThan(4);
      expect(errors).toEqual([]);
    } finally {
      await context.close();
    }
  });
}
