#!/bin/zsh
# Rebuilds, then relaunches the app.
set -e
cd "$(dirname "$0")/.."
./scripts/build.sh
pkill -x Shotnote 2>/dev/null || true
open build/Build/Products/Debug/Shotnote.app
