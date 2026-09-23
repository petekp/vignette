#!/bin/zsh
# Rebuilds, then relaunches the app. Waits for the old process to exit before opening the new
# build, so the new instance never finds an older one to replace. Drawings live on disk. The kill
# skips the app's own quit, so the editor loses only a change from its last 0.3 s.
set -e
cd "$(dirname "$0")/.."
./scripts/build.sh "$@"
name=$(sed -n 's/^name: *//p' project.yml)
if pgrep -x "$name" >/dev/null; then
  pkill -x "$name"
  for i in {1..50}; do pgrep -x "$name" >/dev/null || break; sleep 0.1; done
fi
open -g "build/Build/Products/Debug/$name.app"
