#!/bin/zsh
# Regenerates the Xcode project and builds the app.
# `--test` first runs scripts/check-agent-folders.py, scripts/check-app-data-paths.py and
# scripts/check-display-links.py, scripts/check-screen-stores.py, scripts/check-app-activation.py,
# scripts/check-animations.py, scripts/check-agents-map.py, scripts/check-map-line-numbers.py,
# scripts/check-site-js.py (needs deno) and scripts/check-python-unused.py (needs pyflakes or uvx),
# then the VignetteTests unit tests
# after the build, and names any that fail or were skipped.
set -e
cd "$(dirname "$0")/.."
run_tests=false
for arg in "$@"; do
  case "$arg" in
    --test) run_tests=true ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done
if $run_tests; then python3 scripts/check-agent-folders.py; python3 scripts/check-app-data-paths.py; python3 scripts/check-display-links.py; python3 scripts/check-screen-stores.py; python3 scripts/check-app-activation.py; python3 scripts/check-animations.py; python3 scripts/check-agents-map.py; python3 scripts/check-map-line-numbers.py; python3 scripts/check-site-js.py; python3 scripts/check-python-unused.py; fi
scheme=$(sed -n 's/^name: *//p' project.yml)
xcodegen generate >/dev/null   # also writes Info.plist
# The git stamp (CFBundleVersion, VignetteBuild) is a build phase in project.yml.
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
  # A skipped test leaves the run passed, so each one is named with its reason.
  result=$(ls -td build/Logs/Test/*.xcresult 2>/dev/null | head -1)
  if [[ -n "$result" ]]; then
    python3 - "$result" <<'PY'
import json, subprocess, sys
out = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", sys.argv[1]],
                     capture_output=True, text=True).stdout
try:
    nodes = json.loads(out).get("testNodes", [])
except ValueError:
    sys.exit()
skipped = []
def walk(node):
    if node.get("nodeType") == "Test Case" and node.get("result") == "Skipped":
        why = "; ".join(c.get("name", "") for c in node.get("children", []) if c.get("nodeType") == "Skip Message")
        skipped.append(f"  {node.get('nodeIdentifier', node.get('name', '?'))}: {why}")
    for child in node.get("children", []):
        walk(child)
for node in nodes:
    walk(node)
if skipped:
    print(f"tests: {len(skipped)} skipped")
    print("\n".join(skipped))
PY
  fi
fi
