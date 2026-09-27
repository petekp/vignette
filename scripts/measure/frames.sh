#!/bin/zsh
# Runs scripts/measure/frames.swift, compiled into build/frames when the binary is missing or older
# than the source. Run it with no arguments for the usage.
set -e
root="$(cd "$(dirname "$0")/../.." && pwd)"
bin="$root/build/frames"
source="$root/scripts/measure/frames.swift"
if [[ ! -x "$bin" || "$source" -nt "$bin" ]]; then
  mkdir -p "$root/build"
  xcrun swiftc -O -o "$bin" "$source"
fi
exec "$bin" "$@"
