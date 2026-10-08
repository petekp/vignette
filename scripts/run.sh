#!/bin/zsh
# Rebuilds, then relaunches the app. pkill's SIGTERM runs the app's own quit, which stores the open
# drawing. A copy still running after the 5 s wait is replaced by the new one, as any launch does.
# `open -n` starts a new process even when LaunchServices still lists the old one, which it does for
# a moment after the process exits: a plain `open` then sends its event to the dead process and
# fails with -600 (procNotFound).
set -e
cd "$(dirname "$0")/.."
./scripts/build.sh "$@"
name=$(sed -n 's/^name: *//p' project.yml)
if pgrep -x "$name" >/dev/null; then
  pkill -x "$name"
  for i in {1..50}; do pgrep -x "$name" >/dev/null || break; sleep 0.1; done
fi
open -n -g "build/Build/Products/Debug/$name.app"
