#!/bin/bash
# Regenerates docs/assets/*.png: runs site/shots in a second halo host (its own socket, so a running halo is left
# alone) and captures each named surface's window on its own, with a transparent background.
set -euo pipefail

cd "$(dirname "$0")/.."
swift build --product halo
halo="$PWD/.build/debug/halo"
export HALO_SOCKET="${TMPDIR:-/tmp/}halo-shots.sock"
mkdir -p docs/assets

"$halo" start --config site/shots > /dev/null 2>&1 &
host=$!
trap 'kill "$host" 2> /dev/null || true' EXIT
for _ in $(seq 50); do "$halo" inspect > /dev/null 2>&1 && break; sleep 0.1; done
sleep 1

windows="$(swift scripts/window-ids.swift "$host" 2> /dev/null)"
"$halo" inspect | python3 -c '
import json, sys
for surface in json.load(sys.stdin)["surfaces"]:
    f = surface["frame"]
    print(surface["name"], int(f["x"]), int(f["y"]), int(f["width"]), int(f["height"]))
' | while read -r name x y width height; do
  id="$(awk -v x="$x" -v y="$y" -v w="$width" -v h="$height" '$2 == x && $3 == y && $4 == w && $5 == h { print $1 }' <<< "$windows")"
  if [[ -z "$id" ]]; then
    echo "no window for $name" >&2
    continue
  fi
  screencapture -x -o -l "$id" "docs/assets/$name.png"
  echo "docs/assets/$name.png"
done
