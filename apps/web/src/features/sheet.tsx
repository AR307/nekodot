import type { FormEvent, ReactNode } from 'react';
import { Dialog } from '../components/ui/dialog';
import { Icon } from '../ui';

/**
 * Modal form surface: a bottom sheet with a drag handle on phones (drag down to dismiss),
 * a centred dialog on wider screens. Focus, Escape, backdrop and motion come from Dialog.
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
  return (
    <Dialog
      as="form"
      className={`sheet ${className}`}
      labelledBy={titleId}
      placement="sheet"
      onClose={onClose}
      onSubmit={onSubmit}
      dragHandle={(start) => (
        <header onPointerDown={start}>
          <span className="sheet-handle" aria-hidden="true" />
          <h2 id={titleId}>{title}</h2>
          <button
            type="button"
            className="icon-button dialog-close"
            onClick={onClose}
            aria-label={closeLabel}
          >
            <Icon name="close" />
          </button>
        </header>
      )}
    >
      <div className="dialog-body">{children}</div>
      <footer>{footer}</footer>
    </Dialog>
  );
}
