'use client';

import { useEffect, useSyncExternalStore, type ComponentPropsWithoutRef } from 'react';
import { useAnimate } from 'motion/react';
import { durations } from '../../motion';

const motionQuery = '(prefers-reduced-motion: reduce)';
const subscribeMotion = (notify: () => void) => {
  const query = window.matchMedia(motionQuery);
  query.addEventListener('change', notify);
  return () => query.removeEventListener('change', notify);
};

type ShiningTextProps = Omit<ComponentPropsWithoutRef<'span'>, 'children'> & {
  text: string;
};

/** Inline so loading text also fits buttons, headings and live status regions. */
export function ShiningText({ text, className = '', ...props }: ShiningTextProps) {
  const reduceMotion = useSyncExternalStore(
    subscribeMotion,
    () => window.matchMedia(motionQuery).matches,
    () => true,
  );
  const [scope, animate] = useAnimate<HTMLSpanElement>();
  useEffect(() => {
    if (reduceMotion) return;
    const animation = animate(
      scope.current,
      { backgroundPosition: ['200% 0%', '-200% 0%'] },
      { repeat: Infinity, duration: durations.shimmer, ease: 'linear' },
    );
    return () => animation.stop();
  }, [animate, reduceMotion, scope]);
  return (
    <span {...props} ref={scope} className={`shining-text ${className}`}>
      {text}
    </span>
  );
}
