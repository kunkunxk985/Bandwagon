#!/usr/bin/env bash
# Wrap Bandwagon.app in a drag-to-Applications DMG.
set -euo pipefail
APP="${1:?Usage: package-dmg.sh /path/to/Bandwagon.app [output.dmg]}"
OUT="${2:-$(dirname "$APP")/Bandwagon-macOS.dmg}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/$(basename "$APP")"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT"
hdiutil create -volname "Bandwagon" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
echo "DMG: $OUT"
