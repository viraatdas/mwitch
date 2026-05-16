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
if ! codesign -dv --verbose=2 "$APP" 2>&1 | grep -q "Developer ID Application"; then
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

echo ""
echo "Notarized + stapled."
echo "Drop the new build/mwitch.zip into mwitch-site/ and redeploy:"
echo "    cp build/mwitch.zip mwitch-site/mwitch.zip"
echo "    cd mwitch-site && vercel deploy --prod --yes"
