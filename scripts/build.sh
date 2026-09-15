#!/bin/zsh
# Builds the web bundle, regenerates the Xcode project, and builds the app.
# `--test` also runs the ShotnoteTests unit tests after the build.
set -e
cd "$(dirname "$0")/.."
run_tests=false
for arg in "$@"; do
  case "$arg" in
    --test) run_tests=true ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done
(cd web && pnpm build)
xcodegen generate >/dev/null
xcodebuild -project Shotnote.xcodeproj -scheme Shotnote -configuration Debug -derivedDataPath build build -quiet
echo "built: $PWD/build/Build/Products/Debug/Shotnote.app"
if $run_tests; then
  xcodebuild -project Shotnote.xcodeproj -scheme Shotnote -destination 'platform=macOS' -derivedDataPath build test -quiet
  echo "tests: passed"
fi
