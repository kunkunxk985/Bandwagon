#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=xcode-env.sh
source "$ROOT/scripts/xcode-env.sh"
xcode_env
SIGNER="${BANDWAGON_SIGNING_IDENTITY:-Bandwagon Local Code Signing}"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  if [[ ! -f "$LOGIN_KEYCHAIN" ]]; then
    printf 'Skipping credential bridge tests: login keychain unavailable on CI runner\n'
    exit 0
  fi
  if ! security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$SIGNER"; then
    printf 'Skipping credential bridge tests: %s not available on CI runner\n' "$SIGNER"
    exit 0
  fi
fi
INSTALL_DIR="$HOME/Library/Application Support/Bandwagon"
INSTALLED="$INSTALL_DIR/BandwagonCredentialBridge"
OUT="$(mktemp -d)"
SERVICE="com.kun.bandwagon.credentials.bridge-fixture.$(uuidgen)"
cleanup() {
  security delete-generic-password -s "$SERVICE" -a fixture >/dev/null 2>&1 || true
  security delete-generic-password -s "$SERVICE.legacy" -a fixture >/dev/null 2>&1 || true
  rm -rf "$OUT"
}
trap cleanup EXIT
export BANDWAGON_BRIDGE_TEST_SERVICE="$SERVICE"

# 1. Protocol fixture: a throwaway signed helper and signed parent exercise the
#    wire format, the digest pin, and the per-item ACL partition without ever
#    touching the real credential item.
xcrun swiftc -O -swift-version 6 -D BRIDGE_FIXTURE \
  "$ROOT/Sources/BandwagonCredentialBridge/main.swift" -o "$OUT/BandwagonCredentialBridge"
codesign --force --sign "$SIGNER" \
  --identifier com.kun.bandwagon.credential-bridge "$OUT/BandwagonCredentialBridge"
xcrun swiftc -O -swift-version 6 -parse-as-library \
  "$ROOT/Sources/Bandwagon/Services/CredentialBridgeClient.swift" \
  "$ROOT/Tests/CredentialBridgeFixtureRegression.swift" -o "$OUT/BandwagonBridgeFixtureParent"
codesign --force --sign "$SIGNER" \
  --identifier com.kun.bandwagon "$OUT/BandwagonBridgeFixtureParent"
DIGEST="$(shasum -a 256 "$OUT/BandwagonCredentialBridge" | cut -d' ' -f1)"
"$OUT/BandwagonBridgeFixtureParent" "$OUT/BandwagonCredentialBridge" "$DIGEST"
python3 - "$SERVICE" <<'PY'
import os, subprocess, sys
service = sys.argv[1]
keychain = os.path.expanduser('~/Library/Keychains/login.keychain-db')
result = subprocess.run(['security', 'dump-keychain', '-a', keychain],
                        capture_output=True, text=True, timeout=45)
if result.returncode:
    sys.exit('FAIL could not inspect fixture ACL metadata')
import re
text = result.stdout
for target in (service, service + '.legacy'):
    # Match the item's service attribute, not the same prefix inside ACL descriptions.
    marker = '"svce"<blob>="' + target + '"'
    position = text.find(marker)
    if position < 0:
        sys.exit('FAIL fixture item missing from Keychain metadata')
    start = text.rfind('keychain:', 0, position)
    end = text.find('keychain:', position)
    block = text[max(start, 0):end if end >= 0 else len(text)]
    partition = re.search(r'authorizations \(1\): partition_id\s+don.t-require-password\s+description: cdhash:([0-9a-fA-F]+)', block)
    if partition is None or 'description: unsigned:' in block or 'description: apple-tool:' in block:
        sys.exit('FAIL fixture ACL is not limited to helper cdhash')
print('PASS fixture and legacy ACLs have restricted cdhash partitions')
PY

# 2. Deployed helper. Only meaningful once it is installed, so a fresh checkout
#    still passes the suite without one.
if [[ -x "$INSTALLED" ]]; then
  xcrun swiftc -O -swift-version 6 -parse-as-library \
    "$ROOT/Tests/CredentialHelperRegression.swift" -o "$OUT/CredentialHelperRegression"
  "$OUT/CredentialHelperRegression"
  python3 "$ROOT/scripts/verify-credential-bridge-acl.py"
else
  printf 'Credential helper not installed; skipping deployed-helper checks\n'
fi

