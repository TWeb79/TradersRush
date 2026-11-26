#!/bin/bash
# Packages the SwiftPM executable as a proper .app bundle so it can be dragged to the Dock.
# Re-run this after any code change to refresh the bundled binary.
set -e
cd "$(dirname "$0")/.."

swift build -c release

APP="TraderRush.app"
rm -rf "$APP" "SetupRush Trader.app" # remove the old pre-rename bundle if present
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SetupRushTrader "$APP/Contents/MacOS/SetupRushTrader"
cp AppPackaging/Info.plist "$APP/Contents/Info.plist"
cp AppPackaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
touch "$APP"

echo "Built: $(pwd)/$APP"
