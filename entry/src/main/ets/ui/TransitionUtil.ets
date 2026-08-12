import { curves, display } from '@kit.ArkUI';

/**
 * Minimum fade-transition duration in milliseconds, keyed by display diagonal.
 *
 *  - < 8.5 inches  -> 200 ms (phone-class devices)
 *  - 8.5 ~ 12 inches -> 250 ms (small tablet / foldable inner)
 *  - > 12 inches  -> 300 ms (tablet / large foldable)
 */
let cachedMs: number = -1;

export function transitionDurationMs(): number {
  if (cachedMs > 0) {
    return cachedMs;
  }
  try {
    const d = display.getDefaultDisplaySync();
    const dpi = Math.max(1, d.densityDPI);
    const widthInch = d.width / dpi;
    const heightInch = d.height / dpi;
    const diagonal = Math.sqrt(widthInch * widthInch + heightInch * heightInch);
    if (diagonal > 12) {
      cachedMs = 300;
    } else if (diagonal >= 8.5) {
      cachedMs = 250;
    } else {
      cachedMs = 200;
    }
  } catch (e) {
    cachedMs = 200;
  }
  return cachedMs;
}

/**
 * Pure fade-in/out transition effect with a spring curve, no positional translation.
 * Designed to be attached via .transition(...) on the root component of an if/else branch.
 */
export function fadeTransition(): TransitionEffect {
  return TransitionEffect.OPACITY.animation({
    duration: transitionDurationMs(),
    curve: curves.springCurve(0.4, 1.0, 0.34, 1.0)
  });
}