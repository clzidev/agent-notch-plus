#!/bin/sh
# Builds AgentNotchPlus.app as a universal binary (Apple Silicon + Intel).
# Works with Command Line Tools only (no full Xcode needed).
# Install with:  cp -R build/AgentNotchPlus.app /Applications/
set -e
cd "$(dirname "$0")/.."
mkdir -p build
# native build system: the default (swiftbuild) insists on precompiling
# SwiftTerm's Shaders.metal, which needs Xcode's optional Metal Toolchain.
# Natively the shader source is just copied and compiled at runtime
# (macOS caches the result), so Command Line Tools are enough.
BS="--build-system native"
if swift build -c release $BS --triple arm64-apple-macosx12.0 && \
   swift build -c release $BS --triple x86_64-apple-macosx12.0; then
    lipo -create \
        .build/arm64-apple-macosx/release/AgentNotchPlus \
        .build/x86_64-apple-macosx/release/AgentNotchPlus \
        -output build/AgentNotchPlus-bin
else
    echo "Cross build failed — building native arch only"
    swift build -c release $BS
    cp .build/release/AgentNotchPlus build/AgentNotchPlus-bin
fi
APP="build/AgentNotchPlus.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/AgentNotchPlus-bin "$APP/Contents/MacOS/AgentNotchPlus"
rm -f build/AgentNotchPlus-bin
cp -R pets "$APP/Contents/Resources/pets"
# GPU terminal renderer: SwiftTerm looks for its shader in this bundle
# (Contents/Resources) and, as a fallback, in the main bundle
SHADERS=$(ls -d .build/*/release/SwiftTerm_SwiftTerm.bundle 2>/dev/null | head -1)
if [ -n "$SHADERS" ]; then
    cp -R "$SHADERS" "$APP/Contents/Resources/"
    cp "$SHADERS/Shaders.metal" "$APP/Contents/Resources/" 2>/dev/null || true
fi
mkdir -p "$APP/Contents/Resources/fonts"
cp scripts/fonts/*.ttf scripts/fonts/LICENSE.txt "$APP/Contents/Resources/fonts/" 2>/dev/null || true
cp scripts/Info.plist "$APP/Contents/Info.plist"
cp scripts/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep -s - "$APP" 2>/dev/null || true
echo "Built $APP"
lipo -info "$APP/Contents/MacOS/AgentNotchPlus" 2>/dev/null || true
