import AxeBuilder from '@axe-core/playwright';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import type { Locator, Page } from '@playwright/test';

/**
 * Ergonomic probe for the web UI. Each check maps to a criterion in
 * docs/superpowers/specs/2026-11-05-ui-ergonomics-motion-design.md (E1–E11).
 * Checks return findings instead of asserting so one run can list every problem;
 * specs gate on the severities they require.
 */
export type Severity = 'P0' | 'P1' | 'P2' | 'P3';
export interface Finding {
  surface: string;
  rule: string;
  severity: Severity;
  detail: string;
  target?: string;
}

/**
 * Motion token durations in ms (styles/tokens.css), plus 9600 = 16 × sway for the working
 * avatar's petals so they stay in phase with the ears.
 */
export const motionTokens = [
  80, 160, 220, 280, 450, 600, 1000, 1200, 1400, 1600, 2000, 9600, 20000,
];
export const minimumTarget = 44;

/** Installs layout-shift and long-animation-frame collectors before any page script runs. */
export async function observeRendering(page: Page) {
  await page.addInitScript(() => {
    const state = { cls: 0, longFrames: [] as number[] };
    (window as unknown as { __ergonomics: typeof state }).__ergonomics = state;
    try {
      new PerformanceObserver((list) => {
        for (const entry of list.getEntries() as (PerformanceEntry & {
          value: number;
          hadRecentInput: boolean;
        })[])
          if (!entry.hadRecentInput) state.cls += entry.value;
      }).observe({ type: 'layout-shift', buffered: true });
      new PerformanceObserver((list) => {
        for (const entry of list.getEntries())
          if (entry.duration > 200) state.longFrames.push(Math.round(entry.duration));
      }).observe({ type: 'long-animation-frame', buffered: true });
    } catch {
      // Observers are diagnostic only; a browser without them reports zero.
    }
  });
}

export async function renderingFindings(page: Page, surface: string): Promise<Finding[]> {
  const state = await page.evaluate(
    () =>
      (window as unknown as { __ergonomics?: { cls: number; longFrames: number[] } })
        .__ergonomics ?? { cls: 0, longFrames: [] },
  );
  const findings: Finding[] = [];
  if (state.cls >= 0.1)
    findings.push({
      surface,
      rule: 'E6 layout shift',
      severity: 'P2',
      detail: `CLS ${state.cls.toFixed(3)} ≥ 0.1`,
    });
  if (state.longFrames.length)
    findings.push({
      surface,
      rule: 'E6 long animation frame',
      severity: 'P3',
      detail: `${state.longFrames.length} frames > 200ms (max ${Math.max(...state.longFrames)}ms)`,
    });
  return findings;
}

