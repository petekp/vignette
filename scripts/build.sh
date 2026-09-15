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
scheme=$(sed -n 's/^name: *//p' project.yml)
(cd web && pnpm build)
xcodegen generate >/dev/null
# The bundle carries the git state: commit count as CFBundleVersion, describe as ShotnoteBuild.
number=$(git rev-list --count HEAD 2>/dev/null || echo 0)
build=$(git describe --always --dirty 2>/dev/null || echo local)
stamp=(CURRENT_PROJECT_VERSION="$number" SHOTNOTE_BUILD="$build")
xcodebuild -project "$scheme.xcodeproj" -scheme "$scheme" -configuration Debug -derivedDataPath build build -quiet "${stamp[@]}"
echo "built: $PWD/build/Build/Products/Debug/$scheme.app ($build)"
if $run_tests; then
  # Same stamp, or the test run rebuilds the app with the project defaults.
  xcodebuild -project "$scheme.xcodeproj" -scheme "$scheme" -destination 'platform=macOS' -derivedDataPath build test -quiet "${stamp[@]}"
  echo "tests: passed"
fi
