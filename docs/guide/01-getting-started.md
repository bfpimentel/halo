# Getting started

## Install

### Homebrew

Builds from source and needs Xcode 16+. Homebrew loads code only from taps you trust, so trust the halo formula once
([Tap Trust](https://docs.brew.sh/Tap-Trust)):

```bash
brew tap bfpimentel/tap
brew trust --formula bfpimentel/tap/halo   # Homebrew 6+: third-party taps need explicit trust
brew install halo
```

### Nix

The flake installs the prebuilt universal binary of the latest release, wrapped to use nixpkgs' esbuild. Add it as an
input:

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  halo = {
    url = "github:bfpimentel/halo";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

Then enable it in **one** of the modules. Each installs `halo` and runs `halo start` at login.

nix-darwin:

```nix
darwinConfigurations.my-mac = nix-darwin.lib.darwinSystem {
  modules = [
    halo.darwinModules.default
    { services.halo.enable = true; }
  ];
};
```

home-manager:

```nix
{ inputs, ... }:
{
  imports = [ inputs.halo.homeManagerModules.default ];
  services.halo.enable = true;
}
```

| Option                    | Default                          | Does                                   |
| ------------------------- | -------------------------------- | -------------------------------------- |
| `services.halo.enable`    | `false`                          | Install halo and add the launchd agent |
| `services.halo.package`   | the flake's `default` package    | The halo build to run                  |
| `services.halo.configDir` | `null` (`$XDG_CONFIG_HOME/halo`) | Passed to `halo start --config`        |

|               | nix-darwin       | home-manager                   |
| ------------- | ---------------- | ------------------------------ |
| launchd label | `org.nixos.halo` | `org.nix-community.home.halo`  |
| Agent output  | `halo log` only  | also `~/Library/Logs/halo.log` |

The agent restarts only after a crash, so `halo quit` keeps it stopped. Start it again with
`launchctl kickstart gui/$(id -u)/<label>`, or run `halo start` yourself.

Without the modules:

```bash
nix run github:bfpimentel/halo -- start              # try it
nix profile install github:bfpimentel/halo           # install, no agent
```

or `environment.systemPackages = [ halo.packages.${pkgs.system}.default ];` (`home.packages` in home-manager).

Update with `nix flake update halo` and rebuild: each release pins itself in the flake.

## Create a config

```bash
halo init
```

Creates `~/.config/halo` with a `halo.json`, a starter widget in `widgets/clock.tsx`, and a `tsconfig.json` that gives
your editor halo's types.

## Widgets and halo.json

A widget is a file in `widgets/` (`widgets/<name>.tsx`, or `widgets/<name>/index.tsx` when it spans several files).
`halo.json` lists what's on screen:

```json
{
  "widgets": {
    "bar": { "widget": "bar", "props": { "height": 32 } },
    "clock": { "widget": "clock", "screens": [1] },
    "clock-big": { "widget": "clock", "screens": [2], "props": { "size": 48 } }
  }
}
```

| Field     | Meaning                                                                                          |
| --------- | ------------------------------------------------------------------------------------------------ |
| key       | The instance's name, shown in errors. One widget can have several instances.                     |
| `widget`  | Required. The file in `widgets/` to mount.                                                       |
| `screens` | `"all"` (default), `"main"` (the menu-bar display) or 1-based display indices (`ScreenInfo.index`). |
| `props`   | JSON handed to the widget. Default `{}`.                                                         |

The widget's default export runs once per display it shows on and returns its surfaces:

```tsx
import { Surface, Text, type WidgetProps } from "halo";

export default ({ screen, props }: WidgetProps<{ size?: number }>) => (
  <Surface screen={screen} anchor={["top"]}>
    <Text style={{ fontSize: props.size ?? 22 }}>hello</Text>
  </Surface>
);
```

Share state between widgets through a module both import (its top-level code runs once). A widget that throws is
reported by name; the others keep running.

## Run

```bash
halo start
```

![The starter widget: a clock in the corner](../assets/starter.png)

Edits under the config folder reload on save. A build error keeps the previous version running and shows a panel in
the corner; runtime errors show there too, with your file and line. Full output: `halo log`.

## Settings

```bash
halo settings
```

With halo running, opens an editor for `halo.json` (run it again, press Esc or click Close to dismiss). Add instances from the widgets in
`widgets/`, rename, duplicate or remove them, pick their screens, and edit string, number and boolean props; nested
props stay in the file. Every change is saved at once, so the widgets reload as you edit. Text fields apply on Enter.

<video src="../assets/settings.mp4" autoplay loop muted playsinline aria-label="halo settings: editing a clock's format, size and color, then adding, renaming and removing instances"></video>

## Start at login

- Homebrew: `brew services start halo`
- Nix: `services.halo.enable = true` already adds a launchd agent.

## Next

- [Surfaces](surfaces.html): where widgets go.
- [Elements](elements.html): what's inside them.
- [Reactivity](reactivity.html): making them update.
