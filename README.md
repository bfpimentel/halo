<p align="center"><img src="docs/assets/logo.svg" alt="halo" height="64"></p>

<p align="center">Desktop widgets for macOS, written in TSX.</p>

<p align="center">
  <a href="https://bfpimentel.github.io/halo/">Website</a> ·
  <a href="https://bfpimentel.github.io/halo/guide/getting-started.html">Docs</a> ·
  <a href="https://bfpimentel.github.io/halo/reference/halo.html">API</a>
</p>

![Widgets made with halo](docs/assets/hero.png)

- **Native.** Core Animation layers and Yoga flexbox. No browser; ~0% CPU when idle.
- **Reactive.** Signals update exactly the properties that read them.
- **Batteries included.** Battery, volume, network, front app, CPU and memory as signals.
- **Scriptable.** `halo trigger` pushes state from your window manager or any script.

## Install

```bash
brew tap bfpimentel/halo https://github.com/bfpimentel/halo
brew install --HEAD halo
halo init     # ~/.config/halo with a starter widget and editor types
halo start
```

Nix: `inputs.halo.url = "github:bfpimentel/halo"`, then `services.halo.enable = true` in nix-darwin or
home-manager.

## Examples

### A clock in the corner

```tsx
import { Box, PerScreen, Surface, Text } from "halo";
import { clock } from "halo/services";

const time = clock.format("HH:mm");

export default () => (
  <PerScreen>
    {(screen) => (
      <Surface
        screen={screen}
        anchor={["bottom", "right"]}
        margins={[0, 16, 16, 0]}
        layer="desktop"
      >
        <Box style={{ padding: [10, 16], background: "#1e1e2ee0", radius: 12 }}>
          <Text style={{ fontSize: 22, fontWeight: "bold", color: "#cdd6f4" }}>
            {time}
          </Text>
        </Box>
      </Surface>
    )}
  </PerScreen>
);
```

### Interactive, animated

```tsx
import { Box, Surface, Text, screens } from "halo";
import { signal } from "halo/signals";

const on = signal(false);

export default () => (
  <Surface
    screen={screens()[0]}
    anchor={["top", "right"]}
    margins={[48, 16, 0, 0]}
    input="interactive"
  >
    <Box
      onClick={() => on.update((value) => !value)}
      style={{
        padding: [8, 14],
        radius: 10,
        background: () => (on() ? "#89b4fa" : "#313244"),
        scale: () => (on() ? 1.08 : 1),
        transition: { background: 150, scale: { curve: "spring" } },
      }}
    >
      <Text style={{ color: () => (on() ? "#11111b" : "#cdd6f4") }}>
        {() => (on() ? "On" : "Off")}
      </Text>
    </Box>
  </Surface>
);
```

### AeroSpace workspaces

```tsx
import { Box, PerScreen, Surface, Text } from "halo";
import { aerospace } from "halo/aerospace";

const spaces = aerospace();

export default () => (
  <PerScreen>
    {(screen) => (
      <Surface
        screen={screen}
        anchor={["top", "left", "right"]}
        size={{ height: 32 }}
        layer="belowMenu"
      >
        <Box
          style={{
            flexDirection: "row",
            align: "center",
            gap: 6,
            padding: [0, 10],
            background: "#1e1e2e",
          }}
        >
          {() =>
            spaces
              .on(screen)()
              .map((workspace) => (
                <Text style={{ color: workspace.focused ? "#89b4fa" : "#7f849c" }}>
                  {workspace.name}
                </Text>
              ))
          }
        </Box>
      </Surface>
    )}
  </PerScreen>
);
```

Point AeroSpace's `exec-on-workspace-change` at `halo trigger aerospace.workspace …`
([setup](https://bfpimentel.github.io/halo/guide/external-signals.html#aerospace)). More in
[`examples/`](examples/README.md).

## CLI

| Command                                                | Does                                     |
| ------------------------------------------------------ | ---------------------------------------- |
| `halo start [--config <dir>]`                          | Run widgets (default `~/.config/halo`)   |
| `halo init [<dir>]`                                    | Create a config with a starter widget    |
| `halo show\|hide\|toggle <name>`                       | Control named surfaces (bind to hotkeys) |
| `halo trigger <name> key=value …`                      | Push state to `externalSignal(name)`     |
| `halo reload`, `halo quit`, `halo log`, `halo inspect` | Manage the running host                  |

## Develop

```bash
swift build && swift run halo start --config examples/demo
swift test && (cd runtime && bun test)
nix develop -c oxlint runtime examples site    # lint; oxfmt formats
cd site && bun install && bun run build        # docs → site/dist
```

Releases: [`docs/releasing.md`](docs/releasing.md).
