#!/bin/zsh
# Regenerates the Xcode project and builds the app.
# `--test` first runs scripts/check-agent-folders.py, scripts/check-app-data-paths.py and
# scripts/check-display-links.py, scripts/check-screen-stores.py, scripts/check-app-activation.py,
# scripts/check-animations.py, scripts/check-agents-map.py, scripts/check-map-line-numbers.py,
# scripts/check-site-js.py (needs deno) and scripts/check-python-unused.py (needs pyflakes or uvx),
# then the VignetteTests unit tests
# after the build, and names any that fail or were skipped.
# `--derived-data <path>` builds into <path> instead of build/, read from the folder the script is
# run in, so a worktree's build leaves build/ and any copy running from it alone.
set -e
run_tests=false
derived_data=build
while (( $# )); do
  case "$1" in
    --test) run_tests=true ;;
    --derived-data)
      if [[ -z "$2" || "$2" == --* ]]; then
        echo "--derived-data needs a folder: scripts/build.sh --derived-data <path>" >&2; exit 2
      fi
      derived_data=${2:a}; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
cd "$(dirname "$0")/.."
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
xcodebuild -project "$scheme.xcodeproj" -scheme "$scheme" -configuration Debug -derivedDataPath "$derived_data" build -quiet "${signing_args[@]}"
echo "built: ${derived_data:a}/Build/Products/Debug/$scheme.app ($build, signed: $signing)"
if $run_tests; then
  # Same signing, or the test run rebuilds the app with the project defaults.
  if ! xcodebuild -project "$scheme.xcodeproj" -scheme "$scheme" -destination 'platform=macOS' -derivedDataPath "$derived_data" test -quiet "${signing_args[@]}"; then
    # xcodebuild's own output names compile errors; the result bundle names the failed tests.
    result=$(ls -td "$derived_data"/Logs/Test/*.xcresult 2>/dev/null | head -1)
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
  result=$(ls -td "$derived_data"/Logs/Test/*.xcresult 2>/dev/null | head -1)
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
