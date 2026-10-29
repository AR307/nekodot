import { useEffect, type FormEvent, type ReactNode } from 'react';
import { motion, useDragControls, useReducedMotion } from 'motion/react';
import { Icon, ease, useMediaQuery } from '../ui';

/**
 * Modal form surface: a bottom sheet with a drag handle on phones (drag down to dismiss),
 * a centred dialog on wider screens. Escape and the backdrop close it.
 */
export function Sheet({
  className,
  title,
  titleId,
  closeLabel,
  onClose,
  onSubmit,
  children,
  footer,
}: {
  className: string;
  title: ReactNode;
  titleId: string;
  closeLabel: string;
  onClose(): void;
  onSubmit(event: FormEvent): void;
  children: ReactNode;
  footer: ReactNode;
}) {
  const compact = useMediaQuery('(max-width: 767px)');
  const reduceMotion = useReducedMotion();
  const drag = useDragControls();
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);
  const hidden = reduceMotion
    ? { opacity: 0 }
    : compact
      ? { y: '100%' }
      : { opacity: 0, y: 12, scale: 0.97 };
  return (
    <motion.div
      className="dialog-backdrop"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: reduceMotion ? 0.1 : 0.2 }}
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <motion.form
        className={`sheet ${className}`}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        initial={hidden}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        exit={hidden}
        transition={
          reduceMotion
            ? { duration: 0.1 }
            : compact
              ? { duration: 0.32, ease }
              : { duration: 0.24, ease }
        }
        drag={compact && !reduceMotion ? 'y' : false}
        dragListener={false}
        dragControls={drag}
        dragConstraints={{ top: 0, bottom: 0 }}
        dragElastic={{ top: 0, bottom: 0.6 }}
        onDragEnd={(_, info) => {
          if (info.offset.y > 120 || info.velocity.y > 600) onClose();
        }}
        onSubmit={onSubmit}
      >
        <header onPointerDown={(event) => compact && drag.start(event)}>
          <span className="sheet-handle" aria-hidden="true" />
          <h2 id={titleId}>{title}</h2>
          <button type="button" className="icon-button" onClick={onClose} aria-label={closeLabel}>
            <Icon name="close" />
          </button>
        </header>
        <div className="dialog-body">{children}</div>
        <footer>{footer}</footer>
      </motion.form>
    </motion.div>
  );
}
