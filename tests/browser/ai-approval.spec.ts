import { expect, test } from '@playwright/test';

test.beforeEach(async ({ page }) => {
  // Vite transforms the real component and its dependencies; only the app entry
  // is replaced so submission timing can be controlled without faking Hermes.
  await page.route(
    (url) => url.pathname === '/src/main.tsx',
    (route) => {
      return route.fulfill({
        contentType: 'text/javascript',
        body: `
        import React from '/node_modules/.vite/deps/react.js';
        import ReactDOM from '/node_modules/.vite/deps/react-dom_client.js';
        import AIApproval from '/src/components/ui/ai-approval.tsx';
        import '/src/styles/tokens.css';
        import '/src/style.css';
        const root = ReactDOM.createRoot(document.getElementById('root'));
        window.calls = 0;
        window.renderApproval = (props = {}) => root.render(React.createElement(AIApproval, {
          question: 'Run the protected operation?',
          options: [
            { id: 'once', label: 'Allow once', resultLabel: 'Allowed once', detail: 'Only this operation' },
            { id: 'deny', label: 'Deny', destructive: true },
          ],
          onDecide: () => {
            window.calls++;
            return new Promise((resolve, reject) => { window.finish = resolve; window.fail = reject; });
          },
          ...props,
        }));
        window.renderApproval();
      `,
      });
    },
  );
  await page.goto('/');
  await expect(page.getByRole('button', { name: 'Allow once', exact: true })).toBeVisible();
});

test('waits for success, prevents repeat clicks and collapses the alternatives', async ({
  page,
}) => {
  await page.getByRole('button', { name: 'Allow once', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Deny', exact: true })).toBeDisabled();
  await expect(page.getByRole('status')).toHaveCount(0);
  await page.evaluate(() => {
    document.querySelectorAll<HTMLButtonElement>('button').forEach((button) => button.click());
    (window as unknown as { finish(): void }).finish();
  });
  await expect(page.getByRole('status')).toContainText('Allowed once');
  await expect(page.getByRole('button')).toHaveCount(0);
  expect(await page.evaluate(() => (window as unknown as { calls: number }).calls)).toBe(1);
});

test('failure keeps choices available and retry can succeed', async ({ page }) => {
  await page.getByRole('button', { name: 'Allow once', exact: true }).click();
  await page.evaluate(() =>
    (window as unknown as { fail(reason: Error): void }).fail(new Error('Connection lost')),
  );
  await expect(page.getByRole('alert')).toHaveText('Connection lost');
  await page.getByRole('button', { name: 'Deny', exact: true }).click();
  await page.evaluate(() => (window as unknown as { finish(): void }).finish());
  await expect(page.getByRole('status')).toHaveText('Deny');
  await expect(page.getByRole('button')).toHaveCount(0);
  expect(await page.evaluate(() => (window as unknown as { calls: number }).calls)).toBe(2);
});

test('optional callback supports standalone decisions', async ({ page }) => {
  await page.evaluate(() => {
    (window as unknown as { renderApproval(props: object): void }).renderApproval({
      onDecide: undefined,
    });
  });
  await page.getByRole('button', { name: 'Allow once', exact: true }).click();
  await expect(page.getByRole('status')).toContainText('Allowed once');
  await expect(page.getByRole('button')).toHaveCount(0);
});

test('live external resolution, stopped history and narrow dark reduced-motion layout', async ({
  page,
}) => {
  await page.setViewportSize({ width: 320, height: 844 });
  await page.emulateMedia({ reducedMotion: 'reduce', colorScheme: 'dark' });
  await page.evaluate(() => {
    (window as unknown as { renderApproval(props: object): void }).renderApproval({
      resolvedId: 'deny',
      question:
        'A very long operation requiring a decision and a complete explanation of its scope',
    });
  });
  await expect(page.getByRole('status')).toHaveText('Deny');
  await expect(page.getByRole('button')).toHaveCount(0);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page.evaluate(() => {
    (window as unknown as { renderApproval(props: object): void }).renderApproval({
      resolvedLabel: 'Stopped',
    });
  });
  await expect(page.getByRole('status')).toHaveText('Stopped');
  await expect(page.getByRole('button')).toHaveCount(0);
});
