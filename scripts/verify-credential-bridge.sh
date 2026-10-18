#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="$HOME/Library/Application Support/Bandwagon"
HELPER="${1:-$INSTALL_DIR/BandwagonCredentialBridge}"
PIN="$(< "$ROOT/scripts/credential-bridge.sha256")"
REQUIREMENT='identifier "com.kun.bandwagon.credential-bridge" and certificate root = H"53b7c0537a374c6d02c9dd462b9f67a784aad7f1"'

[[ "$PIN" =~ ^[0-9a-f]{64}$ ]] || { printf 'Invalid helper release digest\n' >&2; exit 1; }
[[ ! -L "$HELPER" && -f "$HELPER" && -x "$HELPER" ]] || {
  printf 'Credential helper missing or not a regular executable: %s\n' "$HELPER" >&2; exit 1;
}
[[ "$(stat -f %u "$HELPER")" == "$(id -u)" ]] || { printf 'Credential helper owner mismatch\n' >&2; exit 1; }
MODE="$(stat -f %Lp "$HELPER")"
[[ "$MODE" == 700 || "$MODE" == 755 ]] || { printf 'Credential helper file permissions are unsafe\n' >&2; exit 1; }
if [[ "$(dirname "$HELPER")" == "$INSTALL_DIR" ]]; then
  [[ ! -L "$INSTALL_DIR" && "$(stat -f %u "$INSTALL_DIR")" == "$(id -u)" &&
     "$(stat -f %Lp "$INSTALL_DIR")" == 700 ]] || {
    printf 'Credential helper directory must be owned by user, mode 0700\n' >&2; exit 1;
  }
fi
ACTUAL="$(shasum -a 256 "$HELPER" | cut -d' ' -f1)"
[[ "$ACTUAL" == "$PIN" ]] || { printf 'Credential helper release digest mismatch\n' >&2; exit 1; }
codesign --verify --strict -R="$REQUIREMENT" "$HELPER"
printf 'Verified unchanged signed credential helper: %s\n' "$HELPER"
