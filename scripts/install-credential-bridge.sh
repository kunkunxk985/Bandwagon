#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE="$ROOT/ReleaseAssets/BandwagonCredentialBridge-v1"
INSTALL_DIR="$HOME/Library/Application Support/Bandwagon"
INSTALLED="$INSTALL_DIR/BandwagonCredentialBridge"
STUB_SHA256='0bef1154ae5e82c26a48239ffa8a757e5c2569473dba527b4ae282448b7a4f57'

[[ $# -le 1 ]] || { printf 'Unexpected arguments\n' >&2; exit 2; }
bash "$ROOT/scripts/verify-credential-bridge.sh" "$RELEASE"
if [[ -e "$INSTALLED" ]]; then
  if bash "$ROOT/scripts/verify-credential-bridge.sh" "$INSTALLED" >/dev/null 2>&1; then
    printf 'Credential helper already installed; left unchanged\n'
    exit 0
  fi
  [[ "${1:-}" == '--replace-unused-stub' && ! -L "$INSTALLED" && -f "$INSTALLED" &&
     "$(shasum -a 256 "$INSTALLED" | cut -d' ' -f1)" == "$STUB_SHA256" ]] || {
    printf 'Refusing to replace an unknown or credential-bearing helper\n' >&2; exit 1;
  }
fi

# Metadata lookup only: never read an item's value. A v3 item means the old
# executable may own credentials and must not be replaced implicitly.
set +e
security find-generic-password -s 'com.kun.bandwagon.credentials.v3' -a default \
  "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1
FOUND_STATUS=$?
set -e
[[ "$FOUND_STATUS" -eq 44 ]] || {
  printf 'Refusing helper replacement: v3 item exists or its state cannot be checked\n' >&2; exit 1;
}
mkdir -p "$INSTALL_DIR"
chmod 700 "$INSTALL_DIR"
STAGE="$INSTALL_DIR/.BandwagonCredentialBridge.new.$$"
trap 'rm -f "$STAGE"' EXIT
cp -p "$RELEASE" "$STAGE"
chmod 700 "$STAGE"
bash "$ROOT/scripts/verify-credential-bridge.sh" "$STAGE"
mv -f "$STAGE" "$INSTALLED"
bash "$ROOT/scripts/verify-credential-bridge.sh" "$INSTALLED"
printf 'Installed fixed credential helper without rebuilding or resigning it\n'
printf 'Note: a packaged Bandwagon.app upgrade also refreshes the helper when its pinned digest differs from the on-disk copy.\n'
