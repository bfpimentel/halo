import type { NativeNode } from "./components";
import { easing, settled, springOf, springStep, type Curve } from "./easing";
import { subscribe } from "./events";
import { native } from "./native";
import { effect, getOwner, onCleanup, signal, untrack, type Accessor } from "./reactive";

export type { Curve } from "./easing";

/// Milliseconds, or the full form. Springs ignore `duration` and settle on their own.
export type Timing = number | { duration?: number; curve?: Curve; delay?: number };

/// Every paint property that can animate.
export interface Animatable {
  opacity?: number;
  scale?: number;
  /// Degrees, clockwise.
  rotate?: number;
  translateX?: number;
  translateY?: number;
  background?: string;
  borderColor?: string;
  borderWidth?: number;
  radius?: number;
}

/// `style.transition`: per property, plus `all` (any paint property) and `layout` (position/size changes).
export type Transitions = { [K in keyof Animatable | "all" | "layout"]?: Timing };

export type EnterTransition = { from: Animatable; duration?: number; curve?: Curve; delay?: number };
export type ExitTransition = { to: Animatable; duration?: number; curve?: Curve; delay?: number };

export type KeyframeTracks = { [K in keyof Animatable]?: NonNullable<Animatable[K]>[] };

export interface KeyframeOptions {
  duration?: number;
  /// Cubic-bezier or named curves only; springs don't apply to keyframes.
  curve?: Curve;
  delay?: number;
  /// Number of runs; `Infinity` loops until cancelled.
  repeat?: number;
  /// Plays back and forth.
  alternate?: boolean;
  /// Position of each keyframe in 0…1 (defaults to evenly spaced).
  offsets?: number[];
  /// Keep the last frame once finished instead of returning to the style.
  fill?: boolean;
}

export interface Animation {
  cancel(): void;
  /// Resolves with `true` when it ran to the end, `false` when cancelled.
  finished: Promise<boolean>;
}

/// Plays keyframes on a node on top of its style, e.g. `animate(icon, { rotate: [0, 360] }, { duration: 800, repeat: Infinity, curve: "linear" })`.
/// Cancelled automatically when the calling component is disposed.
export function animate(node: NativeNode, tracks: KeyframeTracks, options: KeyframeOptions = {}): Animation {
  let resolve: (finished: boolean) => void = () => {};
  const finished = new Promise<boolean>((done) => (resolve = done));
  const wire = { ...options, repeat: options.repeat === Infinity ? Number.POSITIVE_INFINITY : options.repeat };
  const key = native.animate(node.id, tracks, wire, (done) => resolve(done));
  const cancel = () => native.cancelAnimation(node.id, key);
  if (getOwner()) onCleanup(cancel);
  return { cancel, finished };
}

let nextFrameID = -1;

/// Calls `callback(time, dt)` (milliseconds) on every display refresh until it returns `false` or its owner is disposed.
/// For anything Core Animation can't express. Returns a function that stops it.
export function onFrame(callback: (time: number, dt: number) => boolean | void): () => void {
  const id = nextFrameID--;
  let last: number | undefined;
  let stopped = false;
  const stop = () => {
    if (stopped) return;
    stopped = true;
    unsubscribe();
    native.setFrames(id, false);
  };
  const unsubscribe = subscribe(id, "frame", (time: number) => {
    const dt = last === undefined ? 0 : time - last;
    last = time;
    if (untrack(() => callback(time, dt)) === false) stop();
  });
  native.setFrames(id, true);
  if (getOwner()) onCleanup(stop);
  return stop;
}

/// A number that follows `target` smoothly: each change animates from wherever the value currently is.
/// Runs per frame in JS only while moving, e.g. `const shown = tween(() => count(), { duration: 400 })`.
export function tween(target: Accessor<number>, timing: Timing = 250): Accessor<number> {
  const options = typeof timing === "number" ? { duration: timing } : timing;
  const spring = springOf(options.curve);
  const ease = easing(spring ? undefined : options.curve);
  const duration = Math.max(1, options.duration ?? 250);
  const value = signal(untrack(target));
  let velocity = 0;
  let stop: (() => void) | undefined;

  effect(() => {
    const to = target();
    const from = untrack(value);
    if (from === to) return;
    stop?.();
    let elapsed = -(options.delay ?? 0);
    stop = onFrame((_, dt) => {
      elapsed += dt;
      if (elapsed < 0) return;
      if (spring) {
        let current = untrack(value);
        [current, velocity] = springStep(spring, current, velocity, to, dt / 1000);
        const done = settled(current, velocity, to);
        value.set(done ? to : current);
        return !done;
      }
      const progress = Math.min(1, elapsed / duration);
      value.set(from + (to - from) * ease(progress));
      return progress < 1;
    });
  });
  return value;
}
