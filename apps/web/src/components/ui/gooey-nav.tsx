/**
 * Adapted from ReactBits Gooey Nav (DOM/CSS particle implementation).
 * https://github.com/DavidHDev/react-bits/tree/c83b5e7e026f003af33ff9ebc3d93afb5c86ad22/src/ts-default/Components/GooeyNav
 * License and adaptation notes: ./react-bits-LICENSE.md
 */
import { useId, useLayoutEffect, useRef, type ReactNode } from 'react';
import { useMediaQuery } from '../../ui';
import './gooey-nav.css';

type Option<T extends string> = { value: T; label: string; icon?: ReactNode };

const noise = (amount: number) => amount / 2 - Math.random() * amount;
const particleCount = 12;
const animationTime = 600;
const timeVariance = 300;
const colors = [1, 2, 3, 1, 2, 3, 1, 4];

function getXY(distance: number, index: number) {
  const angle = ((360 + noise(8)) / particleCount) * index * (Math.PI / 180);
  return [distance * Math.cos(angle), distance * Math.sin(angle)];
}

/** ReactBits' radial particles, with each particle owning its animation lifetime. */
function makeParticles(element: HTMLSpanElement) {
  for (let index = 0; index < particleCount; index++) {
    const start = getXY(32, particleCount - index);
    const end = getXY(8 + noise(7), particleCount - index);
    const rotate = noise(10);
    const particle = document.createElement('span');
    const point = document.createElement('span');
    particle.className = 'gooey-nav__particle';
    point.className = 'gooey-nav__point';
    const properties = {
      '--start-x': `${start[0]}px`,
      '--start-y': `${start[1]}px`,
      '--end-x': `${end[0]}px`,
      '--end-y': `${end[1]}px`,
      '--time': `${animationTime * 2 + noise(timeVariance * 2)}ms`,
      '--scale': `${1 + noise(0.2)}`,
      '--color': `var(--gooey-color-${colors[Math.floor(Math.random() * colors.length)]})`,
      '--rotate': `${(rotate > 0 ? rotate + 5 : rotate - 5) * 10}deg`,
    };
    for (const [name, value] of Object.entries(properties)) particle.style.setProperty(name, value);
    particle.append(point);
    particle.addEventListener('animationend', (event) => {
      if (event.target === particle) particle.remove();
    });
    element.append(particle);
  }
}

export function GooeyNav<T extends string>({
  label,
  value,
  options,
  onChange,
  className = '',
}: {
  label: string;
  value: T;
  options: Option<T>[];
  onChange(value: T): void;
  className?: string;
}) {
  const filterId = `gooey-${useId().replace(/:/g, '')}`;
  const rootRef = useRef<HTMLElement>(null);
  const listRef = useRef<HTMLUListElement>(null);
  const effectRef = useRef<HTMLSpanElement>(null);
  const previousValue = useRef(value);
  const reduceMotion = useMediaQuery('(prefers-reduced-motion: reduce)');
  const activeIndex = options.findIndex((option) => option.value === value);
  // Translated labels can change without a change to the selected value or item count.
  const labels = JSON.stringify(options.map((option) => option.label));

  useLayoutEffect(() => {
    const root = rootRef.current;
    const list = listRef.current;
    const effect = effectRef.current;
    const selected = list?.children[activeIndex];
    if (!root || !list || !effect || !selected) return;

    let disposed = false;
    const measure = () => {
      const container = root.getBoundingClientRect();
      const item = selected.getBoundingClientRect();
      Object.assign(effect.style, {
        left: `${item.left - container.left}px`,
        top: `${item.top - container.top}px`,
        width: `${item.width}px`,
        height: `${item.height}px`,
      });
      root.dataset.ready = 'true';
    };
    measure();
    effect.replaceChildren();
    if (previousValue.current !== value && !reduceMotion) {
      effect.classList.remove('is-animating');
      void effect.offsetWidth;
      effect.classList.add('is-animating');
      makeParticles(effect);
    } else {
      effect.classList.remove('is-animating');
    }
    previousValue.current = value;

    const observer = new ResizeObserver(measure);
    observer.observe(root);
    for (const item of list.children) observer.observe(item);
    void document.fonts.ready.then(() => {
      if (!disposed) measure();
    });
    return () => {
      disposed = true;
      observer.disconnect();
      effect.replaceChildren();
    };
  }, [activeIndex, value, labels, reduceMotion]);

  return (
    <nav
      ref={rootRef}
      className={`gooey-nav ${className}`.trim()}
      aria-label={label}
      data-reduced-motion={reduceMotion ? 'true' : undefined}
    >
      <svg className="gooey-nav__defs" aria-hidden="true" focusable="false">
        <defs>
          <filter id={filterId} x="-100%" y="-200%" width="300%" height="500%">
            <feGaussianBlur in="SourceGraphic" stdDeviation="4" result="blur" />
            <feColorMatrix
              in="blur"
              type="matrix"
              values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 20 -8"
            />
          </filter>
        </defs>
      </svg>
      <span
        ref={effectRef}
        className="gooey-nav__effect"
        style={{ filter: `url("#${filterId}")` }}
        aria-hidden="true"
      />
      <ul
        ref={listRef}
        className="gooey-nav__list"
        onKeyDown={(event) => {
          if (event.altKey || event.ctrlKey || event.metaKey) return;
          const buttons = Array.from(event.currentTarget.querySelectorAll('button'));
          const index = buttons.indexOf(event.target as HTMLButtonElement);
          if (index < 0) return;
          let next: number;
          switch (event.key) {
            case 'ArrowRight':
              next = (index + 1) % options.length;
              break;
            case 'ArrowLeft':
              next = (index + options.length - 1) % options.length;
              break;
            case 'Home':
              next = 0;
              break;
            case 'End':
              next = options.length - 1;
              break;
            default:
              return;
          }
          event.preventDefault();
          buttons[next]?.focus();
          onChange(options[next]!.value);
        }}
      >
        {options.map((option) => (
          <li key={option.value}>
            <button
              type="button"
              className="gooey-nav__link"
              aria-current={value === option.value ? 'page' : undefined}
              onClick={() => {
                if (value !== option.value) onChange(option.value);
              }}
            >
              {option.icon}
              <span>{option.label}</span>
            </button>
          </li>
        ))}
      </ul>
    </nav>
  );
}
