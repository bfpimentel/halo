# Examples

Run any of them with `swift run halo start --config examples/<name>` (or `halo start --config …` once installed).
Edits hot-reload.

| Example                           | Shows                                                                                                                                                                                                |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`demo`](demo/main.tsx)           | Five widgets on one display: a top bar, a desktop clock, an app launcher strip, an OSD that hides itself, and a load-average sparkline (`poll`, `computed`, reactive lists) split into its own file. |
| [`signals`](signals/main.tsx)     | The reactive core on its own: a counter, derived values, a 20 Hz progress bar and a list rebuilt from a signal.                                                                                      |
| [`aerospace`](aerospace/main.tsx) | A bar with live AeroSpace workspaces via `halo/aerospace` and `halo trigger`. The file header has the `aerospace.toml` lines it needs.                                                               |
| [`launcher`](launcher/main.tsx)   | Input: a keyboard-focused app launcher (`<Input>`, arrows/Enter/Esc, hover, click, enter/exit animation) toggled with `halo toggle launcher`, plus a corner button with a popup attached to it.      |
| [`animation`](animation/main.tsx) | Every animation layer, on timers: style transitions with springs, keyframes, enter/exit on list items and on a surface, layout transitions, and a JS `tween`.                                        |

Start your own with `halo init` (creates `~/.config/halo` with a starter `main.tsx` and a `tsconfig.json` for editor types).
