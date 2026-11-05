import type { KeyboardEvent } from 'react';

/**
 * Arrow-key movement for `role="menu"` popups (WAI-ARIA menu pattern): ↓/↑ move between
 * enabled menu items and wrap, Home/End jump to the ends. Attach to the menu's container
 * or to an ancestor that also contains the trigger. Returns whether the key was handled.
 */
export function moveMenuFocus(event: KeyboardEvent<HTMLElement>) {
  if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) return false;
  const items = [
    ...event.currentTarget.querySelectorAll<HTMLElement>(
      '[role="menu"] [role^="menuitem"]:not(:disabled)',
    ),
  ];
  if (!items.length) return false;
  event.preventDefault();
  const current = items.indexOf(document.activeElement as HTMLElement);
  const last = items.length - 1;
  const next =
    event.key === 'Home'
      ? 0
      : event.key === 'End'
        ? last
        : event.key === 'ArrowDown'
          ? current < 0 || current === last
            ? 0
            : current + 1
          : current <= 0
            ? last
            : current - 1;
  items[next]!.focus();
  return true;
}
