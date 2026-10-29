import { memo, useEffect, useState, useSyncExternalStore, type ReactNode } from 'react';
import { motion, useReducedMotion } from 'motion/react';

export const ease = [0.2, 0.8, 0.2, 1] as const;

export function useMediaQuery(query: string) {
  return useSyncExternalStore(
    (notify) => {
      const list = window.matchMedia(query);
      list.addEventListener('change', notify);
      return () => list.removeEventListener('change', notify);
    },
    () => window.matchMedia(query).matches,
  );
}

export function Wordmark({ compact = false }: { compact?: boolean }) {
  return (
    <span className="wordmark" aria-label="nekodot">
      <svg className="brand-cat" viewBox="0 0 40 40" aria-hidden="true">
        <polygon points="7,15 10,3 18,10" />
        <polygon points="33,15 30,3 22,10" />
        <circle cx="20" cy="23" r="15" />
        <g className="brand-eyes">
          <ellipse cx="15" cy="23" rx="2" ry="2.6" />
          <ellipse cx="25" cy="23" rx="2" ry="2.6" />
        </g>
      </svg>
      {!compact && <span>nekodot</span>}
    </span>
  );
}

export const BotAvatar = memo(function BotAvatar({
  color,
  size = 48,
  working = false,
}: {
  color: string;
  size?: number;
  working?: boolean;
}) {
  const [blinking, setBlinking] = useState(false);
  const reduceMotion = useReducedMotion();
  useEffect(() => {
    if (working || reduceMotion) return;
    let timer: ReturnType<typeof setTimeout>;
    const schedule = () => {
      timer = setTimeout(
        () => {
          setBlinking(true);
          timer = setTimeout(() => {
            setBlinking(false);
            schedule();
          }, 160);
        },
        4000 + Math.random() * 3000,
      );
    };
    schedule();
    return () => clearTimeout(timer);
  }, [working, reduceMotion]);
  return (
    <svg
      className={`bot-avatar${working ? ' working' : blinking ? ' blinking' : ''}`}
      width={size}
      height={size}
      viewBox="0 0 40 40"
      style={{ overflow: 'visible' }}
      aria-hidden="true"
    >
      <polygon className="ear ear-left" points="7,15 10,3 18,10" fill={color} />
      <polygon className="ear ear-right" points="33,15 30,3 22,10" fill={color} />
      <circle cx="20" cy="23" r="15" fill={color} />
      <g className="eyes">
        <ellipse cx="15" cy="23" rx="2" ry="2.6" />
        <ellipse cx="25" cy="23" rx="2" ry="2.6" />
      </g>
    </svg>
  );
});

/** Stacked member colour dots for a group. */
export function GroupDots({ colors, size = 26 }: { colors: string[]; size?: number }) {
  return (
    <span className="group-dots" style={{ '--dot': `${size}px` } as React.CSSProperties}>
      {colors.slice(0, 3).map((color, index) => (
        <i key={index} style={{ background: color }} />
      ))}
    </span>
  );
}

/** Connection state dot: ok pulses, connecting spins a ring, offline stays still. */
export function StatusDot({ state }: { state: 'ok' | 'connecting' | 'offline' }) {
  return (
    <span className={`status-dot is-${state}`} aria-hidden="true">
      <i />
    </span>
  );
}

export function SpinnerDots() {
  return (
    <span className="thinking-dots" aria-hidden="true">
      <i />
      <i />
      <i />
    </span>
  );
}

export function Kbd({ children }: { children: ReactNode }) {
  return <kbd className="kbd">{children}</kbd>;
}

/** Segmented control whose selection indicator glides between options. */
export function Segmented<T extends string>({
  id,
  label,
  value,
  options,
  onChange,
}: {
  id: string;
  label: string;
  value: T;
  options: { value: T; label: string; icon?: IconName }[];
  onChange(value: T): void;
}) {
  const reduceMotion = useReducedMotion();
  return (
    <nav className="segmented" aria-label={label}>
      {options.map((option) => (
        <button
          key={option.value}
          aria-current={value === option.value ? 'page' : undefined}
          onClick={() => onChange(option.value)}
        >
          {value === option.value && (
            <motion.span
              className="segmented-thumb"
              layoutId={id}
              transition={
                reduceMotion ? { duration: 0 } : { type: 'spring', stiffness: 500, damping: 38 }
              }
            />
          )}
          {option.icon && <Icon name={option.icon} />}
          <span>{option.label}</span>
        </button>
      ))}
    </nav>
  );
}

