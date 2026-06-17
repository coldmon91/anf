#!/bin/bash
# Install (or refresh) the midnight nightly-release LaunchAgent on this Mac.
# Idempotent: re-run after editing the schedule. Uninstall with:
#   launchctl bootout gui/$(id -u)/dev.rescene.anf.nightly
#   rm ~/Library/LaunchAgents/dev.rescene.anf.nightly.plist
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="dev.rescene.anf.nightly"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/anf-nightly"
mkdir -p "$(dirname "$PLIST")" "$LOG_DIR"

cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$REPO/tools/nightly-release.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key><integer>0</integer>
        <key>Minute</key><integer>0</integer>
    </dict>
    <key>StandardOutPath</key><string>$LOG_DIR/launchd.out.log</string>
    <key>StandardErrorPath</key><string>$LOG_DIR/launchd.err.log</string>
    <key>RunAtLoad</key><false/>
    <key>ProcessType</key><string>Background</string>
</dict>
</plist>
PLIST

# Reload cleanly (bootout is fine to fail when not yet loaded).
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl enable "gui/$(id -u)/$LABEL"

echo "✓ installed $LABEL — runs nightly at 00:00"
echo "  plist:  $PLIST"
echo "  script: $REPO/tools/nightly-release.sh"
echo "  logs:   $LOG_DIR/"
echo
echo "next run:"
launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | grep -iE "runs|next|state =" | sed 's/^/  /' || true
