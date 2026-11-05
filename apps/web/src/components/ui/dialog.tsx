import {
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type FormEvent,
  type KeyboardEvent,
  type PointerEvent,
  type ReactNode,
} from 'react';
import { createPortal } from 'react-dom';
import { motion, useDragControls, type TargetAndTransition } from 'motion/react';
import { media, useMotion } from '../../motion';
import { useMediaQuery } from '../../ui';

/**
 * Modal foundation for every dialog, sheet and full-screen preview.
 * - Renders in its own layer on <body>; the app and lower dialogs become inert.
 * - Focus moves inside on open ([data-autofocus] or the first field), Tab cycles within,
 *   Escape closes only the top dialog, and focus returns to where it was on close.
 * - Page scroll is locked while any dialog is open.
 * - Motion follows the shared tokens; phones get a bottom sheet that drags down to close.
 */
export type DialogPlacement = 'center' | 'sheet' | 'top' | 'side' | 'full';

const layers: HTMLElement[] = [];

function syncInert() {
  const root = document.getElementById('root');
  const top = layers.at(-1);
  if (root) root.inert = layers.length > 0;
  for (const layer of layers) layer.inert = layer !== top;
  document.body.style.overflow = layers.length ? 'hidden' : '';
}

const focusable =
  'a[href], button:not([disabled]), input:not([disabled]):not([type="hidden"]), select:not([disabled]), textarea:not([disabled]), summary, [tabindex]:not([tabindex="-1"]), [contenteditable="true"]';

function tabbables(container: HTMLElement) {
  return [...container.querySelectorAll<HTMLElement>(focusable)].filter(
    (element) =>
      !element.closest('[inert], [hidden], [aria-hidden="true"]') &&
      element.getClientRects().length > 0,
  );
}

export function Dialog({
  label,
  labelledBy,
  className,
  backdropClassName = 'dialog-backdrop',
  placement = 'center',
  as = 'section',
  dismissible = true,
  onClose,
  onSubmit,
  dragHandle,
  children,
}: {
  label?: string;
  labelledBy?: string;
  className: string;
  backdropClassName?: string;
  /** Where the panel lives; `sheet` becomes a bottom sheet on phones and centred otherwise. */
  placement?: DialogPlacement;
  as?: 'section' | 'form' | 'div';
  /** False while a blocking action runs: Escape and the backdrop do nothing. */
  dismissible?: boolean;
  onClose(): void;
  onSubmit?(event: FormEvent): void;
  /** Bottom sheets start a drag from this handle area (receives pointer-down). */
  dragHandle?: (start: (event: PointerEvent) => void) => ReactNode;
  children: ReactNode;
}) {
  const [layer] = useState(() => {
    const element = document.createElement('div');
    element.className = 'dialog-layer';
    return element;
  });
  const panel = useRef<HTMLElement>(null);
  const close = useRef(onClose);
  const canDismiss = useRef(dismissible);
  useLayoutEffect(() => {
    close.current = onClose;
    canDismiss.current = dismissible;
  });
  const phone = useMediaQuery(media.phone);
  const motionTokens = useMotion();
  const drag = useDragControls();
  const bottomSheet = placement === 'sheet' && phone;

  useLayoutEffect(() => {
    const previous = document.activeElement as HTMLElement | null;
    document.body.append(layer);
    layers.push(layer);
    syncInert();
    return () => {
      layers.splice(layers.indexOf(layer), 1);
      layer.remove();
      syncInert();
      if (previous?.isConnected) previous.focus({ preventScroll: true });
    };
  }, [layer]);

  useEffect(() => {
    const container = panel.current;
    if (!container) return;
    // A form starts at its first field; a read-only panel starts at itself, never on an
    // action button that a stray Enter/Space could trigger.
    const preferred = container.querySelector<HTMLElement>('[data-autofocus], [autofocus]');
    const field = tabbables(container).find((element) =>
      element.matches('input, select, textarea, [contenteditable="true"]'),
    );
    (preferred ?? field ?? container).focus({ preventScroll: true });
  }, []);

  function onKeyDown(event: KeyboardEvent) {
    if (event.key === 'Escape') {
      event.stopPropagation();
      if (canDismiss.current) close.current();
      return;
    }
    if (event.key !== 'Tab' || !panel.current) return;
    const items = tabbables(panel.current);
    if (!items.length) {
      event.preventDefault();
      return;
    }
    const first = items[0]!,
      last = items.at(-1)!;
    const active = document.activeElement;
    if (event.shiftKey && (active === first || !panel.current.contains(active))) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && (active === last || !panel.current.contains(active))) {
      event.preventDefault();
      first.focus();
    }
  }

  const hidden: TargetAndTransition = motionTokens.reduce
    ? { opacity: 0 }
    : bottomSheet
      ? { y: '100%' }
      : placement === 'side'
        ? phone
          ? { y: '100%' }
          : { x: 24, opacity: 0 }
        : placement === 'top'
          ? { opacity: 0, y: -motionTokens.rise(2), scale: 0.98 }
          : placement === 'full'
            ? { opacity: 0, x: motionTokens.rise(3) }
            : { opacity: 0, y: motionTokens.rise(2), scale: 0.98 };
  const Panel = as === 'form' ? motion.form : as === 'div' ? motion.div : motion.section;

  return createPortal(
    <motion.div
      className={backdropClassName}
      data-placement={placement}
      initial={{ opacity: 0 }}
      animate={{ opacity: 1, transition: motionTokens.tween('base') }}
      exit={{ opacity: 0, transition: motionTokens.tween('fast') }}
      onKeyDown={onKeyDown}
      onMouseDown={(event) => {
        if (event.target === event.currentTarget && canDismiss.current) close.current();
      }}
    >
      <Panel
        ref={panel as never}
        className={className}
        role="dialog"
        aria-modal="true"
        aria-label={label}
        aria-labelledby={labelledBy}
        tabIndex={-1}
        initial={hidden}
        animate={{
          opacity: 1,
          x: 0,
          y: 0,
          scale: 1,
          transition: motionTokens.tween(bottomSheet || placement === 'side' ? 'panel' : 'base'),
        }}
        exit={{
          ...hidden,
          transition: motionTokens.tween(bottomSheet || placement === 'side' ? 'base' : 'fast'),
        }}
        drag={bottomSheet && !motionTokens.reduce ? 'y' : false}
        dragListener={false}
        dragControls={drag}
        dragConstraints={{ top: 0, bottom: 0 }}
        dragElastic={{ top: 0, bottom: 0.6 }}
        onDragEnd={(_, info) => {
          if ((info.offset.y > 120 || info.velocity.y > 600) && canDismiss.current) close.current();
        }}
        onSubmit={onSubmit}
      >
        {dragHandle?.((event) => bottomSheet && drag.start(event))}
        {children}
      </Panel>
    </motion.div>,
    layer,
  );
}
