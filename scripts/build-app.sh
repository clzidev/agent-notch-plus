#!/bin/sh
# Builds AgentNotchPlus.app as a universal binary (Apple Silicon + Intel).
# Works with Command Line Tools only (no full Xcode needed).
# Install with:  cp -R build/AgentNotchPlus.app /Applications/
set -e
cd "$(dirname "$0")/.."
mkdir -p build
if swift build -c release --triple arm64-apple-macosx12.0 && \
   swift build -c release --triple x86_64-apple-macosx12.0; then
    lipo -create \
        .build/arm64-apple-macosx/release/AgentNotchPlus \
        .build/x86_64-apple-macosx/release/AgentNotchPlus \
        -output build/AgentNotchPlus-bin
else
    echo "Cross build failed — building native arch only"
    swift build -c release
    cp .build/release/AgentNotchPlus build/AgentNotchPlus-bin
fi
APP="build/AgentNotchPlus.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/AgentNotchPlus-bin "$APP/Contents/MacOS/AgentNotchPlus"
rm -f build/AgentNotchPlus-bin
cp -R pets "$APP/Contents/Resources/pets"
cp scripts/Info.plist "$APP/Contents/Info.plist"
cp scripts/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep -s - "$APP" 2>/dev/null || true
echo "Built $APP"
lipo -info "$APP/Contents/MacOS/AgentNotchPlus" 2>/dev/null || true
