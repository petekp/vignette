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
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"   # the drag target
hdiutil create -volname "$scheme" -srcfolder "$staging" -ov -format UDZO -quiet "$dmg"
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
