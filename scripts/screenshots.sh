#!/bin/bash
# Regenerates docs/assets: runs site/shots in a second halo host (its own socket, so a running halo is left alone)
# and captures each named surface's window on its own. "name" → name.png (transparent background);
# "name@<seconds>" → name.mp4, a recording of that length (screencapture -v, converted with avconvert).
# Only built-in macOS tools. Captures are at the display's scale: run it on a Retina display for 2x assets.
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
sleep 2 # icons load, enter animations settle

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
  if [[ "$name" != *@* ]]; then
    screencapture -x -o -l "$id" "docs/assets/$name.png"
    echo "docs/assets/$name.png"
    continue
  fi
  base="${name%@*}"
  seconds="${name#*@}"
  driver=""
  if [[ "$base" == trigger ]]; then # real `halo trigger` calls while recording
    (while true; do for n in 2 3 4 5 1; do "$halo" trigger docs.workspace "focused=$n" > /dev/null; sleep 0.9; done; done) < /dev/null &
    driver=$!
  fi
  movie="$(mktemp -t halo-shot).mov"
  screencapture -x -v -V "$seconds" -l "$id" "$movie" < /dev/null
  if [[ -n "$driver" ]]; then
    kill "$driver" 2> /dev/null
    wait "$driver" 2> /dev/null || true
  fi
  avconvert -s "$movie" -p PresetHighestQuality -o "docs/assets/$base.mp4" --replace < /dev/null > /dev/null 2>&1
  rm -f "$movie"
  echo "docs/assets/$base.mp4"
done
