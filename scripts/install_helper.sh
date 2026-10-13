#!/bin/bash
# Fallback installer for the root helper as a plain launchd daemon, for when SMAppService registration
# isn't available (e.g. running an ad-hoc build). Needs sudo.
#   sudo ./scripts/install_helper.sh "build/Mac Fan Control.app"
#   sudo ./scripts/install_helper.sh --uninstall
set -euo pipefail

LABEL="com.macfancontrol.helper"
DEST="/Library/PrivilegedHelperTools/$LABEL"
PLIST="/Library/LaunchDaemons/$LABEL.plist"

if [[ "${1:-}" == "--uninstall" ]]; then
    launchctl bootout "system/$LABEL" 2>/dev/null || true
    rm -f "$PLIST" "$DEST"
    echo "Helper removed. Fans return to automatic."
    exit 0
fi

APP="${1:?usage: install_helper.sh <path to Mac Fan Control.app> | --uninstall}"
SRC="$APP/Contents/MacOS/FanHelper"
[[ -x "$SRC" ]] || { echo "No helper at $SRC"; exit 1; }
[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }

mkdir -p /Library/PrivilegedHelperTools
cp "$SRC" "$DEST"
chown root:wheel "$DEST"
chmod 755 "$DEST"

cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key><array><string>$DEST</string></array>
    <key>MachServices</key><dict><key>$LABEL</key><true/></dict>
</dict>
</plist>
PLISTEOF
chown root:wheel "$PLIST"
chmod 644 "$PLIST"

launchctl bootout "system/$LABEL" 2>/dev/null || true
launchctl bootstrap system "$PLIST"
echo "Helper installed and registered."
