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

**PublicBackend (default, required to be complete):** borderless `NSPanel` with `.nonactivatingPanel`, `ignoresMouseEvents` for passthrough, `isOpaque = false`, clear background, layer-backed content view. Space policy maps onto `collectionBehavior` (`.canJoinAllSpaces`, `.stationary`, `.fullScreenAuxiliary`, `.ignoresCycle`). Levels use `NSWindow.Level` / `CGWindowLevelForKey`. Batching goes through `CATransaction` plus `NSAnimationContext` with animations disabled.

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
| `spaces` | `all` · `current` (follows the active Space) |
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
- **TS/TSX compilation:** esbuild, run by the host as a short-lived subprocess at load and reload. It's resolved from `HALO_ESBUILD`, then `PATH`, then `runtime/node_modules/.bin/esbuild` in dev. Output is one ESM bundle per config. Source maps are on so errors point to the user's `.tsx` lines.
- **Signals:** a small in-house implementation (`signal`, `computed`, `effect`, `batch`, `untrack`, `onCleanup`) in Solid's style. No framework dependency. `batch` also wraps the native transaction so one JS tick produces one compositor commit.
- **Host APIs** JSC doesn't provide (all promise-based):
  - `setTimeout` / `setInterval` / `queueMicrotask`
  - `exec(cmd, args)` → `{ stdout, stderr, code }`; `spawn` with streaming lines
  - `readFile` / `watchFile`
  - `poll(cmd, intervalMs)` → signal (convenience)
  - `console.*` → host log
- **Hot reload:** watch the config dir, rebuild, dispose the old root (run all cleanups, tear down surfaces), mount the new one. Don't try to preserve state in v1.
- **Errors:** a throwing widget must not kill the runtime. Show an error surface or log entry and keep the others alive.

### 6. Services

Each service is a JS module exposing signals. It's backed by native code in Swift.

