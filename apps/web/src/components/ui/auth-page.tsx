import type { ReactNode } from 'react';
import { Icon, Wordmark } from '../../ui';

function FloatingPaths() {
  return (
    <svg className="auth-paths" viewBox="0 0 600 800" fill="none" aria-hidden="true">
      {[1, -1].map((direction) => (
        <g key={direction} transform={direction < 0 ? 'translate(600 800) rotate(180)' : undefined}>
          {Array.from({ length: 24 }, (_, index) => (
            <path
              key={index}
              d={`M ${-160 + index * 12} -80 C ${380 + index * 8} 120, ${-240 + index * 14} 420, ${320 + index * 12} 900`}
              stroke="currentColor"
              strokeWidth="0.7"
              style={{ animationDelay: `${index * -0.4}s` }}
            />
          ))}
        </g>
      ))}
    </svg>
  );
}

export function AuthFrame({
  headline,
  description,
  note,
  language,
  languageLabel,
  onToggleLanguage,
  children,
}: {
  headline: string;
  description: string;
  note: string;
  language: 'zh' | 'en';
  languageLabel: string;
  onToggleLanguage(): void;
  children: ReactNode;
}) {
  return (
    <main className="auth-layout" lang={language}>
      <section className="auth-brand-panel">
        <Wordmark />
        <FloatingPaths />
        <div className="auth-intro">
          <h1>{headline}</h1>
          <p>{description}</p>
        </div>
        <span className="auth-brand-note">{note}</span>
      </section>
      <section className="auth-form-panel">
        <button className="quiet-button auth-language" type="button" onClick={onToggleLanguage}>
          <Icon name="globe" />
          {languageLabel}
        </button>
        {children}
      </section>
    </main>
  );
}
