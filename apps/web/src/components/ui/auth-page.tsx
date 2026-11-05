import type { ReactNode } from 'react';
import { motion, useReducedMotion } from 'motion/react';
import { ChevronLeft, Globe2 } from 'lucide-react';
import { Wordmark } from '../../ui';
import { Button } from './button';

export function AuthPage({
  children,
  headline,
  description,
  language,
  languageLabel,
  homeLabel,
  onToggleLanguage,
}: {
  children: ReactNode;
  headline: string;
  description: string;
  language: 'zh' | 'en';
  languageLabel: string;
  homeLabel: string;
  onToggleLanguage(): void;
}) {
  return (
    <main className="auth-layout" lang={language}>
      <aside className="auth-brand-panel">
        <div className="auth-brand-mark">
          <Wordmark />
        </div>
        <div className="auth-paths" aria-hidden="true">
          <FloatingPaths position={1} />
          <FloatingPaths position={-1} />
        </div>
        <div className="auth-intro">
          <h1>{headline}</h1>
          <p>{description}</p>
        </div>
      </aside>
      <section className="auth-form-panel">
        <div className="auth-toolbar">
          <Button variant="ghost" size="sm" asChild>
            <a href="https://nekodot.com">
              <ChevronLeft size={16} />
              {homeLabel}
            </a>
          </Button>
          <Button variant="ghost" size="sm" type="button" onClick={onToggleLanguage}>
            <Globe2 size={16} />
            {languageLabel}
          </Button>
        </div>
        <div className="auth-form-content">
          <div className="auth-mobile-mark">
            <Wordmark />
          </div>
          {children}
        </div>
      </section>
    </main>
  );
}

function FloatingPaths({ position }: { position: number }) {
  const reducedMotion = useReducedMotion();
  return (
    <svg viewBox="-240 -60 1000 1000" fill="none" preserveAspectRatio="xMidYMid slice">
      {Array.from({ length: 36 }, (_, index) => {
        const offset = index * 5 * position;
        const path = `M-${380 - offset} -${189 + index * 6}C-${380 - offset} -${189 + index * 6} -${312 - offset} ${216 - index * 6} ${152 - offset} ${343 - index * 6}C${616 - offset} ${470 - index * 6} ${684 - offset} ${875 - index * 6} ${684 - offset} ${875 - index * 6}`;
        return (
          <motion.path
            key={index}
            d={path}
            stroke="currentColor"
            strokeWidth={0.5 + index * 0.03}
            strokeOpacity={0.1 + index * 0.018}
            initial={false}
            animate={
              reducedMotion
                ? { pathLength: 1, opacity: 0.5 }
                : {
                    pathLength: [1, 0.7, 1],
                    opacity: [0.45, 0.65, 0.45],
                    pathOffset: [0, 0.3, 0],
                  }
            }
            transition={
              reducedMotion
                ? { duration: 0 }
                : {
                    duration: 20 + index * 0.23,
                    repeat: Infinity,
                    ease: 'linear',
                  }
            }
          />
        );
      })}
    </svg>
  );
}
