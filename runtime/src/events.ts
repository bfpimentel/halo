import { reportError } from "./host";
import { native } from "./native";
import { batch, onCleanup } from "./reactive";

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

/// Routes native `kind` events for `id` to `handler` until the current owner is disposed.
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

export interface ClickEvent {
  x: number;
  y: number;
  button: "left" | "right";
  clicks: number;
}

export interface ScrollEvent {
  dx: number;
  dy: number;
}

export interface KeyEvent {
  /// "Enter", "Escape", "ArrowUp", "Tab", "Backspace", "Space"… or the typed character.
  key: string;
  shift: boolean;
  ctrl: boolean;
  alt: boolean;
  meta: boolean;
  repeat: boolean;
}

/// Same as `halo show|hide|toggle <name>` from the CLI.
export function show(name: string): void {
  native.setVisibility("show", name);
}

export function hide(name: string): void {
  native.setVisibility("hide", name);
}

export function toggle(name: string): void {
  native.setVisibility("toggle", name);
}
