#!/bin/bash
# Points the flake at a release: writes its version and the zip's SRI hash to nix/release.json.
# Usage: scripts/bump-nix.sh <version> [zip]   (without a zip, downloads the published GitHub release v<version>)
set -euo pipefail

cd "$(dirname "$0")/.."
version="${1:?usage: scripts/bump-nix.sh <version> [zip]}"
zip="${2:-}"
if [ -z "$zip" ]; then
  zip="$(mktemp)"
  trap 'rm -f "$zip"' EXIT
  curl -fsSL -o "$zip" "https://github.com/bfpimentel/halo/releases/download/v$version/halo-$version-macos.zip"
fi
hash="sha256-$(shasum -a 256 "$zip" | cut -d' ' -f1 | xxd -r -p | base64)"

printf '{\n  "version": "%s",\n  "hash": "%s"\n}\n' "$version" "$hash" > nix/release.json
echo "nix/release.json → $version ($hash)"
