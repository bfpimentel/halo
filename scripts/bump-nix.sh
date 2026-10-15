#!/bin/bash
# Points the flake at a published release: writes its version and the Nix hash of the unpacked zip to nix/release.json.
# Usage: scripts/bump-nix.sh <version>   (the GitHub release v<version> must exist)
set -euo pipefail

cd "$(dirname "$0")/.."
version="${1:?usage: scripts/bump-nix.sh <version>}"
url="https://github.com/bfpimentel/halo/releases/download/v$version/halo-$version-macos.zip"
hash="$(nix store prefetch-file --unpack --json "$url" | sed -n 's/.*"hash": *"\([^"]*\)".*/\1/p')"

printf '{\n  "version": "%s",\n  "hash": "%s"\n}\n' "$version" "$hash" > nix/release.json
echo "nix/release.json → $version ($hash)"
