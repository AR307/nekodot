import { useReducedMotion, type Transition } from 'motion/react';

/**
 * Motion and layout tokens for components animated with motion/react. CSS reads the same
 * values from styles/tokens.css; design-system.test.ts keeps the two identical.
 * Source: design/08-motion.png and design/09-tokens.png.
 */

/** Seconds. Exits use the next shorter step than their entrance. */
export const durations = {
  instant: 0.08,
  fast: 0.16,
  base: 0.22,
  panel: 0.28,
  slow: 0.45,
  sway: 0.6,
  cycle: 1,
  breathe: 1.2,
  pulse: 1.4,
  scan: 1.6,
  shimmer: 2,
  ambient: 20,
} as const;
export type Step = 'instant' | 'fast' | 'base' | 'panel' | 'slow';

/** The single curve from the design board, for every entrance and movement. */
export const ease = [0.2, 0.8, 0.2, 1] as const;
/** Overshoot for confirmations such as a successful pairing (scale .6 → 1.08 → 1). */
export const easePop = [0.34, 1.4, 0.64, 1] as const;
/** Accelerating exit for things that leave and do not come back (particles, dismissals). */
export const easeExit = [0.55, 0, 1, 0.45] as const;
/** Pixel offsets: avatar hop, message rise, relay label slide. */
export const shift = { 1: 4, 2: 8, 3: 12 } as const;
/** Delay between list items; only the first six items are staggered. */
export const stagger = 0.03;
export const staggerLimit = 6;
/** Tool card finish/expand and shared layout movement (design board: spring 400/32). */
export const spring = { type: 'spring', stiffness: 400, damping: 32 } as const;
/** Playful confirmation: picked avatars, pairing success. */
export const springPop = { type: 'spring', stiffness: 420, damping: 18 } as const;

/** Phone ≤ 767, tablet 768–1023, desktop 1024–1279, wide ≥ 1280 (min-width values). */
export const breakpoints = { tablet: 768, desktop: 1024, wide: 1280 } as const;
export const media = {
  phone: `(max-width: ${breakpoints.tablet - 1}px)`,
  belowDesktop: `(max-width: ${breakpoints.desktop - 1}px)`,
  belowWide: `(max-width: ${breakpoints.wide - 1}px)`,
} as const;

/** For element.animate(): milliseconds and the CSS form of the shared curve. */
export const ms = (step: keyof typeof durations) => durations[step] * 1000;
export const easeCss = `cubic-bezier(${ease.join(', ')})`;

const instant: Transition = { duration: durations.instant };

/** Shared-curve tween; with reduced motion every step collapses to a short fade. */
export function tween(step: Step, reduce: boolean | null, delay = 0): Transition {
  return reduce ? instant : { duration: durations[step], ease, delay };
}

/** Spring for layout movement and expanding cards; reduced motion gets the instant fade. */
export function springy(reduce: boolean | null, kind: 'spring' | 'pop' = 'spring'): Transition {
  return reduce ? instant : kind === 'pop' ? springPop : spring;
}

/** Transitions that already respect the person's reduced-motion setting. */
export function useMotion() {
  const reduce = useReducedMotion() ?? false;
  return {
    reduce,
    tween: (step: Step, delay = 0) => tween(step, reduce, delay),
    spring: reduce ? instant : spring,
    springPop: reduce ? instant : springPop,
    pop: reduce ? instant : ({ duration: durations.slow, ease: easePop } as Transition),
    /** Vertical entrance offset; none with reduced motion. */
    rise: (step: keyof typeof shift = 2) => (reduce ? 0 : shift[step]),
  };
}
