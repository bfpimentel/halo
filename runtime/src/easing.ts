/// Pure curve math for JS-driven animation (`tween`). Native animations use Core Animation's own curves.

export type Curve =
  | "linear"
  | "ease-in"
  | "ease-out"
  | "ease-in-out"
  | "spring"
  | [x1: number, y1: number, x2: number, y2: number]
  | { stiffness?: number; damping?: number; mass?: number };

export interface Spring {
  stiffness: number;
  damping: number;
  mass: number;
}

export const defaultSpring: Spring = { stiffness: 300, damping: 26, mass: 1 };

const named: Record<string, [number, number, number, number]> = {
  linear: [0, 0, 1, 1],
  "ease-in": [0.42, 0, 1, 1],
  "ease-out": [0, 0, 0.58, 1],
  "ease-in-out": [0.42, 0, 0.58, 1],
};

/// The spring a curve describes, or undefined for time-based curves.
export function springOf(curve: Curve | undefined): Spring | undefined {
  if (curve === "spring") return defaultSpring;
  if (curve && typeof curve === "object" && !Array.isArray(curve)) return { ...defaultSpring, ...curve };
  return undefined;
}

/// Maps progress 0…1 to eased progress, CSS cubic-bezier semantics.
export function easing(curve: Curve | undefined = "ease-out"): (t: number) => number {
  const points = Array.isArray(curve) ? curve : named[curve as string] ?? named["ease-out"];
  return cubicBezier(...points);
}

export function cubicBezier(x1: number, y1: number, x2: number, y2: number): (t: number) => number {
  const sample = (a: number, b: number, t: number) => ((1 - 3 * b + 3 * a) * t + (3 * b - 6 * a)) * t * t + 3 * a * t;
  const slope = (a: number, b: number, t: number) => 3 * (1 - 3 * b + 3 * a) * t * t + 2 * (3 * b - 6 * a) * t + 3 * a;
  return (x) => {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    let t = x;
    for (let i = 0; i < 8; i++) {
      const error = sample(x1, x2, t) - x;
      if (Math.abs(error) < 1e-6) return sample(y1, y2, t);
      const d = slope(x1, x2, t);
      if (Math.abs(d) < 1e-6) break;
      t -= error / d;
    }
    let low = 0;
    let high = 1;
    t = x;
    while (high - low > 1e-6) {
      if (sample(x1, x2, t) < x) low = t;
      else high = t;
      t = (low + high) / 2;
    }
    return sample(y1, y2, t);
  };
}

/// One semi-implicit Euler step of a damped spring pulling `value` toward `target`. `dt` in seconds.
export function springStep(spring: Spring, value: number, velocity: number, target: number, dt: number): [number, number] {
  const steps = Math.max(1, Math.ceil(dt / (1 / 240)));
  const h = dt / steps;
  for (let i = 0; i < steps; i++) {
    const force = -spring.stiffness * (value - target) - spring.damping * velocity;
    velocity += (force / spring.mass) * h;
    value += velocity * h;
  }
  return [value, velocity];
}

export function settled(value: number, velocity: number, target: number): boolean {
  return Math.abs(value - target) < 1e-3 && Math.abs(velocity) < 1e-3;
}
