#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ICONSET="Resources/AppIcon.iconset"
ICNS="Resources/AppIcon.icns"

echo "==> Rendering iconset"
rm -rf "$ICONSET"
swift tools/make_icon.swift "$ICONSET"

echo "==> Compiling $ICNS"
iconutil -c icns "$ICONSET" -o "$ICNS"

echo "==> Cleaning up"
# Keep iconset around for inspection; comment the next line to discard it.
ls -la "$ICONSET" >/dev/null

echo ""
echo "Done. $ICNS ($(du -h "$ICNS" | cut -f1))"
