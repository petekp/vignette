#!/bin/zsh
# Builds the web bundle, regenerates the Xcode project, and builds the app.
set -e
cd "$(dirname "$0")/.."
(cd web && pnpm build)
xcodegen generate >/dev/null
xcodebuild -project Shotnote.xcodeproj -scheme Shotnote -configuration Debug -derivedDataPath build build -quiet
echo "built: $PWD/build/Build/Products/Debug/Shotnote.app"
