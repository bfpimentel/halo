import { reportError, sh } from "halo/host";
import { native } from "halo/native";
import { getOwner, onCleanup, signal, type Accessor } from "halo/reactive";

/** What `halo trigger <name> key=value ...` sends. Hydration results arrive as `{ stdout, stderr, code }`. */
export type Payload = Record<string, string>;

type Handler = (payload: Payload) => void;

const handlers = new Map<string, Set<Handler>>();

globalThis.__halo.onEvent = (name, payload) => {
  for (const handler of handlers.get(name) ?? []) handler(payload);
};

/** Options for `externalSignal()`. */
export interface ExternalSignalOptions<T> {
  initial?: T;
  /** Shell command run on load (and so after every reload) to get the current state before the first event. */
  hydrate?: string;
  /** Turns a payload into the signal's value; returning `undefined` ignores the payload. */
  parse?: (payload: Payload) => T | undefined;
}

/**
 * The latest value pushed with `halo trigger <name>`. Starts from the last payload the host saw,
 * then from `hydrate` — unless a live event arrives first.
 */
export function externalSignal<T = Payload>(
  name: string,
  options: ExternalSignalOptions<T> = {},
): Accessor<T | undefined> {
  const parse = options.parse ?? ((payload: Payload) => payload as unknown as T);
  const value = signal<T | undefined>(options.initial);
  const apply = (payload: Payload) => {
    try {
      const parsed = parse(payload);
      if (parsed !== undefined) value.set(parsed);
    } catch (error) {
      reportError(error);
    }
  };

  const last = native.lastEvent(name);
  if (last) apply(last);

  let liveEventSeen = false;
  const handler: Handler = (payload) => {
    liveEventSeen = true;
    apply(payload);
  };
  const set = handlers.get(name) ?? new Set();
  set.add(handler);
  handlers.set(name, set);
  if (getOwner()) onCleanup(() => set.delete(handler));

  if (options.hydrate) {
    const command = options.hydrate;
    sh(command).then((result) => {
      if (liveEventSeen) return;
      if (result.code !== 0) {
        console.warn(
          `externalSignal("${name}"): hydrate \`${command}\` exited ${result.code}: ${result.stderr.trim()}`,
        );
        return;
      }
      apply({ stdout: result.stdout, stderr: result.stderr, code: String(result.code) });
    });
  }
  return value;
}
