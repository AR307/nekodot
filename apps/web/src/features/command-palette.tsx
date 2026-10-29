import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { motion, useReducedMotion } from 'motion/react';
import { Icon, Kbd, ease } from '../ui';
import type { Texts } from '../shared';

export type PaletteItem = {
  id: string;
  section: string;
  label: string;
  hint?: string;
  icon: ReactNode;
  keywords?: string;
  run(): void;
};

/** Keyboard-first jump list over bots, groups and app actions. */
export function CommandPalette({
  t,
  items,
  onClose,
}: {
  t: Texts;
  items: PaletteItem[];
  onClose(): void;
}) {
  const [query, setQuery] = useState('');
  const [index, setIndex] = useState(0);
  const listRef = useRef<HTMLDivElement>(null);
  const reduceMotion = useReducedMotion();
  const results = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return needle
      ? items.filter((item) =>
          [item.label, item.hint, item.keywords].join(' ').toLowerCase().includes(needle),
        )
      : items;
  }, [items, query]);
  const active = results[Math.min(index, results.length - 1)];

  useEffect(() => {
    listRef.current?.querySelector('[aria-selected="true"]')?.scrollIntoView({ block: 'nearest' });
  }, [active?.id]);

  function run(item: PaletteItem | undefined) {
    if (!item) return;
    onClose();
    item.run();
  }

  return (
    <motion.div
      className="palette-backdrop"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: 0.16 }}
    >
      <motion.div
        className="palette"
        role="dialog"
        aria-modal="true"
        aria-label={t.search}
        initial={reduceMotion ? { opacity: 0 } : { opacity: 0, y: -10, scale: 0.97 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        exit={reduceMotion ? { opacity: 0 } : { opacity: 0, y: -6, scale: 0.98 }}
        transition={{ duration: reduceMotion ? 0.1 : 0.2, ease }}
      >
        <label className="palette-search">
          <Icon name="search" />
          <input
            autoFocus
            role="combobox"
            aria-expanded="true"
            aria-controls="palette-results"
            aria-activedescendant={active ? 'palette-' + active.id : undefined}
            aria-label={t.searchPlaceholder}
            placeholder={t.searchPlaceholder}
            value={query}
            onChange={(event) => {
              setQuery(event.target.value);
              setIndex(0);
            }}
            onKeyDown={(event) => {
              if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
                event.preventDefault();
                const step = event.key === 'ArrowDown' ? 1 : -1;
                setIndex((current) => (current + step + results.length) % results.length);
              } else if (event.key === 'Enter') {
                event.preventDefault();
                run(active);
              } else if (event.key === 'Escape') {
                event.preventDefault();
                onClose();
              }
            }}
          />
          <Kbd>Esc</Kbd>
        </label>
        <div className="palette-results" id="palette-results" role="listbox" ref={listRef}>
          {results.map((item, position) => (
            <div key={item.id} role="presentation">
              {item.section !== results[position - 1]?.section && (
                <div className="palette-section" role="presentation">
                  {item.section}
                </div>
              )}
              <div
                id={'palette-' + item.id}
                role="option"
                aria-selected={item === active}
                className="palette-option"
                onMouseMove={() => setIndex(position)}
                onClick={() => run(item)}
              >
                {item === active && (
                  <motion.span
                    className="palette-highlight"
                    layoutId="palette-highlight"
                    transition={
                      reduceMotion
                        ? { duration: 0 }
                        : { type: 'spring', stiffness: 600, damping: 44 }
                    }
                  />
                )}
                <span className="palette-icon">{item.icon}</span>
                <span className="palette-label">{item.label}</span>
                {item.hint && <span className="palette-hint-text">{item.hint}</span>}
                {item === active && (
                  <span className="palette-enter">
                    <Icon name="enter" />
                  </span>
                )}
              </div>
            </div>
          ))}
          {!results.length && <p className="palette-empty">{t.noMatches}</p>}
        </div>
        <footer className="palette-footer">{t.paletteHint}</footer>
      </motion.div>
    </motion.div>
  );
}
