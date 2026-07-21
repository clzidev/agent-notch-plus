#!/bin/sh
# Builds a distributable DMG: the app plus an /Applications shortcut.
set -e
cd "$(dirname "$0")/.."
./scripts/build-app.sh
rm -rf build/dmg build/AgentNotchPlus.dmg
mkdir -p build/dmg
cp -R build/AgentNotchPlus.app build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname "Agent Notch Plus" -srcfolder build/dmg -ov -format UDZO build/AgentNotchPlus.dmg
rm -rf build/dmg
echo "Built build/AgentNotchPlus.dmg"
