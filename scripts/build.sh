#!/bin/zsh
# Builds the web bundle, regenerates the Xcode project, and builds the app.
# `--test` also runs the ShotnoteTests unit tests after the build and names any that fail.
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
xcodegen generate >/dev/null   # also writes Info.plist; web/dist must exist first
# The git stamp (CFBundleVersion, ShotnoteBuild) is a build phase in project.yml.
build=$(git describe --always --dirty 2>/dev/null || echo local)
# scripts/signing.env (gitignored) names a certificate; without it the build is ad-hoc signed.
signing_args=()
if [[ -f scripts/signing.env ]]; then
  source scripts/signing.env
  signing_args=(CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}")
  signing="$CODE_SIGN_IDENTITY"
else
  signing="ad-hoc"
fi
xcodebuild -project "$scheme.xcodeproj" -scheme "$scheme" -configuration Debug -derivedDataPath build build -quiet "${signing_args[@]}"
echo "built: $PWD/build/Build/Products/Debug/$scheme.app ($build, signed: $signing)"
if $run_tests; then
  # Same signing, or the test run rebuilds the app with the project defaults.
  if ! xcodebuild -project "$scheme.xcodeproj" -scheme "$scheme" -destination 'platform=macOS' -derivedDataPath build test -quiet "${signing_args[@]}"; then
    # xcodebuild's own output names compile errors; the result bundle names the failed tests.
    result=$(ls -td build/Logs/Test/*.xcresult 2>/dev/null | head -1)
    if [[ -n "$result" ]]; then
      summary=$(xcrun xcresulttool get test-results summary --path "$result" 2>/dev/null)
      python3 - "$summary" <<'PY' >&2
import json, sys
d = json.loads(sys.argv[1])
print(f"tests: failed ({d.get('failedTests', '?')} of {d.get('totalTestCount', '?')})")
for f in d.get("testFailures", []):
    print(f"  {f.get('targetName', '')}/{f.get('testName', '?')}: {f.get('failureText', '')}")
PY
    fi
    exit 1
  fi
  echo "tests: passed"
fi
