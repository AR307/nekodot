import { type ReactNode, useId, useRef, useState } from 'react';
import { AnimatedList } from './animated-list';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import { Icon, LoadingText } from '../../ui';
import '../../styles/ai-approval.css';
import { springy } from '../../motion';

export type AIApprovalOption = {
  id: string;
  label: string;
  detail?: string;
  destructive?: boolean;
  resultLabel?: string;
};

export type AIApprovalProps = {
  question: string;
  options: AIApprovalOption[];
  children?: ReactNode;
  className?: string;
  resolvedId?: string;
  /** Also closes a cancelled or failed request that has no selected option. */
  resolvedLabel?: string;
  disabled?: boolean;
  onDecide?: (option: AIApprovalOption) => void | Promise<void>;
};

export default function AIApproval({
  question,
  options,
  children,
  className = '',
  resolvedId,
  resolvedLabel,
  disabled = false,
  onDecide,
}: AIApprovalProps) {
  const questionId = useId();
  const reduceMotion = useReducedMotion();
  const submitting = useRef(false);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [submittedId, setSubmittedId] = useState<string | null>(null);
  const [error, setError] = useState('');
  const chosenId = resolvedId ?? submittedId;
  const chosen = options.find((option) => option.id === chosenId);
  const resolved = Boolean(chosenId || resolvedLabel);
  const transition = springy(reduceMotion);

  async function decide(option: AIApprovalOption) {
    if (disabled || resolved || submitting.current) return;
    submitting.current = true;
    setBusyId(option.id);
    setError('');
    try {
      await onDecide?.(option);
      setSubmittedId(option.id);
    } catch (reason) {
      submitting.current = false;
      setError(reason instanceof Error ? reason.message : String(reason));
    } finally {
      setBusyId(null);
    }
  }

  return (
    <motion.div
      className={`ai-approval ${resolved ? 'is-resolved' : 'is-pending'} ${className}`}
      role="group"
      aria-labelledby={questionId}
      aria-busy={Boolean(busyId)}
      layout={!reduceMotion}
      transition={transition}
    >
      <motion.div layout={!reduceMotion} transition={transition}>
        <p className="ai-approval-question" id={questionId}>
          {question}
        </p>
        {children && <div className="ai-approval-context">{children}</div>}
      </motion.div>
      <div className="ai-approval-decision">
        <AnimatePresence initial={false} mode="popLayout">
          {resolved ? (
            <motion.div
              key="resolved"
              className={`ai-approval-result${chosen?.destructive ? ' is-destructive' : chosen ? ' is-chosen' : ''}`}
              role="status"
              initial={reduceMotion ? false : { opacity: 0, scale: 0.97 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={transition}
            >
              <Icon name={chosen ? 'check' : 'close'} />
              <span>{resolvedLabel ?? chosen?.resultLabel ?? chosen?.label}</span>
              {chosen?.detail && <small>{chosen.detail}</small>}
            </motion.div>
          ) : (
            <AnimatedList className="ai-approval-options" key="options">
              {options.map((option) => (
                <motion.button
                  className={`ai-approval-option${option.destructive ? ' is-destructive' : ''}`}
                  key={option.id}
                  type="button"
                  aria-label={option.label}
                  disabled={disabled || Boolean(busyId)}
                  whileTap={reduceMotion ? undefined : { scale: 0.99 }}
                  onClick={() => void decide(option)}
                >
                  <span>{option.label}</span>
                  {option.detail && <small>{option.detail}</small>}
                  {busyId === option.id && <LoadingText action="submitting" />}
                </motion.button>
              ))}
            </AnimatedList>
          )}
        </AnimatePresence>
      </div>
      {error && !resolved && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
    </motion.div>
  );
}