/** Static checks of whatever is currently rendered: axe, targets, type size, overflow, motion tokens. */
export async function auditSurface(
  page: Page,
  surface: string,
  options: { exclude?: string[]; touch?: boolean } = {},
): Promise<Finding[]> {
  const findings: Finding[] = [];
  // Measure the settled UI: entrance animations (list pop-in, sheets) finish first. Reveals can
  // start a moment later (intersection observers), so settle in a few rounds.
  await page.evaluate(async () => {
    for (let round = 0; round < 4; round++) {
      const running = document
        .getAnimations()
        .filter((animation) => animation.effect?.getComputedTiming().iterations !== Infinity);
      if (!running.length && round > 0) return;
      await Promise.race([
        Promise.all(running.map((animation) => animation.finished.catch(() => undefined))),
        new Promise((resolve) => setTimeout(resolve, 2_000)),
      ]);
      await new Promise((resolve) => setTimeout(resolve, 150));
    }
  });
  let axe = new AxeBuilder({ page }).withTags([
    'wcag2a',
    'wcag2aa',
    'wcag21a',
    'wcag21aa',
    'wcag22aa',
  ]);
  for (const selector of options.exclude ?? []) axe = axe.exclude(selector);
  const result = await axe.analyze();
  // axe cannot see the Gooey Nav pill (a filtered pseudo-element behind the selected label)
  // and compares the label with the track instead. Measure label against the pill directly.
  const pillContrast = await page.evaluate(() => {
    const parse = (value: string) =>
      value
        .match(/[\d.]+/g)!
        .slice(0, 3)
        .map(Number);
    const luminance = (rgb: number[]) => {
      const [r, g, b] = rgb.map((v) => {
        const c = v / 255;
        return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
      });
      return 0.2126 * r! + 0.7152 * g! + 0.0722 * b!;
    };
    const ratios: Record<string, number> = {};
    for (const nav of document.querySelectorAll<HTMLElement>('.gooey-nav[data-ready="true"]')) {
      const label = nav.querySelector('[aria-current="page"]');
      const effect = nav.querySelector('.gooey-nav__effect');
      if (!label || !effect) continue;
      const fg = luminance(parse(getComputedStyle(label).color));
      const bg = luminance(parse(getComputedStyle(effect, '::after').backgroundColor));
      ratios[nav.getAttribute('aria-label') ?? ''] =
        (Math.max(fg, bg) + 0.05) / (Math.min(fg, bg) + 0.05);
    }
    return ratios;
  });
  const onPill = (target: string) =>
    /aria-current="page"/.test(target) &&
    Object.values(pillContrast).every((ratio) => ratio >= 4.5);
  for (const violation of result.violations)
    for (const node of violation.nodes) {
      if (violation.id === 'color-contrast' && onPill(node.target.join(' '))) continue;
      findings.push({
        surface,
        rule: `axe ${violation.id}`,
        severity:
          violation.impact === 'critical' || violation.impact === 'serious'
            ? 'P1'
            : violation.impact === 'moderate'
              ? 'P2'
              : 'P3',
        // Contrast failures carry the measured ratio and colours; keep them for triage.
        detail: (violation.id === 'color-contrast' && node.any[0]?.message) || violation.help,
        target: node.target.join(' '),
      });
    }
  const measured = await page.evaluate(
    ({ minimumTarget, motionTokens }) => {
      const out: { rule: string; severity: string; detail: string; target: string }[] = [];
      const describe = (element: Element) => {
        const label =
          element.getAttribute('aria-label') ??
          element.getAttribute('title') ??
          (element.textContent ?? '').trim().replace(/\s+/g, ' ').slice(0, 40);
        const classes = [...element.classList].slice(0, 2).join('.');
        return `${element.tagName.toLowerCase()}${classes ? '.' + classes : ''} "${label}"`;
      };
      const hidden = (element: Element) => {
        if (element.closest('[aria-hidden="true"], [inert]')) return true;
        // Content of a closed <details> is not rendered (content-visibility), only its summary.
        const details = element.closest('details:not([open])');
        if (details && !element.closest('summary')) return true;
        if (!element.checkVisibility({ visibilityProperty: true, opacityProperty: true }))
          return true;
        const style = getComputedStyle(element);
        if (style.visibility === 'hidden' || style.display === 'none') return true;
        const box = element.getBoundingClientRect();
        return box.width === 0 && box.height === 0;
      };
      const interactive = document.querySelectorAll(
        'button, a[href], input:not([type="hidden"]), select, textarea, summary, [role="button"], [role="tab"], [role="menuitem"], [role="option"], [role="switch"], [role="checkbox"], [tabindex]:not([tabindex="-1"])',
      );
      const seen = new Set<string>();
      for (const element of interactive) {
        if (hidden(element)) continue;
        // Inline text links follow the surrounding text size (WCAG 2.5.8 inline exception).
        if (element.tagName === 'A' && getComputedStyle(element).display === 'inline') continue;
        if (element.closest('.markdown, .message-text')) continue;
        let box = element.getBoundingClientRect();
        if (element instanceof HTMLInputElement && /checkbox|radio/.test(element.type)) {
          const label = element.closest('label');
          if (label) box = label.getBoundingClientRect();
        }
        // A nested control inside a larger clickable row/label is reachable through it.
        const host = element.parentElement?.closest('label, [role="option"], button');
        if (host && host !== element) {
          const outer = host.getBoundingClientRect();
          if (outer.width >= minimumTarget && outer.height >= minimumTarget) continue;
        }
        if (box.width + 0.5 < minimumTarget || box.height + 0.5 < minimumTarget) {
          const key = describe(element) + Math.round(box.width) + 'x' + Math.round(box.height);
          if (seen.has(key)) continue;
          seen.add(key);
          // Accepted exception (WCAG 2.5.8 "equivalent"): a pointer splitter whose value
          // is also adjustable from the keyboard. Still reported so it stays visible.
          const splitter =
            element.getAttribute('role') === 'separator' && element.hasAttribute('aria-valuenow');
          out.push({
            rule: 'E1 target size',
            severity: splitter ? 'P3' : Math.min(box.width, box.height) < 24 ? 'P1' : 'P2',
            detail:
              `${Math.round(box.width)}×${Math.round(box.height)} < ${minimumTarget}` +
              (splitter ? ' (accepted: keyboard-adjustable separator)' : ''),
            target: describe(element),
          });
        }
      }
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      const small = new Map<string, number>();
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        if (!node.textContent?.trim()) continue;
        const parent = node.parentElement;
        if (!parent || hidden(parent)) continue;
        const size = parseFloat(getComputedStyle(parent).fontSize);
        if (size < 12) small.set(describe(parent), size);
      }
      for (const [target, size] of small)
        out.push({ rule: 'E3 type size', severity: 'P2', detail: `${size}px < 12px`, target });
      if (document.documentElement.scrollWidth > innerWidth + 1)
        out.push({
          rule: 'E8 horizontal overflow',
          severity: 'P1',
          detail: `scrollWidth ${document.documentElement.scrollWidth} > ${innerWidth}`,
          target: 'document',
        });
      const toMs = (value: string) =>
        value.endsWith('ms') ? parseFloat(value) : parseFloat(value) * 1000;
      const offTokens = new Map<string, Set<string>>();
      for (const element of document.querySelectorAll('*')) {
        // Gooey Nav particles jitter around 2 × sway on purpose (organic burst); accepted.
        if (element.matches('.gooey-nav__particle, .gooey-nav__point')) continue;
        const style = getComputedStyle(element);
        const values = [
          ...style.transitionDuration.split(','),
          ...(style.animationName !== 'none' ? style.animationDuration.split(',') : []),
        ];
        for (const raw of values) {
          const ms = Math.round(toMs(raw.trim()));
          if (!ms || motionTokens.some((token) => Math.abs(token - ms) <= 1)) continue;
          const key = `${ms}ms`;
          const targets = offTokens.get(key) ?? new Set<string>();
          if (targets.size < 3) targets.add(describe(element));
          offTokens.set(key, targets);
        }
      }
      for (const [duration, targets] of offTokens)
        out.push({
          rule: 'E6 non-token duration',
          severity: 'P3',
          detail: duration,
          target: [...targets].join(' | '),
        });
      return out;
    },
    { minimumTarget, motionTokens },
  );
  for (const item of measured)
    findings.push({ surface, ...item, severity: item.severity as Severity });
  return findings;
}

