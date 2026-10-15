# Releasing

halo ships two ways:

- **Homebrew**: a formula in this repository that builds from source.
- **Nix**: a flake that installs the prebuilt release zip.

The zip comes from the release workflow ([`.github/workflows/release.yml`](../.github/workflows/release.yml)), which runs [`scripts/package.sh`](../scripts/package.sh) on every `v*` tag. The script builds a universal binary and writes `halo-<version>-macos.zip`. The zip contains `bin/halo`, `share/halo/runtime/src` and `share/halo/examples`.

## Homebrew

The formula lives at [`Formula/halo.rb`](../Formula/halo.rb), so the repository is its own tap:

```bash
brew tap bfpimentel/halo https://github.com/bfpimentel/halo
brew install --HEAD halo     # before the first tagged release
brew install halo            # once the formula has a stable url
brew services start halo     # launch at login (LaunchAgent running `halo start`)
```

### What the formula installs

| Path | Contents |
|---|---|
| `bin/halo` | the single binary (`swift build -c release --product halo`) |
| `share/halo/runtime/src` | the TS runtime; `Bundler.locate` finds it next to the real (symlink-resolved) binary |
| `share/halo/examples` | the example configs |

`halo init` writes `opt/halo/...` paths (not the versioned Cellar path) into the user's `tsconfig.json`, so editor
types survive upgrades. esbuild comes from the `esbuild` formula; launchd's minimal `PATH` is covered by the
service's `std_service_path_env` and by `Bundler`'s fallback search of `/opt/homebrew/bin` and `/usr/local/bin`.

## Nix

Use the flake in your nix-darwin or home-manager configuration:

```nix
{
  inputs.halo.url = "github:bfpimentel/halo";

  # nix-darwin
  modules = [ inputs.halo.darwinModules.default { services.halo.enable = true; } ];

  # or home-manager
  imports = [ inputs.halo.homeManagerModules.default ];
  services.halo.enable = true;   # optional: services.halo.configDir = "/Users/me/widgets";
}
```

Either module installs `halo` and adds a launchd agent that runs `halo start` at login. The agent restarts only after a crash, so `halo quit` keeps it stopped.

The package itself is `packages.<system>.default`. It downloads the release zip pinned in [`nix/release.json`](../nix/release.json), checks its hash, and wraps `halo` so it uses nixpkgs' esbuild. Nix downloads don't get the quarantine flag, so the unsigned binary runs as is. To work on halo, `nix develop` gives you esbuild and bun.

Until the first release exists, `nix/release.json` has an empty hash, and building fails with a hash mismatch.

## Cutting a release

1. Bump `IPC.version` in `Sources/IPC/Protocol.swift`, commit, tag `vX.Y.Z` and push the tag. The workflow builds the zip and publishes the GitHub release.
2. Point the flake at the new release with `scripts/bump-nix.sh X.Y.Z`. It writes the version and hash to `nix/release.json`. Commit that file.
3. For Homebrew, get the source tarball checksum:
   ```bash
   curl -sL https://github.com/bfpimentel/halo/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256
   ```
4. Add this to the formula, above `head`:
   ```ruby
   url "https://github.com/bfpimentel/halo/archive/refs/tags/vX.Y.Z.tar.gz"
   sha256 "<checksum>"
   ```
5. Commit the formula change. Users then get the new version with `brew update && brew upgrade halo`.

## Checking the packages

Build the zip locally with `scripts/package.sh`. To test the Nix package against a local zip, serve `dist/` over HTTP, because the build sandbox can't read your home directory. Then build `nix/package.nix` with `release.url` set to that URL.

To check the formula, run these on a Mac with Homebrew, from the tapped repo:

```bash
brew install --build-from-source --HEAD halo
brew test halo
brew audit --strict halo
```

The build needs Xcode 16+ (Swift 6 tools) and fetches the pinned Yoga package through SwiftPM.
