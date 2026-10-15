# CLAUDE.md

> **Working name:** `halo` (placeholder; rename freely). CLI: `halo`, IPC socket: `$TMPDIR/halo.sock`.

## What this project is

A **Quickshell-like widget runtime for macOS**. Users write top-level desktop widgets (bars, floating panels, HUDs, OSDs, desktop widgets) in **TypeScript/TSX**. The runtime places them on screen as native, non-activating surfaces and keeps them in sync with reactive state.

Think of it as three things in one process:

1. **A compositor backend** that creates and configures top-level surfaces (level, Space behavior, shape, blur, input policy).
2. **A native render tree** (CALayers, laid out with Yoga flexbox, text through CoreText).
3. **A JavaScriptCore runtime** that runs user TSX with fine-grained signals. A changed signal updates exactly the layer properties that depend on it.

### Goals

- Declarative, stateful widgets in TSX, with hot reload on save.
- Precise placement: anchors to screen edges and corners, per-display instancing, awareness of safe areas, the notch, and the menu bar.
- Native rendering, low idle CPU, small memory footprint. No WebView per widget.
- A small set of built-in services, plus **external signals** that other tools push in.

### Non-goals (do not build these)

- **Not a window manager.** We don't tile, move, or react to other apps' windows.
- **No exclusive zones.** macOS can't reserve screen space. Bars overlay. Users set padding in their WM.
- **No interception of system UI:** notifications, other apps' menu-bar extras, the Dock, the system volume/brightness HUD. A halo OSD can react to volume changes, but the system HUD still appears.
- **No widgets over fullscreen apps.** Every surface, on every layer, is hidden while a fullscreen app is showing. Deliberate and not configurable.
- **No native multi-Space support.** Surfaces live on one Space. The target users run tiling WMs (AeroSpace and similar) that keep everything in a single Space. With several native Spaces, widgets only show on the Space they were created on; that's accepted, not a bug. This is also what keeps widgets out of fullscreen (verified on macOS 27): any panel with `.canJoinAllSpaces` shows over fullscreen apps at `aboveMenu`/`overlay`, even without `.fullScreenAuxiliary`, while single-Space panels are hidden by macOS itself.
- **No Spaces introspection of our own.** Workspace state comes from outside (AeroSpace and similar) through signals.
- No SwiftUI in the widget layer. AppKit/SwiftUI may be used for incidental host UI only, if any.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│ User config (TSX)  ── esbuild ──▶ JS bundle              │
├──────────────────────────────────────────────────────────┤
│ JS runtime (JavaScriptCore)                              │
│   signals · JSX → native node ops · timers · spawn · fs  │
├──────────────────────────────────────────────────────────┤
│ Render tree: Node (Yoga) ──▶ CALayer / CATextLayer       │
├──────────────────────────────────────────────────────────┤
│ Surface manager: Surface = anchor + level + space +      │
│                  input policy + root layer               │
├──────────────────────────────────────────────────────────┤
│ Compositor backend (protocol)                            │
│   PublicBackend (NSPanel)  │  SkyLightBackend (private)  │
├──────────────────────────────────────────────────────────┤
│ Environment: displays · safe areas · notch · menu bar    │
│ Services: battery · audio · network · clock · … (+priv.) │
│ IPC: Unix socket ◀── `halo` CLI ◀── AeroSpace, scripts   │
└──────────────────────────────────────────────────────────┘
```

### 1. Compositor backend

A Swift protocol so placement and rendering never touch window APIs directly:

- create/destroy a surface
- set frame, level, Space policy, shape/corner mask, background blur, shadow
- set input policy (passthrough / hover / interactive, **never** activating)
- `transaction { … }` to batch changes across many surfaces

**PublicBackend (default, required to be complete):** borderless `NSPanel` with `.nonactivatingPanel`, `ignoresMouseEvents` for passthrough, `isOpaque = false`, clear background, layer-backed content view. `collectionBehavior` is always `.stationary` + `.ignoresCycle`: one Space, unaffected by Mission Control, skipped by window cycling. Never `.canJoinAllSpaces` or `.fullScreenAuxiliary` (see Non-goals). Levels use `NSWindow.Level` / `CGWindowLevelForKey`. Batching goes through `CATransaction` plus `NSAnimationContext` with animations disabled.

**SkyLightBackend (optional, flagged private):** modeled on SketchyBar's `window.c` / `surface.c`. Raw `SLSNewWindowWithOpaqueShapeAndContext` windows, a private Space for true stickiness, `SLSTransaction*` for atomic multi-surface updates, and ordering groups. Build it only if the public backend proves insufficient for a concrete case. Keep it behind a compile flag.

### 2. Surfaces and placement

A `Surface` is configured declaratively from TSX:

| Property | Values |
|---|---|
| `screen` | a display id (usually supplied by `<PerScreen>`) |
| `anchor` | any combination of `top/bottom/left/right`; none = centered |
| `margins` | per-edge insets |
| `size` | fixed width/height, or `"fill"` along anchored axes |
| `layer` | `desktop` · `belowMenu` · `aboveMenu` · `overlay` |
| `input` | `passthrough` · `hover` · `interactive` |
| `avoid` | `notch`, `menuBar`: placement shifts around them |
| `visible` | bool (hidden surfaces are kept, not destroyed) |

Placement is a **pure function** `(SurfaceConfig, ScreenInfo) -> CGRect`. Unit-test it heavily. Note: AppKit's global coordinates are bottom-left origin, CoreGraphics' are top-left. Convert in exactly one place.

Layer mapping (initial, revisit after testing):

- `desktop` → `kCGDesktopIconWindowLevel + 1`
- `belowMenu` → `kCGBackstopMenuLevel` (SketchyBar's default)
- `aboveMenu` → `kCGStatusWindowLevel`
- `overlay` → `kCGPopUpMenuWindowLevel` or `kCGScreenSaverWindowLevel - 1`

### 3. Environment (public APIs only)

- Displays: `NSScreen.screens`, `NSApplication.didChangeScreenParametersNotification`, `CGDisplayRegisterReconfigurationCallback`
- Safe areas and notch: `NSScreen.safeAreaInsets`, `auxiliaryTopLeftArea`, `auxiliaryTopRightArea` (macOS 12+)
- Menu bar: `NSStatusBar.system.thickness`, plus `visibleFrame` vs `frame`. Auto-hide affects this.
- Appearance: `NSApp.effectiveAppearance` (light/dark), accent color

All of these are exposed to JS as signals (`screens()`, `screen.safeArea()`, `appearance()`).

### 4. Render tree

- JSX compiles to calls like `h(type, props, children)`. The runtime builds **native nodes** directly. No virtual DOM, no diffing.
- Each prop that's a signal or function becomes an effect that writes **one** native property. Static props are applied once.
- Primitives (start small):
  - `<Box>`: flexbox container with background, border, radius, padding, gap, opacity
  - `<Text>`: CoreText-backed, font family/size/weight, color, truncation
  - `<Image>`: file path, SF Symbol name, or app icon by bundle id
  - `<Shape>` (later): paths for graphs and progress rings
- Layout: **Yoga** (C API) owns the layout. After each layout pass, frames are pushed to CALayers inside one `CATransaction` with `setDisableActions(true)`.
- Styling is a **typed props object**, not CSS: `style={{ padding: 8, gap: 6, background: "#1e1e2e", radius: 8 }}`. Keep the vocabulary to what's in the table above until a real widget needs more.
- Animation: explicit only (`animate(signal, { duration, curve })` or a `transition` prop). Core Animation does the interpolation.
- Hit-testing: native, against layer frames. Events (`onClick`, `onScroll`, `onHover`) dispatch to JS. Surfaces with `input: passthrough` get none.

### 5. JS runtime

- **JavaScriptCore** (`JSContext`, `JSExport`), the public system framework. No bundled engine.
- **TS/TSX compilation:** esbuild, run by the host as a short-lived subprocess at load and reload. It's resolved from `HALO_ESBUILD`, then `PATH`, then `runtime/node_modules/.bin/esbuild` in dev. The host feeds esbuild a generated entry (`import { mount } from "halo/internal"` + the config's absolute `main.tsx`) and gets back one IIFE script; `halo` is aliased to `runtime/src`, so `halo/<module>` maps to `runtime/src/<module>.ts`. Not done yet: source maps (errors currently point at bundle lines; planned for M7).
- **Signals** (`runtime/src/signals.ts`): `signal`, `computed`, `effect`, `batch`, `untrack`, `onCleanup`, `root`, `getOwner`/`runWithOwner`. `signal(v)` returns an accessor with `.set` / `.update`. Glitch-free (mark DIRTY/CHECK, then pull), and effects re-collect dependencies on every run. No framework dependency. A throwing effect is logged and doesn't stop others. One JS tick produces one compositor commit because layout is coalesced per run-loop pass on the Swift side.
- **JSX** (`runtime/src/components.ts`): components run once, untracked. A function child is a reactive slot (`{() => list().map(...)}`) whose previous nodes are destroyed on re-run. Strings inside `<Box>` become `<Text>`. In `<Text>`, only function children are reactive: write `{() => `WS ${ws()}`}`, not `WS {ws()}`. Text styling (`color`, `fontSize`, `fontWeight`, `fontFamily`) lives in `style`. `<Image>` takes `symbol`, `app` (bundle id) or `file`, plus `size` and `color`. A `<Surface>` with exactly one node child uses it as its root (so it fills the surface); otherwise its children are wrapped in a `<Box>`.
- **Bridge** (`runtime/src/native.ts` ↔ `Sources/JSRuntime/Bridge.swift`): `globalThis.__native` with integer handles for nodes, surfaces and timers. Each `Runtime` (one per load) owns a fresh `JSContext` plus registries of everything it created. On reload it calls the config's root `dispose` first, logs anything still alive as a leak, then force-releases it.
- **Host APIs** JSC doesn't provide (all promise-based):
  - `setTimeout` / `setInterval` / `queueMicrotask`
  - `exec(cmd, args)` → `{ stdout, stderr, code }`, `sh(command)`. Not yet: `spawn` with streaming lines
  - Not yet: `readFile` / `watchFile` (add when a widget needs them)
  - `poll(cmd, intervalMs)` → signal (convenience)
  - `console.*` → host log
- **Hot reload:** watch the config dir, rebuild, dispose the old root (run all cleanups, tear down surfaces), mount the new one. Don't try to preserve state in v1.
- **Errors:** a throwing widget must not kill the runtime. Show an error surface or log entry and keep the others alive.

### 6. Services

Each service is a JS module exposing signals. It's backed by native code in Swift.

**Public (v1):** `clock`, `battery` (IOKit power sources), `audio` (CoreAudio default output volume and mute), `network` (`NWPathMonitor`: connectivity and interface type only. Wi-Fi SSID needs Location permission, which an unsigned plain executable can't request), `frontApp` (`NSWorkspace` notifications), `cpu`/`memory` (host stats).

Services are lazy: the native observer starts when a signal gets its first subscriber and stops when the last one is cleaned up.

**Gray zone:** undocumented but non-private mechanisms (IOKit registry keys like battery health, distributed notifications like `com.apple.screenIsLocked`, files like the Focus/DND assertions). These are normal services, not `halo/private`. Document them as "may return nothing" and never let them throw.

**Private (flagged, not in the MVP):** `nowPlaying` via MediaRemote. The MVP path for media is a user script pushing state with `halo trigger`. Since macOS 15.4, MediaRemote only answers entitled processes. The known workaround runs it through a system binary that still has the entitlement (see the `mediaremote-adapter` project). Verify the current state before implementing.

### 7. External signals and IPC

- One binary, `halo`. `halo start [--config <dir>]` runs the host in the foreground (also what `brew services` runs). Every other command is a thin client of the running host.
- Socket: `$TMPDIR/halo.sock` (per-user temp dir, `HALO_SOCKET` overrides it). Protocol (`Sources/IPC`): one JSON `Request` line per connection, answered with one JSON `Response` line. `halo start` refuses to run if a live host already answers there, and removes a stale socket file.
- `halo trigger <name> [key=value ...]` emits a named event with a string-map payload (split on the first `=`). The host keeps the latest payload per name, so a reloaded config starts from it.
- `externalSignal(name, { initial?, hydrate?, parse? })` (`halo/signals`) returns a signal of the latest parsed payload. `parse` returning `undefined` ignores that payload. `hydrate` is a shell command run on every load; its result arrives as `{ stdout, stderr, code }` and is dropped if a live event got there first.
- `halo/aerospace`: `aerospace()` gives `workspaces()`, `focused()` and `on(screen)`. It re-queries AeroSpace on every `aerospace.workspace` / `aerospace.focus` event, not by polling. Monitors map exactly through AeroSpace's `%{monitor-appkit-nsscreen-screens-id}` = `ScreenInfo.index` (1-based `NSScreen.screens` order); an unmatched one is logged, never guessed. Setup lives in `examples/aerospace/main.tsx`:
  ```toml
  exec-on-workspace-change = ['/bin/bash', '-c',
    'halo trigger aerospace.workspace focused=$AEROSPACE_FOCUSED_WORKSPACE prev=$AEROSPACE_PREV_WORKSPACE']
  on-focus-changed = ['exec-and-forget halo trigger aerospace.focus']   # optional: keeps "empty" fresh
  ```
- Other commands: `halo reload`, `halo quit` (disposes the config, removes the socket), `halo log` (`tail -F` of `$TMPDIR/halo.log`, truncated at each start). Not yet: `halo inspect` (M7).
- Socket I/O happens off the main thread and requests are handled on main. Sockets are `SO_NOSIGPIPE` and the host ignores SIGPIPE: a client that hangs up early must never kill it.

## Private API policy (important)

The MVP ships **no** private APIs. The rules below apply once one is added. `halo/private/*` and `PrivateBridges` don't exist yet. Known candidates for later: MediaRemote (now playing), SkyLight (custom blur radius; sticky surfaces only if native multi-Space support is ever wanted), DisplayServices (display brightness), CoreBrightness (keyboard backlight).

1. **Public by default.** Every core feature (surfaces, placement, rendering, IPC) must work with public APIs only.
2. **Private APIs are opt-in and visible at the import site:** `import { nowPlaying } from "halo/private/media"`. Never re-export private modules from public ones.
3. Native private code lives in its own target (`PrivateBridges`) with hand-written headers. Each function has a comment naming the macOS versions it was verified on.
4. **Fail soft:** a private service reports `{ available: false, reason }` instead of throwing or crashing. It probes availability at startup (`dlsym`, not hard linking).
5. Every private symbol used is listed in `docs/private-apis.md` with purpose, verified versions, and fallback.

## Example user config (target ergonomics)

```tsx
// ~/.config/halo/main.tsx
import { PerScreen, Surface, Box, Text } from "halo";
import { clock, battery } from "halo/services"; // battery: M5
import { externalSignal } from "halo/signals";

const time = clock.format("HH:mm");
const ws = externalSignal("aerospace.workspace", {
  hydrate: "aerospace list-workspaces --focused",
  parse: (p) => p.focused ?? p.stdout?.trim(),
});

export default () => (
  <PerScreen>
    {(screen) => (
      <Surface screen={screen} anchor={["top", "left", "right"]} size={{ height: 32 }}
               layer="belowMenu" input="interactive" avoid={["notch"]}>
        <Box style={{ flexDirection: "row", justify: "space-between", padding: [0, 10] }}>
          <Text>{() => `WS ${ws()}`}</Text>
          <Text>{() => `${battery.percent()}% · ${time()}`}</Text>
        </Box>
      </Surface>
    )}
  </PerScreen>
);
```

Treat this as a design target, not a frozen API. Update it here when the API changes.

## Tech stack and repo layout

- **Host:** Swift (SwiftPM), macOS 14+ minimum (revisit if needed). A single plain executable, `halo`, not a `.app`: `halo start` sets the `.accessory` activation policy, so it has no Dock icon and no app menu.
- **Distribution:** unsigned, via Homebrew. The formula builds from source (`swift build -c release`), depends on the `esbuild` formula, and ships a `brew services` launchd plist for launch at login. Anything that needs a TCC usage description or an entitlement is out of scope.
- **User config:** `$XDG_CONFIG_HOME/halo` (default `~/.config/halo`), entry `main.tsx`, imports between files allowed. `halo start --config <dir>` overrides it. Module-level code (top-level `clock.format`, `externalSignal`, `setInterval`…) runs inside the config's root scope, so a reload disposes it like component code.
- **Native deps:** Yoga (SwiftPM dependency on `facebook/yoga`, pinned exact; `import yoga`), esbuild (external, see JS runtime).
- **JS runtime library:** TypeScript, ships `.d.ts` so user configs get full type checking.

```
Package.swift
Sources/
  HaloCLI/           # the `halo` executable: argument parsing, `start` → HaloHost, other commands → socket client
  HaloHost/          # library: `runHost`, run loop, IPC server, config watcher, reload
  IPC/               # protocol (Request/Response/Command parsing) and Unix socket helpers, shared by both sides
  Compositor/        # Backend protocol, PublicBackend, Surface, placement
  Render/            # Node, Yoga bridge, CALayer mapping, text, hit-testing
  JSRuntime/         # JSContext setup, bridge, host APIs, esbuild invocation, logging
  Services/          # public services (M5)
  PrivateBridges/    # C/ObjC private API shims (opt-in, not created yet)
runtime/             # TS: reactive core, signals (+externalSignal), jsx-runtime, components, services, aerospace
examples/            # sample configs (bar, floating panel, OSD)
docs/                # private-apis.md, design notes
Tests/
```

## Build and run

- build: `swift build`
- run dev: `swift run halo start --config examples/demo` (or `examples/aerospace`, `examples/signals`; without `--config` it loads `$XDG_CONFIG_HOME/halo`). Edits under the config dir hot-reload; a failed build keeps the previous config running. Logs go to stderr and `$TMPDIR/halo.log`.
- control it: `swift run halo trigger <name> k=v`, `halo reload`, `halo quit`, `halo log`.
- tests: `swift test` (Swift Testing: placement math, render-tree invalidation, config lifecycle/reload leaks, external signals, IPC parsing; the JSRuntime suites need esbuild) and `cd runtime && bun test` (signal graph).

## Conventions

- Swift: no force-unwraps in runtime paths. All AppKit and Core Animation work happens on the main thread. Services may use background queues but publish to JS on main.
- Ownership: every native object created for JS (node, surface, effect, timer, subprocess) is tied to a scope and released in its cleanup. Reload must leave zero leaked surfaces or processes. Test this.
- Coordinate-space conversion happens only in `Compositor/Geometry.swift`.
- Inside a surface, layers use top-left coordinates because the panel's content view is a flipped `NSView`. Never set `isGeometryFlipped` on a view's backing layer: AppKit resets it. `CALayer.render(in:)` ignores flipping, so offscreen snapshots show mirrored layouts.
- Layers created for nodes have implicit animations disabled. Layout runs at most once per run-loop pass (`LayoutScheduler`), and only for roots whose Yoga tree is dirty.
- Performance budget: idle CPU ~0%, no polling unless the user asked for `poll`. A signal update triggers no layout unless a layout-affecting prop changed.
- Keep the TSX API small. Add a primitive or style prop only when an example widget needs it.
- Tests only where logic is subtle or regressions are silent: placement math, the signal graph and ownership, reload leaks, IPC parsing. No tests for thin AppKit/service wrappers or for coverage's sake. Check those by running an example.

## Milestones

1. **Static surface:** host agent shows a `PublicBackend` panel anchored top on every screen, correct level and Space behavior, survives display hot-plug.
2. **Render tree:** Box/Text/Image with Yoga layout, driven from Swift (no JS yet).
3. **JS runtime:** JSC + esbuild + signals + JSX mounting the same bar from TSX. Hot reload.
4. **IPC and external signals:** `halo trigger`, hydration, AeroSpace example.
5. **Services:** clock, battery, audio, network, frontApp.
6. **Input:** click, scroll, hover. Popup surfaces anchored to a node.
7. **Polish:** animation, error surface, `halo inspect`, typed docs, example gallery.
8. **(Optional, post-MVP) private:** `nowPlaying`; evaluate `SkyLightBackend` only if a concrete limitation is found.

## Open questions

- Font fallback and SF Symbols rendering inside `CATextLayer` vs custom CoreText drawing.

## References

- SketchyBar: `src/window.c`, `src/surface.c`, `src/layer.m` (SkyLight surfaces bound to a remote CALayer), `src/bar.c` (placement, notch, menu-bar avoidance), `src/sketchybar.c` (notify procs, Mach IPC). https://github.com/FelixKratz/SketchyBar
- Quickshell (QML: `PanelWindow`, `Variants`, reactive services): https://quickshell.org
- AGS/Astal (GJS + JSX + reactive bindings, closest model to ours)
- wlr-layer-shell protocol (layers, anchors, margins: the placement model borrowed here)
- simple-bar (Übersicht + React widgets, push updates from AeroSpace/yabai)
- Yoga: https://yogalayout.dev · SolidJS signals (reactivity model)