/** E7: with reduced motion, nothing loops and nothing lasts longer than the instant token. */
export async function auditReducedMotion(page: Page, surface: string): Promise<Finding[]> {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.waitForTimeout(400);
  const result = await page.evaluate(() => {
    const out: { detail: string; target: string }[] = [];
    for (const animation of document.getAnimations()) {
      const timing = animation.effect?.getComputedTiming();
      if (!timing || animation.playState !== 'running') continue;
      const target =
        animation.effect instanceof KeyframeEffect && animation.effect.target
          ? animation.effect.target.tagName.toLowerCase() +
            '.' +
            [...animation.effect.target.classList].slice(0, 2).join('.')
          : 'unknown';
      if (timing.iterations === Infinity) out.push({ detail: 'infinite animation', target });
      else if (typeof timing.duration === 'number' && timing.duration > 81)
        out.push({ detail: `${Math.round(timing.duration)}ms animation`, target });
    }
    return out;
  });
  await page.emulateMedia({ reducedMotion: 'no-preference' });
  return result.map((item) => ({
    surface,
    rule: 'E7 reduced motion',
    severity: item.detail.startsWith('infinite') ? 'P1' : 'P2',
    ...item,
  }));
}

/**
 * E4: a modal keeps focus inside while open, closes on Escape and returns focus to its trigger.
 * `open` must activate `trigger` by keyboard or pointer.
 */
export async function auditDialog(
  page: Page,
  surface: string,
  trigger: Locator,
  dialog: Locator,
  open: () => Promise<void>,
): Promise<Finding[]> {
  const findings: Finding[] = [];
  const fail = (detail: string, severity: Severity = 'P1') =>
    findings.push({ surface, rule: 'E4 dialog focus', severity, detail });
  await trigger.focus();
  await open();
  await dialog.waitFor({ state: 'visible' });
  await page.waitForTimeout(350);
  const inside = () => dialog.evaluate((element) => element.contains(document.activeElement));
  if (!(await inside())) fail('initial focus is outside the dialog');
  let escaped = false;
  for (let i = 0; i < 24 && !escaped; i++) {
    await page.keyboard.press(i % 6 === 5 ? 'Shift+Tab' : 'Tab');
    if (!(await inside())) escaped = true;
  }
  if (escaped) fail('Tab moves focus out of the open dialog');
  const backgroundInert = await dialog.evaluate((element) => {
    const root = document.getElementById('root');
    if (!root || root.contains(element)) return false;
    return root.inert || root.getAttribute('aria-hidden') === 'true';
  });
  if (!backgroundInert) fail('background is not inert while the dialog is open', 'P2');
  await page.keyboard.press('Escape');
  const closed = await dialog
    .waitFor({ state: 'hidden', timeout: 2_000 })
    .then(() => true)
    .catch(() => false);
  if (!closed) {
    fail('Escape does not close the dialog');
    return findings;
  }
  await page.waitForTimeout(100);
  const returned = await trigger.evaluate((element) => element === document.activeElement);
  if (!returned) fail('focus does not return to the trigger after closing', 'P2');
  return findings;
}

export async function writeReport(path: string, findings: Finding[]) {
  await mkdir(dirname(path), { recursive: true });
  const order: Record<Severity, number> = { P0: 0, P1: 1, P2: 2, P3: 3 };
  const sorted = [...findings].sort(
    (a, b) => order[a.severity] - order[b.severity] || a.surface.localeCompare(b.surface),
  );
  await writeFile(path, JSON.stringify(sorted, null, 2));
  return sorted;
}

export function blocking(findings: Finding[]) {
  return findings.filter((finding) => finding.severity === 'P0' || finding.severity === 'P1');
}
