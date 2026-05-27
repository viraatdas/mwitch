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

# SPM copies the resolved Sparkle.framework next to the binary. It's a
# universal (arm64+x86_64) slice with the helper apps + XPC services inside.
SPARKLE_FW="$BIN_DIR/Sparkle.framework"
if [[ ! -d "$SPARKLE_FW" ]]; then
    echo "error: Sparkle.framework not found at $SPARKLE_FW" >&2
    echo "       Run 'swift package resolve' then rebuild." >&2
    exit 1
fi

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
    echo "==> Generating AppIcon.icns"
    "$ROOT/tools/make_icons.sh"
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/mwitch"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/mwitch"

# Stamp the version. Marketing version comes from the VERSION file; the build
# number is the git commit count so it increases monotonically — Sparkle uses
# CFBundleVersion to decide whether an appcast item is newer than what's installed.
MARKETING_VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION" 2>/dev/null || echo 0.0.0)"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
echo "==> Version $MARKETING_VERSION (build $BUILD_NUMBER)"
plutil -replace CFBundleShortVersionString -string "$MARKETING_VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"

# Embed Sparkle (cp -R preserves the framework's internal symlinks).
echo "==> Embedding Sparkle.framework"
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"

# Prefer a stable signing identity over ad-hoc so TCC grants (Accessibility,
# etc.) persist across rebuilds. Developer ID Application is best (also
# notarizable); Apple Development is fine for local use.
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
SIGN_ID="$(echo "$IDENTITIES" | { grep -E '"Developer ID Application: .*"' || true; } | head -1 \
    | sed -E 's/.*"(Developer ID Application: [^"]+)".*/\1/')"
IS_DEVELOPER_ID=1
if [[ -z "$SIGN_ID" ]]; then
    SIGN_ID="$(echo "$IDENTITIES" | { grep -E '"Apple Development: .*"' || true; } | head -1 \
        | sed -E 's/.*"(Apple Development: [^"]+)".*/\1/')"
    IS_DEVELOPER_ID=0
fi

# Sparkle's framework, helper apps, and XPC services must each be signed
# inside-out with our identity *before* the outer app. Under hardened runtime,
# library validation only loads code signed by the same Team ID, so the
# framework (shipped signed by the Sparkle project) has to be re-signed.
sign_sparkle() {
    local id="$1"
    local fw="$APP/Contents/Frameworks/Sparkle.framework"
    local v="$fw/Versions/B"
    local opts=(--force --options runtime)
    [[ "$id" != "-" ]] && opts+=(--timestamp)
    for target in \
        "$v/XPCServices/Downloader.xpc" \
        "$v/XPCServices/Installer.xpc" \
        "$v/Autoupdate" \
        "$v/Updater.app" \
        "$fw"; do
        [[ -e "$target" ]] || continue
        codesign "${opts[@]}" --sign "$id" "$target"
    done
}

if [[ -n "$SIGN_ID" && "$IS_DEVELOPER_ID" -eq 1 ]]; then
    echo "==> Signing with: $SIGN_ID"
    sign_sparkle "$SIGN_ID"
    codesign --force \
        --options runtime \
        --timestamp \
        --entitlements "$ROOT/Resources/mwitch.entitlements" \
        --sign "$SIGN_ID" \
        "$APP"
    codesign --verify --strict --deep --verbose=2 "$APP"
    echo "==> Signed with Developer ID (ready for notarization)"
elif [[ -n "$SIGN_ID" ]]; then
    echo "==> Signing with: $SIGN_ID (local-use cert; not notarizable)"
    sign_sparkle "$SIGN_ID"
    codesign --force \
        --options runtime \
        --entitlements "$ROOT/Resources/mwitch.entitlements" \
        --sign "$SIGN_ID" \
        "$APP"
    codesign --verify --strict --deep --verbose=2 "$APP"
    echo "==> Signed (TCC grants will persist across rebuilds)"
else
    echo "==> No signing cert found — falling back to ad-hoc signing"
    echo "    (TCC permissions will not persist across rebuilds.)"
    echo "    Create one in Xcode: Settings → Accounts → Manage Certificates → + → Developer ID Application"
    sign_sparkle "-"
    codesign --force --sign - --options runtime "$APP" >/dev/null 2>&1 \
        || codesign --force --sign - "$APP"
fi

echo ""
echo "Built: $APP"
echo "Run:   open '$APP'"
echo "       (or '$APP/Contents/MacOS/mwitch' to see stdout)"
echo ""
if [[ "$IS_DEVELOPER_ID" -eq 1 ]]; then
    echo "Next:  ./notarize.sh   # submits to Apple and staples the ticket"
fi
