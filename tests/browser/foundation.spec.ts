import { expect, test } from '@playwright/test';
test('the account screen works at desktop, tablet, and phone sizes in both languages', async ({
  page,
}) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { name: '创建账号' })).toBeVisible();
  await page.getByRole('button', { name: 'English', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Create account' })).toBeVisible();
  await page.getByRole('button', { name: 'Already have an account? Sign in' }).click();
  await expect(page.getByRole('heading', { name: 'Sign in', exact: true })).toBeVisible();
  await page.getByRole('button', { name: '中文', exact: true }).click();
  await expect(page.getByRole('heading', { name: '登录', exact: true })).toBeVisible();
  for (const width of [1440, 768, 390]) {
    await page.setViewportSize({ width, height: 900 });
    await expect(page.getByLabel('邮箱')).toBeVisible();
    await expect(page.getByRole('button', { name: '继续', exact: true })).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
      true,
    );
    await page.screenshot({ path: `docs/evidence/phase1-account-${width}.png`, fullPage: true });
  }
});
