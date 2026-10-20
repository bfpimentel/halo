# Examples

Each one is recorded and shown with its full source in the [examples gallery](https://bfpimentel.github.io/halo/examples/index.html).

Run any of them with `swift run halo start --config examples/<name>` (or `halo start --config …` once installed).
Edits hot-reload.

| Example                            | Shows                                                                                                                                                                                                                                                                     |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`demo`](demo/halo.json)           | Five widgets in one `halo.json`: a top bar, a desktop clock (`defineWidget` props: formats and corner), an app dock (apps from `props`), an OSD that hides itself, and a load-average sparkline (`poll`, `computed`, reactive lists); colors shared through `theme.ts`.   |
| [`signals`](signals/halo.json)     | The reactive core on its own: a counter, derived values, a 20 Hz progress bar and a list rebuilt from a signal.                                                                                                                                                           |
| [`aerospace`](aerospace/halo.json) | AeroSpace spaces: each display's workspaces, the focused one highlighted, updated on every workspace change. `aerospace.ts` builds them from `halo trigger` events and `aerospace` queries; copy it into your config. The README has the `aerospace.toml` lines it needs. |
| [`launcher`](launcher/halo.json)   | Input: a keyboard-focused app launcher (`<Input>`, arrows/Enter/Esc, hover, click, enter/exit animation) toggled with `halo toggle launcher`, plus a corner button with a popup attached to it.                                                                           |
| [`shapes`](shapes/halo.json)       | `<Shape>`: a CPU progress ring (`ring()`, `track`, `strokeEnd` with a spring) with its percentage overlaid (`position: "absolute"`), a CPU history `sparkline`, and a plain SVG path.                                                                                     |
| [`io`](io/halo.json)               | Files and processes: a click counter saved across reloads (`readFile`/`writeFile`), a note followed with `watchFile` (edit it from a terminal), and live latency from a long-running `ping` (`spawn`).                                                                    |
| [`services`](services/halo.json)   | Every built-in service: a status strip (front app, CPU, memory, network, volume, battery) and a volume OSD that appears on changes; scroll the volume chip to adjust it.                                                                                                  |
| [`animation`](animation/halo.json) | Every animation layer, on timers: style transitions with springs, keyframes, enter/exit on list items and on a surface, layout transitions, and a JS `tween`.                                                                                                             |

Start your own with `halo init` (creates `~/.config/halo` with a `halo.json`, a starter widget and a `tsconfig.json` for editor types).

More widgets, shared by users: [Show and tell](https://github.com/bfpimentel/halo/discussions/categories/show-and-tell).
