#!/bin/bash
# Builds the release zip that the GitHub workflow publishes and the Nix flake installs:
#   halo-<version>-macos/{bin/halo, share/halo/runtime/src, share/halo/examples, LICENSE}
# The binary is universal (arm64 + x86_64). Usage: scripts/package.sh <version> (the release workflow passes the tag's).
# The version exists only in the git tag: it's written into IPC.version for this build and restored afterwards.
set -euo pipefail

cd "$(dirname "$0")/.."
version="${1:?usage: scripts/package.sh <version>}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must look like 1.2.3, got '$version'" >&2; exit 1; }

source="Sources/IPC/Protocol.swift"
cp "$source" "$source.orig"
trap 'mv "$source.orig" "$source"' EXIT
sed -i '' "s/static let version = \"dev\"/static let version = \"$version\"/" "$source"
grep -q "static let version = \"$version\"" "$source" || { echo "couldn't set IPC.version in $source" >&2; exit 1; }

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
cp LICENSE "$stage/LICENSE"

(cd dist && zip -qry "$name.zip" "$name")

echo "dist/$name.zip"
echo "sha256: $(shasum -a 256 "dist/$name.zip" | cut -d' ' -f1)"
