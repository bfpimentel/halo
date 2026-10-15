# Getting started

## Install

### Homebrew

Builds from source and needs Xcode 16+:

```bash
brew tap bfpimentel/halo https://github.com/bfpimentel/halo
brew install --HEAD halo
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

Creates `~/.config/halo/main.tsx` and a `tsconfig.json` that gives your editor halo's types. `main.tsx` default-exports
a component; everything it renders is on screen.

## Run

```bash
halo start
```

Edits under the config folder reload on save. A build error keeps the previous version running and shows a panel in
the corner; runtime errors show there too, with your file and line. Full output: `halo log`.

## Start at login

- Homebrew: `brew services start halo`
- Nix: `services.halo.enable = true` already adds a launchd agent.

## Next

- [Surfaces](surfaces.html): where widgets go.
- [Elements](elements.html): what's inside them.
- [Reactivity](reactivity.html): making them update.
