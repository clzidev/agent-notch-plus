#!/bin/sh
# Builds AgentNotchPlus.app (run from anywhere). Install with:
#   cp -R build/AgentNotchPlus.app /Applications/
set -e
cd "$(dirname "$0")/.."
swift build -c release
APP="build/AgentNotchPlus.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/AgentNotchPlus "$APP/Contents/MacOS/AgentNotchPlus"
cp -R pets "$APP/Contents/Resources/pets"
cp scripts/Info.plist "$APP/Contents/Info.plist"
cp scripts/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep -s - "$APP" 2>/dev/null || true
echo "Built $APP"
