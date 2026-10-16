#!/bin/bash
# Idle CPU and memory of a release halo host per example, as a Markdown table.
# Usage: scripts/perf.sh [seconds] [example ...]   (defaults: 20 s; demo services launcher animation)
# Each example runs in its own host (separate HALO_SOCKET), so a running halo is left alone.
set -euo pipefail

cd "$(dirname "$0")/.."
seconds="${1:-20}"
shift || true
[ $# -gt 0 ] || set -- demo services launcher animation

swift build -c release --product halo > /dev/null
halo="$PWD/.build/release/halo"
socket="${TMPDIR:-/tmp/}halo-perf.sock"

cpu_seconds() { # cumulative CPU time of a pid, from ps's [hh:]mm:ss.cc (hosts here never run for days)
  ps -o time= -p "$1" | awk -F'[:-]' '{ s = 0; for (i = 1; i <= NF; i++) s = s * 60 + $i; print s }'
}

echo "| example | idle CPU | RSS | footprint |"
echo "| --- | --- | --- | --- |"
for example in "$@"; do
  HALO_SOCKET="$socket" "$halo" start --config "examples/$example" > /dev/null 2>&1 &
  pid=$!
  sleep 3 # load, first layout, service start
  before="$(cpu_seconds "$pid")"
  sleep "$seconds"
  after="$(cpu_seconds "$pid")"
  rss_kb="$(ps -o rss= -p "$pid" | tr -d ' ')"
  footprint="$(footprint -p "$pid" 2> /dev/null | awk '/phys_footprint:/ { print $2, $3; exit }')"
  HALO_SOCKET="$socket" "$halo" quit > /dev/null 2>&1 || kill "$pid"
  wait "$pid" 2> /dev/null || true
  cpu="$(awk -v a="$before" -v b="$after" -v s="$seconds" 'BEGIN { printf "%.2f%%", (b - a) / s * 100 }')"
  echo "| $example | $cpu | $((rss_kb / 1024)) MB | ${footprint:-n/a} |"
done
