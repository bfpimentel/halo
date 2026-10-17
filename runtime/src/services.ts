import { native } from "halo/native";
import {
  getOwner,
  onCleanup,
  signal,
  untrack,
  type Accessor,
  type Signal,
} from "halo/reactive";

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
    active.refs--;
    queueMicrotask(() => {
      if (active.refs > 0 || tickers.get(resolutionMs) !== active) return;
      native.clearTimer(active.timer);
      tickers.delete(resolutionMs);
    });
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

interface Subscription {
  state: Signal<Record<string, unknown> | undefined>;
  refs: number;
  id: number;
}

const subscriptions = new Map<string, Subscription>();

/**
 * Reads a native service's latest state, subscribing the current owner. The service runs while anyone reads
 * it; releases are checked a microtask later, so an effect that re-runs (release, then read again) never
 * restarts it.
 */
function read<T>(name: string, options: { intervalMs?: number } = {}): T | undefined {
  const key = options.intervalMs ? `${name}@${options.intervalMs}` : name;
  let entry = subscriptions.get(key);
  if (!entry) {
    entry = {
      state: signal<Record<string, unknown> | undefined>(undefined),
      refs: 0,
      id: 0,
    };
    subscriptions.set(key, entry);
  }
  const active = entry;
  if (getOwner()) {
    active.refs++;
    if (active.id === 0) {
      active.id = native.subscribeService(name, options, (state) =>
        active.state.set(state),
      );
    }
    onCleanup(() => {
      active.refs--;
      queueMicrotask(() => {
        if (active.refs > 0 || active.id === 0) return;
        native.unsubscribeService(active.id);
        active.id = 0;
      });
    });
  }
  return active.state() as T | undefined;
}

/** The internal battery. Every value is reactive. */
export interface Battery {
  /** Whether this Mac has a battery; the rest stays undefined when it doesn't. */
  present(): boolean;
  /** 0–100. */
  percent(): number | undefined;
  charging(): boolean | undefined;
  /** What powers the Mac now. */
  source(): "ac" | "battery" | undefined;
  /** Minutes to empty (or to full while charging), when macOS has an estimate. */
  minutesRemaining(): number | undefined;
}

interface BatteryState {
  present: boolean;
  percent?: number;
  charging?: boolean;
  source: "ac" | "battery";
  minutesRemaining: number | null;
}

/** The internal battery, from power-source notifications. */
export const battery: Battery = {
  present: () => read<BatteryState>("battery")?.present ?? false,
  percent: () => read<BatteryState>("battery")?.percent,
  charging: () => read<BatteryState>("battery")?.charging,
  source: () => read<BatteryState>("battery")?.source,
  minutesRemaining: () => read<BatteryState>("battery")?.minutesRemaining ?? undefined,
};

/** The default output device. Every value is reactive. */
export interface Audio {
  /** 0–1, or undefined when the device has no software volume (many HDMI/DisplayPort outputs). */
  volume(): number | undefined;
  muted(): boolean | undefined;
  /** The output device's name. */
  device(): string | undefined;
  /** Sets the volume (0–1); false when the device can't. */
  setVolume(volume: number): boolean;
  setMuted(muted: boolean): boolean;
  toggleMuted(): boolean;
}

interface AudioState {
  volume: number | null;
  muted: boolean;
  adjustable: boolean;
  device: string | null;
}

/** The default output device's volume and mute; follows device switches. */
export const audio: Audio = {
  volume: () => read<AudioState>("audio")?.volume ?? undefined,
  muted: () => read<AudioState>("audio")?.muted,
  device: () => read<AudioState>("audio")?.device ?? undefined,
  setVolume: (volume) => native.serviceAction("audio", "setVolume", volume),
  setMuted: (muted) => native.serviceAction("audio", "setMuted", muted),
  toggleMuted: () =>
    native.serviceAction(
      "audio",
      "setMuted",
      !untrack(() => read<AudioState>("audio")?.muted),
    ),
};

/** Network reachability. Every value is reactive. */
export interface Network {
  connected(): boolean | undefined;
  /** The interface in use; `"none"` when offline. */
  type(): "wifi" | "ethernet" | "cellular" | "other" | "none" | undefined;
  /** Metered, e.g. a phone hotspot. */
  expensive(): boolean | undefined;
  /** Low Data Mode is on. */
  constrained(): boolean | undefined;
}

