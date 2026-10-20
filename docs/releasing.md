# Releasing

halo ships two ways:

- **Homebrew**: a formula in [bfpimentel/homebrew-tap](https://github.com/bfpimentel/homebrew-tap) that builds from source.
- **Nix**: a flake that installs the prebuilt release zip.

The zip comes from the release workflow ([`.github/workflows/release.yml`](../.github/workflows/release.yml)), which runs [`scripts/package.sh`](../scripts/package.sh) on every `v*` tag. The script builds a universal binary and writes `halo-<version>-macos.zip`. The zip contains `bin/halo`, `share/halo/runtime/src`, `share/halo/examples` and `LICENSE`.

## Homebrew

The formula is `Formula/halo.rb` in [bfpimentel/homebrew-tap](https://github.com/bfpimentel/homebrew-tap):

```bash
brew tap bfpimentel/tap
brew trust --formula bfpimentel/tap/halo  # Homebrew 6+ requires trusting third-party taps or formulae
brew install halo                         # latest release
brew install --HEAD halo                  # main
brew services start halo                  # launch at login (LaunchAgent running `halo start`)
```

The release workflow keeps it current. It checks first that the `HOMEBREW_TAP_TOKEN` secret (a token with Contents
read/write on the tap) is set and that the tap has `Formula/halo.rb`, so a misconfigured tap fails before building.
After publishing, it points the formula's `url` at the new tag's source tarball, sets its `sha256`, and pushes
`halo X.Y.Z` to the tap with plain git.

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

The git tag is the version. Source says `dev` (`IPC.version` in `Sources/IPC/Protocol.swift`); release builds write
the tag's version in for the build only (`scripts/package.sh <version>`, and the formula's `inreplace`).

```bash
git tag vX.Y.Z && git push origin vX.Y.Z
```

Tag any commit on `main`. The workflow rejects tags that aren't `vX.Y.Z`, then builds the zip, publishes the GitHub
release, updates the Homebrew formula in the tap and commits the Nix pin to `main`. Pull afterwards. Nothing to bump
by hand.

## Checking the packages

Build the zip locally with `scripts/package.sh`. To test the Nix package against a local zip, serve `dist/` over HTTP, because the build sandbox can't read your home directory. Then build `nix/package.nix` with `release.url` set to that URL.

To check the formula, run these on a Mac with Homebrew, with the tap installed and the formula trusted (see above):

```bash
brew install --build-from-source bfpimentel/tap/halo
brew test bfpimentel/tap/halo
brew audit --strict bfpimentel/tap/halo
```

The build needs Xcode 16+ (Swift 6 tools) and fetches the pinned Yoga package through SwiftPM.

## Docs

The docs site follows releases: the root shows the latest `v*` tag's docs and `/next/` shows `main`'s, each linking
to the other from the header. [`.github/workflows/docs.yml`](../.github/workflows/docs.yml) rebuilds both on every
tag and on pushes to `main` that touch docs, examples or the runtime. Pushing a tag is all a release needs.
