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

/**
 * Reads a UTF-8 file. `~` is your home folder; relative paths start at the config folder.
 * Rejects with the path and reason when it can't be read.
 */
export function readFile(path: string): Promise<string> {
  return new Promise((resolve, reject) =>
    native.readFile(path, (text, error) =>
      text === null ? reject(new Error(error ?? path)) : resolve(text),
    ),
  );
}

/**
 * Writes a UTF-8 file atomically, creating missing folders. Paths work like `readFile`'s.
 * Keep state outside the config folder (e.g. `~/.cache/…`): writes there reload the config.
 */
export function writeFile(path: string, text: string): Promise<void> {
  return new Promise((resolve, reject) =>
    native.writeFile(path, text, (error) =>
      error === null ? resolve() : reject(new Error(error)),
    ),
  );
}

/**
 * A file's contents as a signal, re-read whenever the file changes (including atomic saves and deletes).
 * `undefined` until the first read and while the file doesn't exist. Stops with its owner.
 */
export function watchFile(path: string): Accessor<string | undefined> {
  const contents = signal<string | undefined>(undefined);
  const id = native.watchFile(path, (text) => contents.set(text ?? undefined));
  if (getOwner()) onCleanup(() => native.unwatchFile(id));
  return contents;
}

/** Callbacks for `spawn`. Exceptions in them are reported, never thrown into the host. */
export interface SpawnOptions {
  /** Each line of stdout, without the newline. */
  onLine?: (line: string) => void;
  /** Each line of stderr. Unhandled stderr goes to the log as warnings. */
  onError?: (line: string) => void;
  /** The exit code (negative for a signal; -1 if it couldn't start). Not called after `kill()`. */
  onExit?: (code: number) => void;
}

/** A running `spawn`. */
export interface Spawned {
  /** Stops the program and everything it started. */
  kill(): void;
}

/**
 * Runs a long-lived program (no shell; use `"/bin/sh", ["-c", command]` for one) and streams its output line by line.
 * Killed with its owner, along with anything it started.
 */
export function spawn(
  command: string,
  args: string[] = [],
  options: SpawnOptions = {},
): Spawned {
  const call = (fn: ((value: never) => void) | undefined, value: unknown) => {
    if (!fn) return;
    try {
      (fn as (value: unknown) => void)(value);
    } catch (error) {
      reportError(error);
    }
  };
  let id = 0;
  id = native.spawn(
    command,
    args,
    (stream, lines) => {
      for (const line of lines) {
        if (stream === "out") call(options.onLine, line);
        else if (options.onError) call(options.onError, line);
        else native.log("warn", `${command}: ${line}`);
      }
    },
    (code, error) => {
      id = 0;
      if (error) native.log("warn", error);
      call(options.onExit, code);
    },
  );
  const kill = () => {
    if (id) native.kill(id);
    id = 0;
  };
  if (getOwner()) onCleanup(kill);
  return { kill };
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