**Public (v1):** `clock`, `battery` (IOKit power sources), `audio` (CoreAudio default output volume and mute), `network` (`NWPathMonitor`: connectivity and interface type only. Wi-Fi SSID needs Location permission, which an unsigned plain executable can't request), `frontApp` (`NSWorkspace` notifications), `cpu`/`memory` (host stats).

Services are lazy: the native observer starts when a signal gets its first subscriber and stops when the last one is cleaned up.

**Gray zone:** undocumented but non-private mechanisms (IOKit registry keys like battery health, distributed notifications like `com.apple.screenIsLocked`, files like the Focus/DND assertions). These are normal services, not `halo:private`. Document them as "may return nothing" and never let them throw.

**Private (flagged, not in the MVP):** `nowPlaying` via MediaRemote. The MVP path for media is a user script pushing state with `halo trigger`. Since macOS 15.4, MediaRemote only answers entitled processes. The known workaround runs it through a system binary that still has the entitlement (see the `mediaremote-adapter` project). Verify the current state before implementing.

### 7. External signals and IPC

- The host listens on a Unix domain socket. The `halo` CLI is a thin client.
- `halo trigger <name> [key=value ...]` emits a named event with a string-map payload. In JS, `externalSignal(name, { initial?, hydrate? })` returns a signal of the latest payload.
- `hydrate` is a shell command run on load and after reload, so state is correct before the first event arrives.
- Example, AeroSpace (`~/.aerospace.toml`):
  ```toml
  exec-on-workspace-change = ['/bin/bash', '-c',
    'halo trigger aerospace.workspace focused=$AEROSPACE_FOCUSED_WORKSPACE prev=$AEROSPACE_PREV_WORKSPACE']
  ```
  with `hydrate: "aerospace list-workspaces --focused"` and `"aerospace list-workspaces --all"`.
- AeroSpace monitor ids don't match `NSScreen` ids. Provide a helper that maps them by name or frame. Don't guess silently.
- Other CLI commands: `halo reload`, `halo quit`, `halo log` (tail), `halo inspect` (dump surfaces and node tree as JSON, for debugging).

## Private API policy (important)

The MVP ships **no** private APIs. The rules below apply once one is added. `halo:private/*` and `PrivateBridges` don't exist yet. Known candidates for later: MediaRemote (now playing), SkyLight (sticky surfaces, custom blur radius), DisplayServices (display brightness), CoreBrightness (keyboard backlight).

1. **Public by default.** Every core feature (surfaces, placement, rendering, IPC) must work with public APIs only.
2. **Private APIs are opt-in and visible at the import site:** `import { nowPlaying } from "halo:private/media"`. Never re-export private modules from public ones.
3. Native private code lives in its own target (`PrivateBridges`) with hand-written headers. Each function has a comment naming the macOS versions it was verified on.
4. **Fail soft:** a private service reports `{ available: false, reason }` instead of throwing or crashing. It probes availability at startup (`dlsym`, not hard linking).
5. Every private symbol used is listed in `docs/private-apis.md` with purpose, verified versions, and fallback.

## Example user config (target ergonomics)

```tsx
// ~/.config/halo/main.tsx
import { PerScreen, Surface, Box, Text } from "halo";
import { clock, battery } from "halo:services";
import { externalSignal } from "halo:signals";

const ws = externalSignal("aerospace.workspace", {
  hydrate: "aerospace list-workspaces --focused",
  parse: (p) => p.focused ?? p.stdout?.trim(),
});

export default () => (
  <PerScreen>
    {(screen) => (
      <Surface screen={screen} anchor={["top", "left", "right"]} size={{ height: 32 }}
               layer="belowMenu" spaces="all" input="interactive" avoid={["notch"]}>
        <Box style={{ flexDirection: "row", justify: "space-between", padding: [0, 10] }}>
          <Text>{() => `WS ${ws()}`}</Text>
          <Text>{() => `${battery.percent()}% · ${clock.format("HH:mm")()}`}</Text>
        </Box>
      </Surface>
    )}
  </PerScreen>
);
```

Treat this as a design target, not a frozen API. Update it here when the API changes.

## Tech stack and repo layout

- **Host:** Swift (SwiftPM), macOS 14+ minimum (revisit if needed). A plain executable, not a `.app`: it sets the `.accessory` activation policy at startup, so it has no Dock icon and no app menu.
- **Distribution:** unsigned, via Homebrew. The formula builds from source (`swift build -c release`), depends on the `esbuild` formula, and ships a `brew services` launchd plist for launch at login. Anything that needs a TCC usage description or an entitlement is out of scope.
- **User config:** `$XDG_CONFIG_HOME/halo` (default `~/.config/halo`), entry `main.tsx`, imports between files allowed. `--config <dir>` overrides it.
- **Native deps:** Yoga (vendored C sources), esbuild (external, see JS runtime).
- **JS runtime library:** TypeScript, ships `.d.ts` so user configs get full type checking.

```
Package.swift
Sources/
  HaloHost/          # entry point, run loop, IPC server, reload
  Compositor/        # Backend protocol, PublicBackend, Surface, placement
  Render/            # Node, Yoga bridge, CALayer mapping, text, hit-testing
  JSRuntime/         # JSContext setup, host APIs, module loader, esbuild invocation
  Services/          # public services
  PrivateBridges/    # C/ObjC private API shims (opt-in)
  HaloCLI/           # `halo` client
runtime/             # TS: jsx-runtime, signals, primitives, service typings
examples/            # sample configs (bar, floating panel, OSD)
docs/                # private-apis.md, design notes
Tests/
```

## Build and run

- build: `swift build`
- run dev: `swift run halo-host` (M1: draws a static bar on every display; `--config <dir>` arrives with the JS runtime)
- tests: `swift test` (Swift Testing; placement math so far). `runtime/` tests will use `bun test`.

## Conventions

- Swift: no force-unwraps in runtime paths. All AppKit and Core Animation work happens on the main thread. Services may use background queues but publish to JS on main.
- Ownership: every native object created for JS (node, surface, effect, timer, subprocess) is tied to a scope and released in its cleanup. Reload must leave zero leaked surfaces or processes. Test this.
- Coordinate-space conversion happens only in `Compositor/Geometry.swift`.
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

- Does `NSPanel` + `.canJoinAllSpaces` + `.stationary` behave correctly over fullscreen apps and during Mission Control on current macOS? If not, that's the first real case for the SkyLight backend.
- Font fallback and SF Symbols rendering inside `CATextLayer` vs custom CoreText drawing.

## References

- SketchyBar: `src/window.c`, `src/surface.c`, `src/layer.m` (SkyLight surfaces bound to a remote CALayer), `src/bar.c` (placement, notch, menu-bar avoidance), `src/sketchybar.c` (notify procs, Mach IPC). https://github.com/FelixKratz/SketchyBar
- Quickshell (QML: `PanelWindow`, `Variants`, reactive services): https://quickshell.org
- AGS/Astal (GJS + JSX + reactive bindings, closest model to ours)
- wlr-layer-shell protocol (layers, anchors, margins: the placement model borrowed here)
- simple-bar (Übersicht + React widgets, push updates from AeroSpace/yabai)
- Yoga: https://yogalayout.dev · SolidJS signals (reactivity model)
