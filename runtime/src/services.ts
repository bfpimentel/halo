import { native } from "halo/native";
import { onCleanup, signal, type Accessor, type Signal } from "halo/reactive";

interface Ticker {
  now: Signal<number>;
  refs: number;
  timer: number;
}

const tickers = new Map<number, Ticker>();

/** One shared timer per resolution, aligned to its boundary, running only while something reads it. */
function ticker(resolutionMs: number): Accessor<number> {
  let entry = tickers.get(resolutionMs);
  if (!entry) {
    const created: Ticker = { now: signal(Date.now()), refs: 0, timer: 0 };
    const arm = () => {
      const now = Date.now();
      created.timer = native.setTimer(
        resolutionMs - (now % resolutionMs) + 5,
        false,
        () => {
          created.now.set(Date.now());
          arm();
        },
      );
    };
    arm();
    tickers.set(resolutionMs, created);
    entry = created;
  }
  const active = entry;
  active.refs++;
  onCleanup(() => {
    if (--active.refs > 0) return;
    native.clearTimer(active.timer);
    tickers.delete(resolutionMs);
  });
  return active.now;
}

/** The current time as reactive strings. */
export interface Clock {
  /**
   * The time formatted with a Unicode date pattern (`"HH:mm"`, `"EEE d MMM"`). Updates every minute, or every
   * second when the pattern shows seconds; stops when nothing reads it.
   */
  format(pattern: string): Accessor<string>;
}

/** The current time as reactive strings. */
export const clock: Clock = {
  format(pattern: string): Accessor<string> {
    const now = ticker(/s/.test(pattern.replace(/'[^']*'/g, "")) ? 1000 : 60_000);
    return () => native.formatDate(pattern, now());
  },
};
