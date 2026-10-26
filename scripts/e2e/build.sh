#!/bin/zsh
# Builds the end-to-end test copy from the source as it is, with its own bundle id, name and URL
# scheme, so it never shares settings, drawings, logs, URLs or Accessibility trust with the real app.
#   build.sh          Vignette E2E        com.petepetrash.vignette.e2e        vignette-e2e
#   build.sh fresh    Vignette E2E Fresh  com.petepetrash.vignette.e2e-fresh  vignette-e2e-fresh
# The first is granted Accessibility once by hand; the second is reset before a run, for the
# untrusted paths. Signed like scripts/build.sh, so a rebuild keeps the grant.
# A launch through LaunchServices with no environment (macOS's Quit & Reopen, Sparkle, a bare
# `open`) would not be a test launch, so each copy's Info.plist names a scratch home and settings
# file under LSEnvironment: /tmp/<bundle id>/home. `open --env` overrides them key by key. e2e.py
# links that home to each scenario's own; by hand, use it as the scratch home or link it to yours.
# Writing it breaks Xcode's signature, so the copy is signed again with the same identity, which
# keeps the designated requirement and the grant.
set -e
cd "$(dirname "$0")/../.."
name=$(sed -n 's/^name: *//p' project.yml)
bundle=$(sed -n 's/^ *PRODUCT_BUNDLE_IDENTIFIER: *\(com[^ ]*\)$/\1/p' project.yml | head -1)
scheme=$(sed -n 's/^ *VIGNETTE_URL_SCHEME: *//p' project.yml)
case "${1:-}" in
  "") suffix=e2e; label="E2E" ;;
  fresh) suffix=e2e-fresh; label="E2E Fresh" ;;
  *) echo "usage: build.sh [fresh]" >&2; exit 2 ;;
esac
out=scripts/e2e/out
mkdir -p "$out"
signing_args=()
if [[ -f scripts/signing.env ]]; then
  source scripts/signing.env
  signing_args=(CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}")
fi
xcodegen generate >/dev/null
log="$out/build-$suffix.log"
if ! xcodebuild -project "$name.xcodeproj" -scheme "$name" -configuration Release -derivedDataPath "$out/dd-$suffix" build -quiet \
    PRODUCT_NAME="$name $label" PRODUCT_BUNDLE_IDENTIFIER="$bundle.$suffix" VIGNETTE_URL_SCHEME="$scheme-$suffix" \
    "${signing_args[@]}" >"$log" 2>&1; then
  echo "xcodebuild failed; see $log" >&2
  exit 1
fi
app="$PWD/$out/dd-$suffix/Build/Products/Release/$name $label.app"
got_bundle=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist")
got_scheme=$(/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes:0" "$app/Contents/Info.plist")
if [[ "$got_bundle" != "$bundle.$suffix" || "$got_scheme" != "$scheme-$suffix" ]]; then
  echo "the test copy came out as $got_bundle with scheme $got_scheme" >&2
  exit 1
fi
home="/tmp/$bundle.$suffix/home"
plutil -replace LSEnvironment -json "{\"VIGNETTE_SETTINGS\": \"$home/settings.json\", \"CFFIXED_USER_HOME\": \"$home\"}" \
  "$app/Contents/Info.plist"
if ! codesign --force --sign "${CODE_SIGN_IDENTITY:--}" --timestamp=none \
    --preserve-metadata=entitlements,requirements,flags,runtime "$app" >>"$log" 2>&1; then
  echo "signing after writing LSEnvironment failed; see $log" >&2
  exit 1
fi
if [[ $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$app/Contents/Info.plist") == 0 ]]; then
  echo "warning: the git stamp did not land; Info.plist was written after the stamp phase ran" >&2
fi
echo "$app"
