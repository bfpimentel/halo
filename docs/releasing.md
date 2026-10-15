# Releasing

halo ships two ways:

- **Homebrew**: a formula in this repository that builds from source.
- **Nix**: a flake that installs the prebuilt release zip.

The zip comes from the release workflow ([`.github/workflows/release.yml`](../.github/workflows/release.yml)), which runs [`scripts/package.sh`](../scripts/package.sh) on every `v*` tag. The script builds a universal binary and writes `halo-<version>-macos.zip`. The zip contains `bin/halo`, `share/halo/runtime/src`, `share/halo/examples` and `LICENSE`.

## Homebrew

The formula lives at [`Formula/halo.rb`](../Formula/halo.rb), so the repository is its own tap:

```bash
brew tap bfpimentel/halo https://github.com/bfpimentel/halo
brew install --HEAD halo     # before the first tagged release
brew install halo            # once the formula has a stable url
brew services start halo     # launch at login (LaunchAgent running `halo start`)
```

### What the formula installs

| Path                     | Contents                                                                             |
| ------------------------ | ------------------------------------------------------------------------------------ |
| `bin/halo`               | the single binary (`swift build -c release --product halo`)                          |
| `share/halo/runtime/src` | the TS runtime; `Bundler.locate` finds it next to the real (symlink-resolved) binary |
| `share/halo/examples`    | the example configs                                                                  |

`halo init` writes `opt/halo/...` paths (not the versioned Cellar path) into the user's `tsconfig.json`, so editor
types survive upgrades. esbuild comes from the `esbuild` formula; launchd's minimal `PATH` is covered by the
service's `std_service_path_env` and by `Bundler`'s fallback search of `/opt/homebrew/bin` and `/usr/local/bin`.

## Nix

User setup (inputs, modules, options): [Getting started](guide/01-getting-started.md#nix).

The package is `packages.<system>.default`. It downloads the release zip pinned in [`nix/release.json`](../nix/release.json), checks the zip's sha256 (`fetchurl`, so plain `shasum` computes it), unpacks it, and wraps `halo` so it uses nixpkgs' esbuild. Nix downloads don't get the quarantine flag, so the unsigned binary runs as is. To work on halo, `nix develop` gives you esbuild, bun, oxlint and oxfmt.

The release workflow pins each release itself: after publishing, it runs `scripts/bump-nix.sh <version> <zip>` on the zip it just uploaded and pushes `chore(nix): pin release <version>` to `main` with the workflow's token (plain git, no third-party action). That push doesn't trigger other workflows. If `main` is protected against direct pushes, allow `github-actions[bot]` or pin by hand with `scripts/bump-nix.sh X.Y.Z` (downloads the published zip).

## Cutting a release

1. Bump `IPC.version` in `Sources/IPC/Protocol.swift`, commit, tag `vX.Y.Z` and push the tag. The workflow builds the zip, publishes the GitHub release and commits the Nix pin to `main`. Pull afterwards.
2. For Homebrew, get the source tarball checksum:
   ```bash
   curl -sL https://github.com/bfpimentel/halo/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256
   ```
3. Add this to the formula, above `head`:
   ```ruby
   url "https://github.com/bfpimentel/halo/archive/refs/tags/vX.Y.Z.tar.gz"
   sha256 "<checksum>"
   ```
4. Commit the formula change. Users then get the new version with `brew update && brew upgrade halo`.

## Checking the packages

Build the zip locally with `scripts/package.sh`. To test the Nix package against a local zip, serve `dist/` over HTTP, because the build sandbox can't read your home directory. Then build `nix/package.nix` with `release.url` set to that URL.

To check the formula, run these on a Mac with Homebrew, from the tapped repo:

```bash
brew install --build-from-source --HEAD halo
brew test halo
brew audit --strict halo
```

The build needs Xcode 16+ (Swift 6 tools) and fetches the pinned Yoga package through SwiftPM.
