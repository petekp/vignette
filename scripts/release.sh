#!/bin/zsh
# Builds, signs, packages, notarizes, and staples a release disk image.
#
#   scripts/release.sh 0.1.0             a full release: notarized and stapled
#   scripts/release.sh 0.1.0 --dry-run   everything but notarization, for checking the pipeline
#
# Needs scripts/signing.env with a Developer ID identity, and (unless --dry-run) notarytool
# credentials stored under $NOTARY_PROFILE. See docs/building.md.
set -e
cd "$(dirname "$0")/.."

version=""
dry_run=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=true ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) if [[ -n "$version" ]]; then echo "version given twice: $arg" >&2; exit 2; fi; version="$arg" ;;
  esac
done
if [[ -z "$version" ]]; then
  echo "usage: scripts/release.sh <version> [--dry-run]" >&2; exit 2
fi
if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "version must look like 1.2.3, got: $version" >&2; exit 2
fi

scheme=$(sed -n 's/^name: *//p' project.yml)
notary_profile="${NOTARY_PROFILE:-vignette}"
out="build/dist"
archive="build/release/$scheme.xcarchive"
app="$out/$scheme.app"
dmg="$out/$scheme-$version.dmg"

# --- what a release cannot be built without -------------------------------------------------

# An ad-hoc signature cannot be notarized, and notarization is the whole point of this script.
if [[ ! -f scripts/signing.env ]]; then
  echo "scripts/signing.env is missing; a release needs a Developer ID certificate" >&2; exit 1
fi
source scripts/signing.env
if [[ "$CODE_SIGN_IDENTITY" != Developer\ ID* ]]; then
  echo "CODE_SIGN_IDENTITY is \"$CODE_SIGN_IDENTITY\"; a release needs a Developer ID certificate" >&2; exit 1
fi
if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "DEVELOPMENT_TEAM is not set in scripts/signing.env; the export needs a team id" >&2; exit 1
fi

# The artifact has to be reproducible from the tag it is released under.
if ! $dry_run && [[ -n "$(git status --porcelain)" ]]; then
  echo "the working tree is dirty; commit or stash before cutting a release" >&2; exit 1
fi

if ! $dry_run && ! xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1; then
  echo "no notarytool credentials under the profile \"$notary_profile\"; see docs/building.md" >&2; exit 1
fi

# --- build -----------------------------------------------------------------------------------

echo "==> app ($version, Release, $CODE_SIGN_IDENTITY)"
xcodegen generate >/dev/null   # also writes Info.plist
rm -rf build/release "$out"
mkdir -p "$out"
# archive and export, not `xcodebuild build`: a plain build is signed for development and carries
# the get-task-allow entitlement whatever the configuration says, and the notary service rejects it.
xcodebuild -project "$scheme.xcodeproj" -scheme "$scheme" -configuration Release \
  -derivedDataPath build/release -archivePath "$archive" archive -quiet \
  MARKETING_VERSION="$version" \
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"

export_options="build/release/ExportOptions.plist"
cat > "$export_options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$DEVELOPMENT_TEAM</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
  <key>destination</key><string>export</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$export_options" -exportPath "$out" >/dev/null

# --- check the things notarization rejects silently --------------------------------------------

echo "==> checking the signature"
# Debug builds carry get-task-allow, and the notary service refuses a binary that has it.
if codesign -d --entitlements - --xml "$app" 2>/dev/null | grep -q 'get-task-allow'; then
  echo "the build carries the get-task-allow entitlement; notarization would reject it" >&2; exit 1
fi
# The hardened runtime is required for notarization.
if ! codesign -d -v "$app" 2>&1 | grep -q 'flags=.*runtime'; then
  echo "the hardened runtime is not enabled on the built app" >&2; exit 1
fi
codesign --verify --deep --strict --verbose=2 "$app"

# --- package -----------------------------------------------------------------------------------

echo "==> disk image"
staging=$(mktemp -d)
device=""
trap '[[ -n "$device" ]] && hdiutil detach "$device" -quiet 2>/dev/null; rm -rf "$staging" "$staging.rw.dmg"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"   # the drag target
# Finder finds the image by its volume name, and a second volume of that name mounts as "$scheme 1".
if [[ -e "/Volumes/$scheme" ]]; then
  echo "a volume named $scheme is mounted; eject it before cutting a release" >&2; exit 1
fi
# Laid out by Finder on a writable image, then compressed: a small window with the app on the
# left and Applications on the right. Finder asks once for this terminal to control it.
hdiutil create -volname "$scheme" -srcfolder "$staging" -ov -format UDRW -quiet "$staging.rw.dmg"
device=$(hdiutil attach "$staging.rw.dmg" -readwrite -noverify -noautoopen | awk '/\/Volumes\// {print $1; exit}')
# Finder learns of the new disk a moment after hdiutil returns.
for _ in {1..50}; do
  [[ $(osascript -e "tell application \"Finder\" to exists disk \"$scheme\"") == true ]] && break
  sleep 0.2
done
osascript <<OSA
tell application "Finder"
  tell disk "$scheme"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {400, 200, 940, 540}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set position of item "$scheme.app" of container window to {140, 150}
    set position of item "Applications" of container window to {400, 150}
    set extension hidden of item "$scheme.app" to true
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
# Written by the volume itself, and visible to anyone whose Finder shows hidden files.
rm -rf "/Volumes/$scheme/.fseventsd"
sync
hdiutil detach "$device" -quiet
device=""
hdiutil convert "$staging.rw.dmg" -format UDZO -ov -quiet -o "$dmg"
codesign --sign "$CODE_SIGN_IDENTITY" --timestamp "$dmg"

# --- notarize ----------------------------------------------------------------------------------

if $dry_run; then
  echo "built (not notarized): $PWD/$dmg"
  echo "a dry run cannot be distributed: macOS will refuse to open it on another Mac."
  exit 0
fi

echo "==> notarizing (this waits on Apple, usually a few minutes)"
xcrun notarytool submit "$dmg" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$dmg"

echo "==> verifying the stapled image"
xcrun stapler validate "$dmg"
# What Gatekeeper will say when the user opens it.
spctl --assess --type open --context context:primary-signature -v "$dmg"

echo
echo "released: $PWD/$dmg"
echo "next: git tag v$version && git push origin v$version"
echo "      gh release create v$version \"$dmg\" --title \"$scheme $version\""
