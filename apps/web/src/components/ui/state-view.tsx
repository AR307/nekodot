import type { ReactNode } from 'react';
import { motion } from 'motion/react';
import { useMotion } from '../../motion';
import { LoadingText } from '../../ui';

/**
 * One layout for the four non-content states of a panel or list: loading, empty, error and
 * offline. Errors are announced assertively and offer a retry when one is given.
 */
export function StateView({
  kind,
  title,
  message,
  action,
  compact = false,
}: {
  kind: 'loading' | 'empty' | 'error' | 'offline';
  title?: ReactNode;
  message?: ReactNode;
  action?: { label: string; run(): void; disabled?: boolean };
  /** Inline variant for lists inside cards and sheets. */
  compact?: boolean;
}) {
  const m = useMotion();
  return (
    <motion.div
      className={`state-view state-${kind}${compact ? ' state-compact' : ''}`}
      role={kind === 'error' ? 'alert' : 'status'}
      initial={{ opacity: 0, y: m.rise(1) }}
      animate={{ opacity: 1, y: 0 }}
      transition={m.tween('base')}
    >
      {kind === 'loading' ? (
        <LoadingText text={typeof title === 'string' ? title : undefined} />
      ) : (
        <>
          {title && <strong>{title}</strong>}
          {message && <p>{message}</p>}
          {action && (
            <button
              type="button"
              className="secondary-button"
              onClick={action.run}
              disabled={action.disabled}
            >
              {action.label}
            </button>
          )}
        </>
      )}
    </motion.div>
  );
}
