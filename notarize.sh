#!/usr/bin/env bash
set -euo pipefail

# Submits build/mwitch.app to Apple's notary service, waits for the result,
# and staples the notarization ticket so the app launches on any Mac without
# the "unidentified developer" Gatekeeper warning.
#
# Auth (two modes):
#   • Local: a one-time keychain creds profile "mwitch-notary":
#       xcrun notarytool store-credentials mwitch-notary \
#           --apple-id "you@example.com" --team-id "TEAMID" \
#           --password "app-specific-password"
#   • CI: set AC_API_KEY_PATH (path to App Store Connect .p8), AC_API_KEY_ID,
#     and AC_API_ISSUER_ID — used instead of the keychain profile.
#
# Sparkle appcast signing reads the EdDSA private key from the keychain by
# default; in CI set SPARKLE_ED_PRIVATE_KEY (the exported key string) and it's
# fed to generate_appcast via stdin instead.
#
# After this finishes, deploy with:
#   cd mwitch-site && vercel deploy --prod --yes

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/mwitch.app"
ZIP="$ROOT/build/mwitch-notarize.zip"
PROFILE="${MWITCH_NOTARY_PROFILE:-mwitch-notary}"
DOWNLOAD_URL_PREFIX="${MWITCH_DOWNLOAD_URL_PREFIX:-https://mwitch.viraat.dev/}"

case "$DOWNLOAD_URL_PREFIX" in
    */) ;;
    *) DOWNLOAD_URL_PREFIX="$DOWNLOAD_URL_PREFIX/" ;;
esac

if [[ ! -d "$APP" ]]; then
    echo "error: $APP not found. Run ./build.sh first." >&2
    exit 1
fi

echo "==> Verifying signature is Developer ID (notarization requires it)"
SIG_INFO="$(codesign -dv --verbose=2 "$APP" 2>&1 || true)"
if ! grep -q "Developer ID Application" <<<"$SIG_INFO"; then
    echo "error: $APP is not signed with a Developer ID Application cert." >&2
    echo "       Create one in Xcode → Settings → Accounts → Manage Certificates, then re-run ./build.sh." >&2
    exit 1
fi

echo "==> Zipping for submission"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> Submitting to Apple notary (this takes 1–10 min)"
if [[ -n "${AC_API_KEY_PATH:-}" ]]; then
    xcrun notarytool submit "$ZIP" \
        --key "$AC_API_KEY_PATH" \
        --key-id "$AC_API_KEY_ID" \
        --issuer "$AC_API_ISSUER_ID" \
        --wait
else
    xcrun notarytool submit "$ZIP" \
        --keychain-profile "$PROFILE" \
        --wait
fi

echo "==> Stapling ticket to $APP"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Refreshing distributable zip"
rm -f "$ROOT/build/mwitch.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/build/mwitch.zip"

# Build the Sparkle appcast from the notarized+stapled zip. generate_appcast
# reads the version from the app's Info.plist and signs the enclosure with the
# EdDSA private key (keychain locally, or SPARKLE_ED_PRIVATE_KEY via stdin in
# CI). The archive is named mwitch.zip so the appcast enclosure can point at
# either the website zip locally or the versioned GitHub Release asset in CI.
echo "==> Generating Sparkle appcast ($DOWNLOAD_URL_PREFIX)"
GEN="$(find "$ROOT/.build/artifacts" -path "*/bin/generate_appcast" -type f | head -1)"
if [[ -z "$GEN" ]]; then
    echo "error: generate_appcast not found — run 'swift package resolve' and build first." >&2
    exit 1
fi
ACDIR="$ROOT/build/appcast"
rm -rf "$ACDIR"
mkdir -p "$ACDIR"
cp "$ROOT/build/mwitch.zip" "$ACDIR/mwitch.zip"
if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
    printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$GEN" --ed-key-file - \
        --download-url-prefix "$DOWNLOAD_URL_PREFIX" "$ACDIR"
else
    "$GEN" --download-url-prefix "$DOWNLOAD_URL_PREFIX" "$ACDIR"
fi

echo "==> Staging appcast.xml into mwitch-site/"
cp "$ACDIR/appcast.xml" "$ROOT/mwitch-site/appcast.xml"

echo ""
echo "Notarized + stapled. appcast.xml staged in mwitch-site/."
echo "Deploy to push the update to all installed copies:"
echo "    cd mwitch-site && vercel deploy --prod --yes"
