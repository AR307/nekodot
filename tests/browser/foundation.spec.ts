import { expect, test } from '@playwright/test';
test('open the foundation page on desktop and mobile and switch language', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('link', { name: 'nekodot' })).toBeVisible();
  await expect(page.locator('article')).toHaveCount(3);
  await page.getByRole('button').click();
  await expect(page.locator('main')).toHaveAttribute('lang', 'zh');
  await expect(page.getByRole('heading', { level: 1 })).toContainText('AI');
  await page.screenshot({ path: 'docs/evidence/foundation-desktop.png', fullPage: true });
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(page.locator('article').last()).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page.screenshot({ path: 'docs/evidence/foundation-mobile.png', fullPage: true });
});
