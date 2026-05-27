#!/usr/bin/env bash
set -euo pipefail

# Submits build/mwitch.app to Apple's notary service, waits for the result,
# and staples the notarization ticket so the app launches on any Mac without
# the "unidentified developer" Gatekeeper warning.
#
# Prerequisite: a "Developer ID Application" certificate in the keychain
# (build.sh already auto-detects + signs with it). Plus a one-time creds
# profile stored under the keychain name "mwitch-notary":
#
#   xcrun notarytool store-credentials mwitch-notary \
#       --apple-id "you@example.com" \
#       --team-id  "YOURTEAMID" \
#       --password "app-specific-password"     # from appleid.apple.com
#
# After this script finishes successfully, redeploy mwitch.zip with
#   cd mwitch-site && cp ../build/mwitch.zip . && vercel deploy --prod --yes

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/mwitch.app"
ZIP="$ROOT/build/mwitch-notarize.zip"
PROFILE="${MWITCH_NOTARY_PROFILE:-mwitch-notary}"

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
xcrun notarytool submit "$ZIP" \
    --keychain-profile "$PROFILE" \
    --wait

echo "==> Stapling ticket to $APP"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Refreshing distributable zip"
rm -f "$ROOT/build/mwitch.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/build/mwitch.zip"

# Build the Sparkle appcast from the notarized+stapled zip. generate_appcast
# reads the version from the app's Info.plist and signs the enclosure with the
# EdDSA private key in the keychain (created once via `generate_keys`). The
# archive is named mwitch.zip so the appcast enclosure points at the same
# /mwitch.zip the website download button serves.
echo "==> Generating Sparkle appcast"
GEN="$(find "$ROOT/.build/artifacts" -path "*/bin/generate_appcast" -type f | head -1)"
if [[ -z "$GEN" ]]; then
    echo "error: generate_appcast not found — run 'swift package resolve' and build first." >&2
    exit 1
fi
ACDIR="$ROOT/build/appcast"
rm -rf "$ACDIR"
mkdir -p "$ACDIR"
cp "$ROOT/build/mwitch.zip" "$ACDIR/mwitch.zip"
"$GEN" --download-url-prefix "https://mwitch.viraat.dev/" "$ACDIR"

echo "==> Staging appcast.xml + mwitch.zip into mwitch-site/"
cp "$ACDIR/appcast.xml" "$ROOT/mwitch-site/appcast.xml"
cp "$ROOT/build/mwitch.zip" "$ROOT/mwitch-site/mwitch.zip"

echo ""
echo "Notarized + stapled. appcast.xml + mwitch.zip staged in mwitch-site/."
echo "Deploy to push the update to all installed copies:"
echo "    cd mwitch-site && vercel deploy --prod --yes"
