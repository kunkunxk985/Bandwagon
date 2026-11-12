#!/usr/bin/env bash
# Regenerates packaging/icon.iconset from packaging/MakeIcon.swift.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=xcode-env.sh
source "$ROOT/scripts/xcode-env.sh"
xcode_env
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -parse-as-library -O "$ROOT/packaging/MakeIcon.swift" -o "$OUT/make-icon"
"$OUT/make-icon" "$ROOT/packaging"
