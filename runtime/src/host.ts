import { native, type ExecResult } from "halo/native";
import {
  endScope,
  getOwner,
  onCleanup,
  runWithOwner,
  setErrorHandler,
  signal,
  type Accessor,
  type OwnerHandle,
} from "halo/reactive";

function format(value: unknown): string {
  if (value instanceof Error)
    return value.stack ? `${value.message}\n${value.stack}` : value.message;
  if (typeof value === "string") return value;
  try {
    return JSON.stringify(value) ?? String(value);
  } catch {
    return String(value);
  }
}

function logger(level: "log" | "warn" | "error") {
  return (...values: unknown[]) => native.log(level, values.map(format).join(" "));
}

export function reportError(error: unknown): void {
  native.log("error", format(error));
}

function guarded(fn: (...args: unknown[]) => void, args: unknown[]) {
  return () => {
    try {
      fn(...args);
    } catch (error) {
      reportError(error);
    }
  };
}

/** Timers started inside a component are cleared with it. */
function startTimer(ms: number, repeats: boolean, fn: () => void): number {
  const id = native.setTimer(Math.max(0, ms), repeats, fn);
  if (getOwner()) onCleanup(() => native.clearTimer(id));
  return id;
}

export function installGlobals(): void {
  const timers = {
    setTimeout: (fn: (...args: unknown[]) => void, ms = 0, ...args: unknown[]) =>
      startTimer(ms, false, guarded(fn, args)),
    setInterval: (fn: (...args: unknown[]) => void, ms = 0, ...args: unknown[]) =>
      startTimer(ms, true, guarded(fn, args)),
    clearTimeout: (id?: number) => id !== undefined && native.clearTimer(id),
    clearInterval: (id?: number) => id !== undefined && native.clearTimer(id),
    queueMicrotask: (fn: () => void) => void Promise.resolve().then(guarded(fn, [])),
  };
  Object.assign(globalThis, timers, {
    console: {
      log: logger("log"),
      info: logger("log"),
      debug: logger("log"),
      warn: logger("warn"),
      error: logger("error"),
    },
  });
  setErrorHandler(reportError);
}

/** Runs a program with arguments (no shell) and resolves with its output. */
export function exec(command: string, args: string[] = []): Promise<ExecResult> {
  return new Promise((resolve) => native.exec(command, args, resolve));
}

/** Runs a command with `/bin/sh -c` and resolves with its output. */
export function sh(command: string): Promise<ExecResult> {
  return exec("/bin/sh", ["-c", command]);
}

/** Runs a shell command every `intervalMs` and exposes its trimmed stdout. Stops with its owner. */
export function poll(
  command: string,
  intervalMs: number,
  initial = "",
): Accessor<string> {
  const output = signal(initial);
  let stopped = false;
  const run = () =>
    sh(command).then((result) => {
      if (stopped) return;
      output.set(result.stdout.trim());
      timer = native.setTimer(intervalMs, false, run);
    });
  let timer = native.setTimer(0, false, run);
  onCleanup(() => {
    stopped = true;
    native.clearTimer(timer);
  });
  return output;
}

/** `scope` was opened before the config's modules ran, so it owns their top-level effects and timers too. */
export function mount(scope: OwnerHandle, app: unknown): void {
  globalThis.__halo.dispose = () => scope.dispose();
  runWithOwner(scope, () => {
    try {
      if (typeof app === "function") app();
    } catch (error) {
      reportError(error);
    }
  });
  endScope();
}
