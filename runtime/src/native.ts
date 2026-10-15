export interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface ScreenInfo {
  id: number;
  name: string;
  frame: Rect;
  scale: number;
  /// 1-based position in macOS's display list (AeroSpace's `monitor-appkit-nsscreen-screens-id`).
  index: number;
  menuBarHeight: number;
  notch: Rect | null;
}

export interface ExecResult {
  stdout: string;
  stderr: string;
  code: number;
}

/// Installed by the Swift host (`JSRuntime/Bridge.swift`). Ids are plain integers owned by the host.
export interface Native {
  log(level: "log" | "warn" | "error", message: string): void;
  createNode(kind: "box" | "text" | "image" | "input"): number;
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
  formatDate(pattern: string, epochMs: number): string;
  /// Starts or stops native delivery of `kind` events for a node or surface id.
  listen(id: number, kind: string, enabled: boolean): void;
  setVisibility(action: "show" | "hide" | "toggle", name: string): void;
  focus(id: number): void;
  /// Plays keyframes on a node; `done(finished)` fires when it ends or is cancelled. Returns a key for cancelling.
  animate(id: number, tracks: object, options: object, done: (finished: boolean) => void): string;
  cancelAnimation(id: number, key: string): void;
  /// Starts or stops `frame` events (display-link timestamps in ms) for a JS-allocated id.
  setFrames(id: number, enabled: boolean): void;
  /// Latest payload the host received for an external event, kept across reloads.
  lastEvent(name: string): Record<string, string> | null;
}

/// Functions the host calls into.
export interface HostHooks {
  onScreens?: (screens: ScreenInfo[]) => void;
  onEvent?: (name: string, payload: Record<string, string>) => void;
  dispose?: () => void;
  /// Returns true when a handler consumed the event (keys then don't reach the system / text field).
  dispatch?: (id: number, kind: string, payload: unknown) => boolean;
}

declare global {
  var __native: Native;
  var __halo: HostHooks;
}

export const native: Native = globalThis.__native;