export type IconName =
  | 'plus'
  | 'arrow'
  | 'arrowUp'
  | 'arrowDown'
  | 'panel'
  | 'back'
  | 'settings'
  | 'laptop'
  | 'server'
  | 'monitor'
  | 'send'
  | 'stop'
  | 'close'
  | 'chevron'
  | 'chevronDown'
  | 'spark'
  | 'plugin'
  | 'chat'
  | 'search'
  | 'doc'
  | 'terminal'
  | 'globe'
  | 'check'
  | 'warning'
  | 'copy'
  | 'users'
  | 'bot'
  | 'enter';

const paths: Record<IconName, ReactNode> = {
  spark: (
    <>
      <path d="m12 3 2.8 6.2L21 12l-6.2 2.8L12 21l-2.8-6.2L3 12l6.2-2.8L12 3Z" />
      <path d="m20 2 .7 1.3L22 4l-1.3.7L20 6l-.7-1.3L18 4l1.3-.7Z" />
    </>
  ),
  plugin: (
    <path d="M8 3h3a2.5 2.5 0 1 1 5 0h3v5a2.5 2.5 0 1 0 0 5v6h-6a2.5 2.5 0 1 0-5 0H3v-6a2.5 2.5 0 1 0 0-5V3h5Z" />
  ),
  chat: (
    <path d="M20 11.5a8.5 8.5 0 0 1-8.5 8.5H4l-2 2v-10.5A8.5 8.5 0 0 1 20 11.5ZM7 9h8M7 13h5" />
  ),
  plus: <path d="M12 5v14M5 12h14" />,
  arrow: <path d="M5 12h14m-6-6 6 6-6 6" />,
  arrowUp: <path d="M12 19V5M5 12l7-7 7 7" />,
  arrowDown: <path d="M12 5v14M19 12l-7 7-7-7" />,
  panel: (
    <>
      <rect x="3" y="4" width="18" height="16" rx="2.5" />
      <path d="M15 4v16" />
    </>
  ),
  back: <path d="M15 18l-6-6 6-6" />,
  settings: (
    <>
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z" />
    </>
  ),
  laptop: (
    <>
      <rect x="4" y="5" width="16" height="11" rx="2" />
      <path d="M2 19h20" />
    </>
  ),
  server: (
    <>
      <rect x="3" y="4" width="18" height="7" rx="2" />
      <rect x="3" y="13" width="18" height="7" rx="2" />
      <path d="M7 7.5h.01M7 16.5h.01" />
    </>
  ),
  monitor: (
    <>
      <rect x="3" y="4" width="18" height="12" rx="2" />
      <path d="M8 20h8M12 16v4" />
    </>
  ),
  send: <path d="m22 2-7 20-4-9-9-4 20-7ZM22 2 11 13" />,
  stop: <rect x="6" y="6" width="12" height="12" rx="2" />,
  close: <path d="M6 6l12 12M18 6 6 18" />,
  chevron: <path d="m9 18 6-6-6-6" />,
  chevronDown: <path d="m6 9 6 6 6-6" />,
  search: (
    <>
      <circle cx="11" cy="11" r="7" />
      <path d="m20 20-4-4" />
    </>
  ),
  doc: (
    <>
      <path d="M4 4h16v16H4z" />
      <path d="M8 9h8M8 13h8M8 17h5" />
    </>
  ),
  terminal: <path d="m5 7 5 5-5 5M12 17h7" />,
  globe: (
    <>
      <circle cx="12" cy="12" r="9" />
      <path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18" />
    </>
  ),
  check: <path d="M5 12.5l4.5 4.5L19 7.5" />,
  warning: (
    <>
      <path d="M12 3l9 16H3z" />
      <path d="M12 10v4M12 17v.5" />
    </>
  ),
  copy: (
    <>
      <rect x="9" y="9" width="11" height="11" rx="2" />
      <path d="M5 15V5a2 2 0 0 1 2-2h10" />
    </>
  ),
  users: (
    <>
      <circle cx="9" cy="8" r="3.5" />
      <path d="M2.5 20a6.5 6.5 0 0 1 13 0M16 4.6a3.5 3.5 0 0 1 0 6.8M18.5 14a6.5 6.5 0 0 1 3 6" />
    </>
  ),
  bot: (
    <>
      <path d="M6 9.5 7 3l4.5 3.5M18 9.5 17 3l-4.5 3.5" />
      <circle cx="12" cy="14" r="7.5" />
      <path d="M9.5 14v.5M14.5 14v.5" />
    </>
  ),
  enter: <path d="M9 10l-5 5 5 5M20 4v7a4 4 0 0 1-4 4H4" />,
};

export function Icon({ name }: { name: IconName }) {
  return (
    <svg
      className="icon"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {paths[name]}
    </svg>
  );
}