interface NetworkState {
  connected: boolean;
  type: "wifi" | "ethernet" | "cellular" | "other" | "none";
  expensive: boolean;
  constrained: boolean;
}

/** Network reachability and interface type. No Wi-Fi name: that needs a Location permission halo can't ask for. */
export const network: Network = {
  connected: () => read<NetworkState>("network")?.connected,
  type: () => read<NetworkState>("network")?.type,
  expensive: () => read<NetworkState>("network")?.expensive,
  constrained: () => read<NetworkState>("network")?.constrained,
};

/** The frontmost app. Every value is reactive. */
export interface FrontApp {
  name(): string | undefined;
  /** Works with `<Image app={…}>` for its icon. */
  bundleId(): string | undefined;
  pid(): number | undefined;
}

interface FrontAppState {
  name: string | null;
  bundleId: string | null;
  pid: number;
}

/** The frontmost app, updated as you switch apps. */
export const frontApp: FrontApp = {
  name: () => read<FrontAppState>("frontApp")?.name ?? undefined,
  bundleId: () => read<FrontAppState>("frontApp")?.bundleId ?? undefined,
  pid: () => read<FrontAppState>("frontApp")?.pid,
};

/** CPU and memory, sampled every `intervalMs` (default 2000) while something reads them. */
export interface System {
  /** Busy share of all cores since the previous sample, 0–1. */
  cpu(intervalMs?: number): number | undefined;
  /** Used share of physical memory (active + wired + compressed), 0–1. */
  memory(intervalMs?: number): number | undefined;
  /** Used memory in bytes. */
  memoryUsed(intervalMs?: number): number | undefined;
  /** Physical memory in bytes. */
  memoryTotal(): number | undefined;
}

interface SystemState {
  cpu?: number;
  memory?: number;
  memoryUsed?: number;
  memoryTotal: number;
}

const sample = (intervalMs = 2000) => read<SystemState>("system", { intervalMs });

/** CPU and memory usage. */
export const system: System = {
  cpu: (intervalMs) => sample(intervalMs)?.cpu,
  memory: (intervalMs) => sample(intervalMs)?.memory,
  memoryUsed: (intervalMs) => sample(intervalMs)?.memoryUsed,
  memoryTotal: () => sample()?.memoryTotal,
};

/** Power state beyond the battery. Every value is reactive. */
export interface Power {
  /** Low Power Mode is on. */
  lowPowerMode(): boolean | undefined;
  /** How hot the Mac runs; anything above `"nominal"` means macOS is throttling. */
  thermal(): "nominal" | "fair" | "serious" | "critical" | undefined;
}

interface PowerState {
  lowPowerMode: boolean;
  thermal: "nominal" | "fair" | "serious" | "critical";
}

/** Low Power Mode and the thermal state, updated as they change. */
export const power: Power = {
  lowPowerMode: () => read<PowerState>("power")?.lowPowerMode,
  thermal: () => read<PowerState>("power")?.thermal,
};

/** The login session. Every value is reactive. */
export interface Session {
  /** The screen is locked. Uses undocumented macOS signals: may stay undefined on future versions. */
  locked(): boolean | undefined;
  /** The displays are asleep. */
  displaysAsleep(): boolean | undefined;
  /** When the Mac last woke from sleep (ms since epoch), since the service started. Changes on every wake. */
  lastWake(): number | undefined;
}

interface SessionState {
  locked: boolean | null;
  displaysAsleep: boolean;
  lastWake: number | null;
}

/** Screen lock, display sleep and wake from system sleep. */
export const session: Session = {
  locked: () => read<SessionState>("session")?.locked ?? undefined,
  displaysAsleep: () => read<SessionState>("session")?.displaysAsleep,
  lastWake: () => read<SessionState>("session")?.lastWake ?? undefined,
};

/** File drags anywhere on screen. Every value is reactive. */
export interface Drag {
  /** Files are being dragged right now, from Finder or any app. Show a drop zone while it's true. */
  active(): boolean;
}

/** File drags in progress, from mouse events and the drag pasteboard's type (its contents are never read). */
export const drag: Drag = {
  active: () => read<{ active: boolean }>("drag")?.active ?? false,
};
