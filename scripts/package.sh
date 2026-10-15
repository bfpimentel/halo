#!/bin/bash
# Builds the release zip that the GitHub workflow publishes and the Nix flake installs:
#   halo-<version>-macos/{bin/halo, share/halo/runtime/src, share/halo/examples}
# The binary is universal (arm64 + x86_64). Usage: scripts/package.sh [version] (defaults to IPC.version).
set -euo pipefail

cd "$(dirname "$0")/.."
version="${1:-$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/IPC/Protocol.swift)}"
declared="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/IPC/Protocol.swift)"
if [[ "$version" != "$declared" ]]; then
  echo "version $version doesn't match IPC.version ($declared) in Sources/IPC/Protocol.swift" >&2
  exit 1
fi

build=(swift build --configuration release --product halo --arch arm64 --arch x86_64)
"${build[@]}"
binary="$("${build[@]}" --show-bin-path)/halo"

name="halo-$version-macos"
stage="dist/$name"
rm -rf "$stage" "dist/$name.zip"
mkdir -p "$stage/bin" "$stage/share/halo/runtime"
cp "$binary" "$stage/bin/halo"
cp -R runtime/src "$stage/share/halo/runtime/src"
cp -R examples "$stage/share/halo/examples"

(cd dist && zip -qry "$name.zip" "$name")

echo "dist/$name.zip"
echo "sha256: $(shasum -a 256 "dist/$name.zip" | cut -d' ' -f1)"
