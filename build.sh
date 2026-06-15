#!/bin/bash
# Builds anf and assembles a runnable anf.app bundle.
#   ./build.sh        release build + bundle
#   ./build.sh run    build, bundle, then launch
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=release
APP="anf.app"
BIN_DIR="$APP/Contents/MacOS"
RES_DIR="$APP/Contents/Resources"

echo "▸ Compiling ($CONFIG)…"
swift build -c "$CONFIG" --product anfapp
BIN="$(swift build -c "$CONFIG" --show-bin-path)/anfapp"

echo "▸ Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$BIN_DIR" "$RES_DIR"
cp "$BIN" "$BIN_DIR/anf"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$RES_DIR/AppIcon.icns"

# The SwiftPM resource bundle (xterm terminal page, l10n tables) MUST ship inside
# the app: without it 1.0.0 crashed on every non-dev machine the moment the
# terminal opened (or at launch on non-ko/en locales).
cp -R "$(swift build -c "$CONFIG" --show-bin-path)/anf_anf.bundle" "$RES_DIR/"
[ -f "$RES_DIR/anf_anf.bundle/xterm/terminal.html" ] || {
    echo "✗ resource bundle missing from $APP (xterm/terminal.html not found)" >&2
    exit 1
}

# Signing preference, best → worst:
#   1. Developer ID Application — hardened runtime + secure timestamp, the form
#      Apple notarization requires. Sign nested code BEFORE the outer bundle
#      (Apple discourages --deep for distribution). Release builds land here.
#   2. anf-dev — stable self-signed identity; keeps macOS TCC (file-access)
#      permissions across local rebuilds. Set up via ./tools/setup-signing.sh.
#   3. ad-hoc — last resort.
DEVID="Developer ID Application"
if security find-identity -p codesigning -v 2>/dev/null | grep -q "$DEVID"; then
    # anf_anf.bundle is a pure resource dir (no Info.plist, no Mach-O) — it carries
    # no code, so it isn't signed on its own; signing the app seals it as a resource.
    codesign --force --options runtime --timestamp \
        --sign "$DEVID" "$APP" >/dev/null
    echo "▸ Signed with '$DEVID' (hardened runtime — ready for notarization)"
elif security find-identity -p codesigning 2>/dev/null | grep -q "anf-dev" \
     && codesign --force --deep --sign "anf-dev" "$APP" >/dev/null 2>&1; then
    echo "▸ Signed with 'anf-dev' (stable self-signed identity)"
else
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
    echo "▸ Ad-hoc signed (run ./tools/setup-signing.sh for persistent permissions)"
fi

echo "✓ Built $APP"

if [[ "${1:-}" == "run" ]]; then
    echo "▸ Launching…"
    open "$APP"
fi
