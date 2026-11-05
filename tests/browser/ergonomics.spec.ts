import { expect, test } from '@playwright/test';
import { userMemoryEnvironment } from '../support/user-memory-environment';
import {
  auditSurface,
  blocking,
  observeRendering,
  renderingFindings,
  writeReport,
  type Finding,
} from '../support/ergonomics';
import { walkSurfaces } from '../support/ergonomics-walk';

/**
 * Ergonomic probe over every web surface reachable with recorded management data
 * (criteria E1–E11, docs/superpowers/specs/2026-11-05-ui-ergonomics-motion-design.md).
 * Recorded replay supplements, and never replaces, the live acceptance run.
 * Surfaces listed in GATED must have no P0/P1 findings; the list grows with each wave.
 */
const GATED: string[] = ['auth', 'pair'];

export const variants = [
  { name: 'desktop-light', width: 1440, height: 900, dark: false, touch: false },
  { name: 'desktop-dark', width: 1440, height: 900, dark: true, touch: false },
  { name: 'phone-light', width: 390, height: 844, dark: false, touch: true },
  { name: 'phone-dark', width: 390, height: 844, dark: true, touch: true },
] as const;

for (const variant of variants) {
  test(`ergonomic probe · ${variant.name}`, async ({ browser }) => {
    test.setTimeout(8 * 60_000);
    const environment = await userMemoryEnvironment();
    const findings: Finding[] = [];
    const errors: string[] = [];
    const context = await browser.newContext({
      viewport: { width: variant.width, height: variant.height },
      hasTouch: variant.touch,
      isMobile: variant.touch,
      locale: 'zh-CN',
    });
    try {
      await context.addInitScript((dark) => {
        localStorage.setItem('nekodot-language', 'zh');
        localStorage.setItem('nekodot-theme', dark ? 'dark' : 'light');
      }, variant.dark);
      const anonymous = await context.newPage();
      await anonymous.goto(environment.url);
      await expect(anonymous.locator('form').first()).toBeVisible();
      await anonymous.waitForTimeout(500);
      findings.push(...(await auditSurface(anonymous, 'auth/login')));
      await anonymous.close();

      const page = await context.newPage();
      page.on('pageerror', (error) => errors.push(error.message));
      await observeRendering(page);
      await page.addInitScript(
        ({ token, nodeId }) => {
          localStorage.setItem('nekodot-token', token);
          localStorage.setItem('nekodot-node', nodeId);
        },
        {
          token: environment.accounts[0]!.token,
          nodeId: environment.nodes[0]!.credentials.nodeId,
        },
      );
      findings.push(...(await walkSurfaces(page, { url: environment.url, touch: variant.touch })));
      findings.push(...(await renderingFindings(page, 'session')));
    } finally {
      await context.close();
      await environment.close();
    }
    const report = await writeReport(`.runtime/ergonomics/probe-${variant.name}.json`, findings);
    expect(errors).toEqual([]);
    const gated = blocking(report).filter((finding) =>
      GATED.some(
        (surface) => finding.surface === surface || finding.surface.startsWith(surface + '/'),
      ),
    );
    expect(gated).toEqual([]);
  });
}
