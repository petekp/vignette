#!/bin/zsh
# Runs scripts/input.swift. Compiles it with Sources/HotKeySpec.swift into build/input when the
# binary is missing or older than either source. Not part of build.sh: the tool is only for
# driving the app from a terminal, and that terminal's Accessibility trust is what lets it post.
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"
bin="$root/build/input"
sources=("$root/scripts/input.swift" "$root/Sources/HotKeySpec.swift")
build=false
[[ -x "$bin" ]] || build=true
for source in "${sources[@]}"; do [[ "$source" -nt "$bin" ]] && build=true; done
if $build; then
  mkdir -p "$root/build"
  xcrun swiftc -parse-as-library -O -o "$bin" "${sources[@]}"
fi
exec "$bin" "$@"
