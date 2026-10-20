/** A rectangle in points, top-left origin. */
export interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

/** A connected display, as `screens()` and `<PerScreen>` report it. */
export interface ScreenInfo {
  id: number;
  name: string;
  frame: Rect;
  scale: number;
  /** 1-based position in macOS's display list (AeroSpace's `monitor-appkit-nsscreen-screens-id`). */
  index: number;
  menuBarHeight: number;
  notch: Rect | null;
}

/** One entry of `readDir()`. */
export interface DirEntry {
  name: string;
  isDirectory: boolean;
}

/** What `exec()` and `sh()` resolve with. */
export interface ExecResult {
  stdout: string;
  stderr: string;
  code: number;
}

/** Installed by the Swift host (`JSRuntime/Bridge.swift`). Ids are plain integers owned by the host. */
export interface Native {
  log(level: "log" | "warn" | "error", message: string): void;
  createNode(kind: "box" | "text" | "image" | "input" | "shape"): number;
  setStyle(id: number, key: string, value: unknown): void;
  setProp(id: number, key: string, value: unknown): void;
  insert(parent: number, child: number, index: number): void;
  detach(id: number): void;
  destroyNode(id: number): void;
  createSurface(root: number, config: object): number;
  updateSurface(id: number, config: object): void;
  destroySurface(id: number): void;
  screens(): ScreenInfo[];
  setTimer(ms: number, repeats: boolean, fn: () => void): number;
  clearTimer(id: number): void;
  exec(command: string, args: string[], done: (result: ExecResult) => void): void;
  readFile(path: string, done: (text: string | null, error: string | null) => void): void;
  writeFile(path: string, text: string, done: (error: string | null) => void): void;
  readDir(
    path: string,
    done: (entries: DirEntry[] | null, error: string | null) => void,
  ): void;
  /** The `defineWidget` schemas of the config's loaded widgets, as JSON keyed by widget name. */
  publishSchemas(json: string): void;
  /** Tears down this runtime; only built-in apps (`halo settings`) do anything with it. */
  close(): void;
  /** Calls `onChange` now and whenever the contents change (null while the file doesn't exist). */
  watchFile(path: string, onChange: (text: string | null) => void): number;
  unwatchFile(id: number): void;
  /** Returns 0 if it couldn't start (`onExit` already got -1 and the reason). */
  spawn(
    command: string,
    args: string[],
    onLines: (stream: "out" | "err", lines: string[]) => void,
    onExit: (code: number, error: string | null) => void,
  ): number;
  kill(id: number): void;
  formatDate(pattern: string, epochMs: number): string;
  /** Starts or stops native delivery of `kind` events for a node or surface id. */
  listen(id: number, kind: string, enabled: boolean): void;
  setVisibility(action: "show" | "hide" | "toggle", name: string): void;
  focus(id: number): void;
  /** Plays keyframes on a node; `done(finished)` fires when it ends or is cancelled. Returns a key for cancelling. */
  animate(
    id: number,
    tracks: object,
    options: object,
    done: (finished: boolean) => void,
  ): string;
  cancelAnimation(id: number, key: string): void;
  /** Starts or stops `frame` events (display-link timestamps in ms) for a JS-allocated id. */
  setFrames(id: number, enabled: boolean): void;
  /** Starts (or joins) a native service; `onState` gets its state now and on every change. Returns an id. */
  subscribeService(
    name: string,
    options: object,
    onState: (state: Record<string, unknown>) => void,
  ): number;
  unsubscribeService(id: number): void;
  serviceAction(name: string, action: string, value: unknown): boolean;
  /** Latest payload the host received for an external event, kept across reloads. */
  lastEvent(name: string): Record<string, string> | null;
}

/** Functions the host calls into. */
export interface HostHooks {
  onScreens?: (screens: ScreenInfo[]) => void;
  onEvent?: (name: string, payload: Record<string, string>) => void;
  /** The user config's widget schemas (JSON keyed by widget name), delivered to `halo settings`. */
  onSchemas?: (json: string) => void;
  dispose?: () => void;
  /** Returns true when a handler consumed the event (keys then don't reach the system / text field). */
  dispatch?: (id: number, kind: string, payload: unknown) => boolean;
}

declare global {
  var __native: Native;
  var __halo: HostHooks;

  /** Timers and logging halo provides (JavaScriptCore has none); timers started in a component stop with it. */
  function setTimeout(
    fn: (...args: unknown[]) => void,
    ms?: number,
    ...args: unknown[]
  ): number;
  function setInterval(
    fn: (...args: unknown[]) => void,
    ms?: number,
    ...args: unknown[]
  ): number;
  function clearTimeout(id?: number): void;
  function clearInterval(id?: number): void;
  function queueMicrotask(fn: () => void): void;
  var console: {
    log(...values: unknown[]): void;
    info(...values: unknown[]): void;
    debug(...values: unknown[]): void;
    warn(...values: unknown[]): void;
    error(...values: unknown[]): void;
  };
}

export const native: Native = globalThis.__native;
