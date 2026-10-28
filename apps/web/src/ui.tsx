import { memo, useEffect, useState } from 'react';
import { useReducedMotion } from 'motion/react';

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
      {!compact && (
        <span>
          nekodot<span className="brand-period">.</span>
        </span>
      )}
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

export function SpinnerDots() {
  return (
    <span className="thinking-dots" aria-hidden="true">
      <i />
      <i />
      <i />
    </span>
  );
}

export function Icon({
  name,
}: {
  name: 'plus' | 'arrow' | 'settings' | 'laptop' | 'send' | 'stop' | 'close' | 'chevron';
}) {
  const paths: Record<typeof name, React.ReactNode> = {
    plus: <path d="M12 5v14M5 12h14" />,
    arrow: <path d="M5 12h14m-6-6 6 6-6 6" />,
    settings: (
      <>
        <circle cx="12" cy="12" r="3" />
        <path d="M12 2h2l.7 3a7 7 0 0 1 1.8 1l3-.9 2 3.5-2.3 2.1a7 7 0 0 1 0 2.6l2.3 2.1-2 3.5-3-.9a7 7 0 0 1-1.8 1l-.7 3h-4l-.7-3a7 7 0 0 1-1.8-1l-3 .9-2-3.5 2.3-2.1a7 7 0 0 1 0-2.6L2.5 8.6l2-3.5 3 .9a7 7 0 0 1 1.8-1l.7-3Z" />
      </>
    ),
    laptop: (
      <>
        <rect x="4" y="5" width="16" height="12" rx="1.5" />
        <path d="M2.5 20h19" />
      </>
    ),
    send: <path d="m22 2-7 20-4-9-9-4 20-7ZM22 2 11 13" />,
    stop: <rect x="6" y="6" width="12" height="12" rx="2" />,
    close: <path d="m6 6 12 12M18 6 6 18" />,
    chevron: <path d="m9 18 6-6-6-6" />,
  };
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
