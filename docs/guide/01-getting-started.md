# Getting started

## Install

Homebrew (builds from source, needs Xcode 16+):

```bash
brew tap bfpimentel/halo https://github.com/bfpimentel/halo
brew install --HEAD halo
```

Nix (prebuilt), in your flake:

```nix
inputs.halo.url = "github:bfpimentel/halo";
# nix-darwin: modules = [ inputs.halo.darwinModules.default ];
# home-manager: imports = [ inputs.halo.homeManagerModules.default ];
services.halo.enable = true;
```

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
