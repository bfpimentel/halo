#!/bin/bash
# Bumps the version everywhere it's declared, commits, and tags v<version> on main.
# Usage: scripts/release.sh <version> [--push]
#   --push  also pushes main and the tag, which starts the release workflow (zip, GitHub release, Nix pin).
# nix/release.json is left alone: the workflow pins it once the zip is published.
set -euo pipefail

cd "$(dirname "$0")/.."
version="${1:?usage: scripts/release.sh <version> [--push]}"
push="${2:-}"
tag="v$version"

fail() { echo "release: $*" >&2; exit 1; }

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must look like 1.2.3, got '$version'"
[[ -z "$push" || "$push" == "--push" ]] || fail "unknown option '$push'"
[[ "$(git branch --show-current)" == "main" ]] || fail "not on main"
[[ -z "$(git status --porcelain)" ]] || fail "working tree has uncommitted changes"

git fetch --quiet --tags origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main differs from origin/main; pull or push first"
if git rev-parse --quiet --verify "refs/tags/$tag" >/dev/null; then
  fail "tag $tag already exists (delete it with: git tag -d $tag && git push origin :refs/tags/$tag)"
fi

current="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/IPC/Protocol.swift)"
[[ "$current" != "$version" ]] || fail "IPC.version is already $version"

sed -i '' "s/static let version = \"$current\"/static let version = \"$version\"/" Sources/IPC/Protocol.swift
sed -i '' "s/placeholder: halo $current/placeholder: halo $version/" \
  .github/ISSUE_TEMPLATE/bug_report.yml .github/DISCUSSION_TEMPLATE/show-and-tell.yml

[[ "$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/IPC/Protocol.swift)" == "$version" ]] ||
  fail "couldn't update Sources/IPC/Protocol.swift"

git add Sources/IPC/Protocol.swift .github/ISSUE_TEMPLATE/bug_report.yml .github/DISCUSSION_TEMPLATE/show-and-tell.yml
git commit --quiet -m "chore: release $tag"
git tag -a "$tag" -m "halo $version"
echo "Committed and tagged $tag ($current → $version)."

if [[ "$push" == "--push" ]]; then
  git push --atomic origin main "$tag"
  echo "Pushed. The release workflow builds the zip, publishes the release and pins it in nix/release.json."
else
  echo "Push when ready: git push --atomic origin main $tag"
fi
