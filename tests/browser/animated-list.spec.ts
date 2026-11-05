import { expect, test } from '@playwright/test';

async function mountList(page: import('@playwright/test').Page) {
  await page.goto('/');
  await page.evaluate(async () => {
    const reactUrl = '/node_modules/.vite/deps/react.js';
    const domUrl = '/node_modules/.vite/deps/react-dom_client.js';
    const componentUrl = '/src/components/ui/animated-list.tsx';
    const { default: React } = await import(/* @vite-ignore */ reactUrl);
    const { default: ReactDOM } = await import(/* @vite-ignore */ domUrl);
    const { AnimatedList } = await import(/* @vite-ignore */ componentUrl);
    document.querySelector('#root')?.setAttribute('hidden', '');
    const host = document.createElement('main');
    document.body.append(host);
    const render = (ids: number[]) =>
      root.render(
        React.createElement(
          AnimatedList,
          { className: 'list-fixture', style: { height: 200, overflowY: 'auto' } },
          ...ids.map((id) =>
            React.createElement(
              'label',
              { key: id, style: { display: 'flex', height: 64, padding: 12 } },
              React.createElement('input', { type: 'checkbox', 'aria-label': `Select ${id}` }),
              `Row ${id}`,
            ),
          ),
        ),
      );
    const root = ReactDOM.createRoot(host);
    Object.assign(window, { renderAnimatedList: render });
    render(Array.from({ length: 16 }, (_, i) => i));
  });
}

test('animated list reveals scrolled and inserted rows without replacing row controls', async ({
  page,
}) => {
  await mountList(page);
  const list = page.locator('.list-fixture');
  await expect(list).toHaveAttribute('data-component', 'reactbits-animated-list');
  await page.getByRole('checkbox', { name: 'Select 0', exact: true }).check();
  await expect(page.getByRole('checkbox', { name: 'Select 0', exact: true })).toBeChecked();
  await list.evaluate((element) => {
    element.scrollTop = element.scrollHeight;
  });
  await expect(page.getByRole('checkbox', { name: 'Select 15', exact: true })).toBeInViewport();
  await expect(list.locator(':scope > label').last()).toHaveAttribute('data-list-state', 'in');
  await expect(list).toHaveCSS('--al-fade-bottom', '0px');
  await page.evaluate(() => {
    (window as unknown as { renderAnimatedList(ids: number[]): void }).renderAnimatedList([
      15, 99, 0,
    ]);
  });
  await expect(page.getByRole('checkbox', { name: 'Select 99', exact: true })).toBeInViewport();
  await expect(page.getByRole('checkbox', { name: 'Select 0', exact: true })).toBeChecked();
});

test('reduced motion displays rows immediately and responds to preference changes', async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await mountList(page);
  const list = page.locator('.list-fixture');
  await expect(list.locator(':scope > label').last()).toHaveAttribute('data-list-state', 'in');
  await expect(list.locator(':scope > label').first()).toHaveCSS('scale', 'none');
  await page.emulateMedia({ reducedMotion: 'no-preference' });
  await list.evaluate((element) => {
    element.scrollTop = element.scrollHeight;
  });
  await expect(list.locator(':scope > label').last()).toHaveAttribute('data-list-state', 'in');
});

test('lists use their existing outer scroll container and keyboard focus reveals rows', async ({
  page,
}) => {
  await mountList(page);
  const list = page.locator('.list-fixture');
  await list.evaluate((element) => {
    const parent = document.createElement('section');
    parent.style.cssText = 'height:200px;overflow:auto';
    element.before(parent);
    parent.append(element);
    Object.assign((element as HTMLElement).style, { height: 'auto', overflowY: 'visible' });
    parent.scrollTop = parent.scrollHeight;
  });
  await expect(list.locator(':scope > label').last()).toHaveAttribute('data-list-state', 'in');
  await page.getByRole('checkbox', { name: 'Select 0', exact: true }).focus();
  await expect(list.locator(':scope > label').first()).toHaveAttribute('data-list-state', 'in');
  await expect(page.getByRole('checkbox', { name: 'Select 0', exact: true })).toBeInViewport();
});

test('row preview dialogs cover the viewport without list clipping or animation', async ({
  page,
}) => {
  await mountList(page);
  await page.locator('.list-fixture').evaluate((element) => {
    Object.assign((element as HTMLElement).style, { height: 'auto', overflowY: 'visible' });
    const backdrop = document.createElement('div');
    backdrop.style.cssText =
      'position:fixed;inset:0;z-index:100;background:white;display:grid;place-items:center';
    const dialog = document.createElement('section');
    dialog.setAttribute('role', 'dialog');
    const close = document.createElement('button');
    close.textContent = 'Close preview';
    close.onclick = () => backdrop.remove();
    dialog.append(close);
    backdrop.append(dialog);
    element.append(backdrop);
  });
  await expect(page.getByRole('dialog').locator('..')).not.toHaveAttribute('data-list-state');
  await page.getByRole('button', { name: 'Close preview' }).click({ timeout: 3000 });
  await expect(page.getByRole('dialog')).toHaveCount(0);
});

test('hover ring stays within the page while switching from desktop to phone width', async ({
  page,
}) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await mountList(page);
  await page.locator('.list-fixture > label').first().hover();
  await page.setViewportSize({ width: 390, height: 900 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
});
