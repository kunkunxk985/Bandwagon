#!/usr/bin/env bash
# Regenerates packaging/macos/icon.iconset and icon.png from MakeIcon.swift.
set -euo pipefail
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -parse-as-library -O "$ROOT/packaging/macos/MakeIcon.swift" -o "$OUT/make-icon"
"$OUT/make-icon" "$ROOT/packaging/macos"
