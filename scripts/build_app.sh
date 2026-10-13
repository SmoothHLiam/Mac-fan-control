#!/bin/bash
# Builds "Mac Fan Control.app" (arm64) with the privileged helper embedded.
#   SIGN_ID="Developer ID Application: …" ./scripts/build_app.sh   # real signing
#   ./scripts/build_app.sh                                          # ad-hoc signing (local use)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
SIGN_ID="${SIGN_ID:--}"
APP="build/Mac Fan Control.app"

swift build -c "$CONFIG" --arch arm64
BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Library/LaunchDaemons" "$APP/Contents/Resources"
cp "$BIN/MacFanControl" "$APP/Contents/MacOS/MacFanControl"
cp "$BIN/FanHelper" "$APP/Contents/MacOS/FanHelper"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/com.macfancontrol.helper.plist "$APP/Contents/Library/LaunchDaemons/"

# Sign inside-out. The identifiers matter: each side pins the other by identifier over XPC.
codesign --force --sign "$SIGN_ID" --identifier com.macfancontrol.helper "$APP/Contents/MacOS/FanHelper"
codesign --force --sign "$SIGN_ID" --identifier com.macfancontrol.app "$APP"

echo "Built: $APP"
echo "Run it, then open Settings → Fan helper → Install."
