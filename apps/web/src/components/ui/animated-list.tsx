import {
  useCallback,
  useLayoutEffect,
  useRef,
  type HTMLAttributes,
  type ReactNode,
  type Ref,
} from 'react';
import '../../styles/animated-list.css';

type AnimatedListProps = HTMLAttributes<HTMLElement> & {
  as?: 'div' | 'ul' | 'ol';
  children?: ReactNode;
  showGradients?: boolean;
  ref?: Ref<HTMLElement>;
};

/**
 * Adapted from ReactBits Animated List (MIT + Commons Clause):
 * https://reactbits.dev/components/animated-list
 * Keeps its pop/slide reveal, stagger, spring ring and scroll fades while
 * retaining the application's own row elements, semantics and scroll parents.
 */
export function AnimatedList({
  as = 'div',
  children,
  className = '',
  showGradients = true,
  ref,
  ...props
}: AnimatedListProps) {
  const rootRef = useRef<HTMLElement | null>(null);
  const setRoot = useCallback(
    (element: HTMLElement | null) => {
      rootRef.current = element;
      if (typeof ref === 'function') return ref(element);
      if (ref) ref.current = element;
    },
    [ref],
  );

  useLayoutEffect(() => {
    const root = rootRef.current;
    if (!root) return;
    const preference = window.matchMedia('(prefers-reduced-motion: reduce)');
    const rows = new Set<HTMLElement>();
    let active: HTMLElement | undefined;
    let frame = 0;

    const updateFades = () => {
      const scrolls =
        /auto|scroll/.test(getComputedStyle(root).overflowY) &&
        root.scrollHeight > root.clientHeight;
      root.toggleAttribute('data-list-scrolls', showGradients && scrolls);
      const span = showGradients && scrolls ? Math.min(40, root.clientHeight / 4) : 0;
      root.style.setProperty('--al-fade-top', `${Math.min(span, Math.max(0, root.scrollTop))}px`);
      root.style.setProperty(
        '--al-fade-bottom',
        `${Math.min(span, Math.max(0, root.scrollHeight - root.clientHeight - root.scrollTop))}px`,
      );
    };
    const placeRing = () => {
      if (!active || !root.contains(active)) {
        delete root.dataset.listActive;
        return;
      }
      const box = active.getBoundingClientRect();
      const parent = root.getBoundingClientRect();
      root.style.setProperty(
        '--al-ring-x',
        `${box.left - parent.left + root.scrollLeft - root.clientLeft}px`,
      );
      root.style.setProperty(
        '--al-ring-y',
        `${box.top - parent.top + root.scrollTop - root.clientTop}px`,
      );
      root.style.setProperty('--al-ring-width', `${box.width}px`);
      root.style.setProperty('--al-ring-height', `${box.height}px`);
      root.style.setProperty('--al-ring-radius', getComputedStyle(active).borderRadius);
      root.dataset.listActive = '';
    };
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          const row = entry.target as HTMLElement;
          const visible =
            preference.matches || entry.isIntersecting || row.contains(document.activeElement);
          row.dataset.listState = visible
            ? 'in'
            : entry.boundingClientRect.bottom <= 0
              ? 'above'
              : 'below';
          if (visible) {
            if (row.dataset.listSeen !== undefined) row.style.setProperty('--al-delay', '0s');
            row.dataset.listSeen = '';
          }
        }
      },
      { threshold: 0 },
    );
    const resize = new ResizeObserver(() => {
      updateFades();
      placeRing();
    });
    const sync = () => {
      const current = new Set(
        Array.from(root.children).filter(
          (row): row is HTMLElement =>
            row instanceof HTMLElement &&
            !row.matches('[role="dialog"], [role="alertdialog"]') &&
            !row.querySelector('[role="dialog"], [role="alertdialog"]'),
        ),
      );
      for (const row of rows) {
        if (current.has(row)) continue;
        observer.unobserve(row);
        resize.unobserve(row);
        rows.delete(row);
      }
      let order = 0;
      for (const row of current) {
        if (rows.has(row)) continue;
        rows.add(row);
        row.style.setProperty('--al-delay', `${Math.min(order++, 6) * 0.05}s`);
        row.dataset.listState = preference.matches ? 'in' : 'below';
        // Establish the initial pose before the observer reveals the new row.
        void row.offsetHeight;
        observer.observe(row);
        resize.observe(row);
      }
      updateFades();
      placeRing();
    };
    const changePreference = () => {
      for (const row of rows) {
        row.dataset.listState = 'in';
        row.style.setProperty('--al-delay', '0s');
        observer.unobserve(row);
        observer.observe(row);
      }
    };
    const point = (event: Event) => {
      let target = event.target instanceof Element ? event.target : null;
      while (target && target.parentElement !== root) target = target.parentElement;
      if (!(target instanceof HTMLElement) || !rows.has(target)) return;
      active = target;
      if (event.type === 'focusin') target.dataset.listState = 'in';
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(placeRing);
    };
    const leave = () => {
      active = undefined;
      delete root.dataset.listActive;
    };
    const blur = (event: FocusEvent) => {
      if (!root.contains(event.relatedTarget as Node | null)) leave();
    };
    const mutation = new MutationObserver(sync);
    mutation.observe(root, { childList: true });
    resize.observe(root);
    root.addEventListener('scroll', updateFades, { passive: true });
    root.addEventListener('pointermove', point);
    root.addEventListener('pointerleave', leave);
    root.addEventListener('focusin', point);
    root.addEventListener('focusout', blur);
    preference.addEventListener('change', changePreference);
    sync();
    return () => {
      cancelAnimationFrame(frame);
      observer.disconnect();
      resize.disconnect();
      mutation.disconnect();
      root.removeEventListener('scroll', updateFades);
      root.removeEventListener('pointermove', point);
      root.removeEventListener('pointerleave', leave);
      root.removeEventListener('focusin', point);
      root.removeEventListener('focusout', blur);
      preference.removeEventListener('change', changePreference);
      for (const row of rows) {
        delete row.dataset.listState;
        delete row.dataset.listSeen;
        row.style.removeProperty('--al-delay');
      }
      leave();
    };
  }, [showGradients]);

  const Tag = as;
  return (
    <Tag
      {...props}
      className={`animated-list ${className}`.trim()}
      data-component="reactbits-animated-list"
      ref={setRoot}
    >
      {children}
    </Tag>
  );
}
