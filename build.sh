#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/mwitch.app"

echo "==> Building (arm64, $CONFIG)"
swift build -c "$CONFIG" --arch arm64

BIN_DIR=".build/arm64-apple-macosx/$CONFIG"
BIN="$BIN_DIR/mwitch"
if [[ ! -x "$BIN" ]]; then
    echo "error: build output not found at $BIN" >&2
    exit 1
fi

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
    echo "==> Generating AppIcon.icns"
    "$ROOT/tools/make_icons.sh"
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/mwitch"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/mwitch"

# Prefer Developer ID Application cert if one exists in the keychain —
# this keeps the code signature stable across rebuilds, so Accessibility
# grants and other TCC permissions persist instead of getting revoked.
DEVELOPER_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -E '"Developer ID Application: .*"' \
    | head -1 \
    | sed -E 's/.*"(Developer ID Application: [^"]+)".*/\1/' || true)"

if [[ -n "$DEVELOPER_ID" ]]; then
    echo "==> Signing with: $DEVELOPER_ID"
    codesign --force \
        --options runtime \
        --timestamp \
        --entitlements "$ROOT/Resources/mwitch.entitlements" \
        --sign "$DEVELOPER_ID" \
        "$APP"
    codesign --verify --strict --deep --verbose=2 "$APP"
    echo "==> Signed with Developer ID (ready for notarization)"
else
    echo "==> No Developer ID cert found — falling back to ad-hoc signing"
    echo "    (TCC permissions will not persist across rebuilds.)"
    echo "    Create one in Xcode: Settings → Accounts → Manage Certificates → + → Developer ID Application"
    codesign --force --sign - --options runtime "$APP" >/dev/null 2>&1 \
        || codesign --force --sign - "$APP"
fi

echo ""
echo "Built: $APP"
echo "Run:   open '$APP'"
echo "       (or '$APP/Contents/MacOS/mwitch' to see stdout)"
echo ""
if [[ -n "$DEVELOPER_ID" ]]; then
    echo "Next:  ./notarize.sh   # submits to Apple and staples the ticket"
fi
