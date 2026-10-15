import { describe, expect, test } from "bun:test";
import {
  batch,
  computed,
  effect,
  onCleanup,
  root,
  setErrorHandler,
  signal,
  untrack,
} from "halo/reactive";

describe("signals", () => {
  test("diamond dependencies run the effect once per change, never with mixed values", () => {
    const a = signal(1);
    const double = computed(() => a() * 2);
    const triple = computed(() => a() * 3);
    const seen: string[] = [];
    root(() => effect(() => seen.push(`${double()}/${triple()}`)));

    a.set(2);
    expect(seen).toEqual(["2/3", "4/6"]);
  });

  test("an unchanged computed value does not re-run its dependents", () => {
    const n = signal(1);
    const isEven = computed(() => n() % 2 === 0);
    let runs = 0;
    root(() =>
      effect(() => {
        isEven();
        runs++;
      }),
    );

    n.set(3);
    n.set(5);
    expect(runs).toBe(1);
    n.set(4);
    expect(runs).toBe(2);
  });

  test("a custom equals is only asked to compare real values, never the first run's missing one", () => {
    const list = signal([1, 2]);
    const compared: unknown[][] = [];
    const joined = computed(() => [...list()], {
      equals: (a, b) => (compared.push([a, b]), a.join() === b.join()),
    });
    let runs = 0;
    root(() =>
      effect(() => {
        joined();
        runs++;
      }),
    );

    list.set([1, 2]);
    expect(runs).toBe(1);
    expect(compared.every(([a]) => Array.isArray(a))).toBe(true);
    list.set([3]);
    expect(runs).toBe(2);
  });

  test("batch coalesces writes into one effect run", () => {
    const a = signal(0);
    const b = signal(0);
    const seen: number[] = [];
    root(() => effect(() => seen.push(a() + b())));

    batch(() => {
      a.set(1);
      b.set(2);
    });
    expect(seen).toEqual([0, 3]);
  });

  test("dependencies are re-collected on each run", () => {
    const useA = signal(true);
    const a = signal("a");
    const b = signal("b");
    const seen: string[] = [];
    root(() => effect(() => seen.push(useA() ? a() : b())));

    useA.set(false);
    a.set("a2");
    expect(seen).toEqual(["a", "b"]);
    b.set("b2");
    expect(seen).toEqual(["a", "b", "b2"]);
  });

  test("untrack reads without subscribing", () => {
    const tracked = signal(0);
    const ignored = signal(0);
    let runs = 0;
    root(() =>
      effect(() => {
        tracked();
        untrack(ignored);
        runs++;
      }),
    );

    ignored.set(1);
    expect(runs).toBe(1);
    tracked.set(1);
    expect(runs).toBe(2);
  });

  test("re-running an effect cleans up what its previous run owned", () => {
    const n = signal(0);
    const log: string[] = [];
    root(() =>
      effect(() => {
        const value = n();
        onCleanup(() => log.push(`cleanup ${value}`));
        effect(() => onCleanup(() => log.push(`inner cleanup ${value}`)));
      }),
    );

    n.set(1);
    expect(log).toEqual(["inner cleanup 0", "cleanup 0"]);
  });

  test("disposing a root runs every nested cleanup and stops its effects", () => {
    const n = signal(0);
    const log: string[] = [];
    let runs = 0;
    const dispose = root((dispose) => {
      onCleanup(() => log.push("root"));
      effect(() => {
        n();
        runs++;
        onCleanup(() => log.push("effect"));
      });
      root(() => onCleanup(() => log.push("nested root")));
      return dispose;
    });

    dispose();
    expect(log).toEqual(["nested root", "effect", "root"]);
    n.set(1);
    expect(runs).toBe(1);
  });

  test("a throwing effect does not stop other effects", () => {
    const n = signal(0);
    const errors: unknown[] = [];
    const seen: number[] = [];
    setErrorHandler((error: unknown) => errors.push(error));
    root(() => {
      effect(() => {
        if (n() === 1) throw new Error("boom");
      });
      effect(() => seen.push(n()));
    });

    n.set(1);
    expect(errors).toHaveLength(1);
    expect(seen).toEqual([0, 1]);
  });
});
