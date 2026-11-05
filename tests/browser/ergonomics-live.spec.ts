import { readFileSync } from 'node:fs';
import { mkdir } from 'node:fs/promises';
import { expect, test } from '@playwright/test';
import {
  auditSurface,
  observeRendering,
  renderingFindings,
  writeReport,
  type Finding,
} from '../support/ergonomics';
import { walkSurfaces } from '../support/ergonomics-walk';

/**
 * Live ergonomic acceptance: the candidate web connected to a real Relay, Node and official
 * Hermes. Runs only when NEKODOT_LIVE_ACCEPTANCE_FILE points to a private local file with
 * `url`, `token` and `nodeId`; the file must never be committed. Reports and screenshots go
 * to the ignored .runtime/ergonomics/live directory.
 */
const file = process.env.NEKODOT_LIVE_ACCEPTANCE_FILE;
const live = file
  ? (JSON.parse(readFileSync(file, 'utf8')) as { url: string; token: string; nodeId: string })
  : undefined;

const variants = [
  { name: 'zh-desktop-light', width: 1440, height: 900, dark: false, touch: false, lang: 'zh' },
  { name: 'zh-phone-dark', width: 390, height: 844, dark: true, touch: true, lang: 'zh' },
  { name: 'en-desktop-dark', width: 1440, height: 900, dark: true, touch: false, lang: 'en' },
  { name: 'en-phone-light', width: 390, height: 844, dark: false, touch: true, lang: 'en' },
  { name: 'zh-tablet-light', width: 768, height: 1024, dark: false, touch: true, lang: 'zh' },
  { name: 'zh-narrow-light', width: 320, height: 640, dark: false, touch: true, lang: 'zh' },
] as const;

for (const variant of variants) {
  test(`live ergonomic acceptance · ${variant.name}`, async ({ browser }) => {
    test.skip(!live, 'Set NEKODOT_LIVE_ACCEPTANCE_FILE to run against a real environment.');
    test.setTimeout(10 * 60_000);
    const shots = `.runtime/ergonomics/live/${variant.name}`;
    await mkdir(shots, { recursive: true });
    const findings: Finding[] = [];
    const errors: string[] = [];
    const context = await browser.newContext({
      viewport: { width: variant.width, height: variant.height },
      hasTouch: variant.touch,
      isMobile: variant.touch,
    });
    try {
      await context.addInitScript(
        ({ dark, lang }) => {
          localStorage.setItem('nekodot-language', lang);
          localStorage.setItem('nekodot-theme', dark ? 'dark' : 'light');
        },
        { dark: variant.dark, lang: variant.lang },
      );
      const anonymous = await context.newPage();
      await anonymous.goto(live!.url);
      await expect(anonymous.locator('form').first()).toBeVisible();
      await anonymous.waitForTimeout(600);
      findings.push(...(await auditSurface(anonymous, 'auth/login')));
      await anonymous.screenshot({ path: `${shots}/auth-login.png` });
      await anonymous.close();

      const page = await context.newPage();
      page.on('pageerror', (error) => errors.push(error.message));
      await observeRendering(page);
      await page.addInitScript(
        ({ token, nodeId }) => {
          localStorage.setItem('nekodot-token', token);
          localStorage.setItem('nekodot-node', nodeId);
        },
        { token: live!.token, nodeId: live!.nodeId },
      );
      findings.push(...(await walkSurfaces(page, { url: live!.url, touch: variant.touch, shots })));
      findings.push(...(await renderingFindings(page, 'session')));
    } finally {
      await context.close();
    }
    await writeReport(`.runtime/ergonomics/live/${variant.name}.json`, findings);
    expect(errors).toEqual([]);
  });
}
