import { reportError } from "halo/host";
import { native } from "halo/native";
import { batch, onCleanup } from "halo/reactive";

type Handler = (payload: never) => unknown;

const handlers = new Map<number, Map<string, Handler>>();

globalThis.__halo.dispatch = (id, kind, payload) => {
  const handler = handlers.get(id)?.get(kind);
  if (!handler) return false;
  try {
    return batch(() => (handler as (payload: unknown) => unknown)(payload)) === true;
  } catch (error) {
    reportError(error);
    return false;
  }
};

/** Registers a JS-side handler without asking the host to start delivering (for ids JS allocated itself). */
export function subscribe(id: number, kind: string, handler: Handler): () => void {
  const byKind = handlers.get(id) ?? new Map<string, Handler>();
  byKind.set(kind, handler);
  handlers.set(id, byKind);
  return () => {
    byKind.delete(kind);
    if (byKind.size === 0) handlers.delete(id);
  };
}

/** Routes native `kind` events for `id` to `handler` until the current owner is disposed. */
export function listen(id: number, kind: string, handler: Handler | undefined): void {
  if (!handler) return;
  const byKind = handlers.get(id) ?? new Map<string, Handler>();
  byKind.set(kind, handler);
  handlers.set(id, byKind);
  native.listen(id, kind, true);
  onCleanup(() => {
    native.listen(id, kind, false);
    byKind.delete(kind);
    if (byKind.size === 0) handlers.delete(id);
  });
}

/** Passed to `onClick`. `x`/`y` are surface-local points. */
export interface ClickEvent {
  x: number;
  y: number;
  button: "left" | "right";
  clicks: number;
}

/** Passed to `onDragEnter` and `onDrop`: the dragged files' paths (nothing is copied) and the surface-local point. */
export interface DropEvent {
  files: string[];
  x: number;
  y: number;
}

/** Passed to `onScroll`, in points. */
export interface ScrollEvent {
  dx: number;
  dy: number;
}

/** Passed to `onKeyDown`. */
export interface KeyEvent {
  /** "Enter", "Escape", "ArrowUp", "Tab", "Backspace", "Space"… or the typed character. */
  key: string;
  shift: boolean;
  ctrl: boolean;
  alt: boolean;
  meta: boolean;
  repeat: boolean;
}

/** Shows every surface named `name` (like `halo show <name>`). */
export function show(name: string): void {
  native.setVisibility("show", name);
}

/** Hides every surface named `name`. */
export function hide(name: string): void {
  native.setVisibility("hide", name);
}

/** Shows or hides every surface named `name`. */
export function toggle(name: string): void {
  native.setVisibility("toggle", name);
}
