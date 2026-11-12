#!/usr/bin/env bash
set -euo pipefail
#
# 从源码产出一份新的凭据辅助程序发布件。
#
# 这个脚本**不会**、也**不能**替换已经安装的辅助程序：
#   - 安装件的摘要被三处锁定；
#   - 钥匙串条目的 ACL 绑定在它的 cdhash 上。
# 换掉已安装的辅助程序会让所有已保存的凭据失效，必须由人明确决定。
# 所以这里只负责产出候选发布件，并把需要同步的地方打印出来。
#
# 用法：
#   build-credential-bridge.sh v2                 产出 ReleaseAssets/BandwagonCredentialBridge-v2
#   build-credential-bridge.sh v2 --update-pin    同时改写三处摘要锁定
#
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=xcode-env.sh
source "$ROOT/scripts/xcode-env.sh"
xcode_env

SIGNER="${BANDWAGON_SIGNING_IDENTITY:-Bandwagon Local Code Signing}"
IDENTIFIER="com.kun.bandwagon.credential-bridge"
REQUIREMENT="identifier \"$IDENTIFIER\" and certificate root = H\"53b7c0537a374c6d02c9dd462b9f67a784aad7f1\""

VERSION="${1:-}"
UPDATE_PIN="${2:-}"
[[ "$VERSION" =~ ^v[0-9]+$ ]] || { printf 'Usage: %s v<N> [--update-pin]\n' "$0" >&2; exit 2; }
[[ -z "$UPDATE_PIN" || "$UPDATE_PIN" == '--update-pin' ]] || { printf 'Unknown flag: %s\n' "$UPDATE_PIN" >&2; exit 2; }

RELEASE="$ROOT/ReleaseAssets/BandwagonCredentialBridge-$VERSION"
[[ ! -e "$RELEASE" ]] || { printf 'Refusing to overwrite existing release: %s\n' "$RELEASE" >&2; exit 1; }

# 刻意不传 -sdk / -target：已有的 v1 发布件是用默认 target 构建的（LC_BUILD_VERSION
# minos 27.0），而 test-credential-bridge.sh 构建夹具辅助程序时也是裸调 xcrun swiftc。
# 强制指定目标会改变可用性判定与内联，产出的 __TEXT 段与既有发布件不一致。
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
BUILT="$OUT/BandwagonCredentialBridge"

xcrun swiftc -O -swift-version 6 \
  "$ROOT/Sources/BandwagonCredentialBridge/main.swift" -o "$BUILT"
codesign --force --sign "$SIGNER" --identifier "$IDENTIFIER" "$BUILT"
codesign --verify --strict -R="$REQUIREMENT" "$BUILT"

cp "$BUILT" "$RELEASE"
chmod 755 "$RELEASE"
DIGEST="$(shasum -a 256 "$RELEASE" | cut -d' ' -f1)"

printf '\nBuilt release asset\n  path    %s\n  digest  %s\n\n' "$RELEASE" "$DIGEST"

if [[ "$UPDATE_PIN" == '--update-pin' ]]; then
  printf '%s\n' "$DIGEST" > "$ROOT/scripts/credential-bridge.sha256"
  perl -pi -e "s/helperSHA256 = \"[0-9a-f]{64}\"/helperSHA256 = \"$DIGEST\"/" \
    "$ROOT/Sources/Bandwagon/Services/KeychainCredentialStore.swift"
  bash "$ROOT/scripts/verify-credential-bridge.sh" "$RELEASE"
  printf 'Pins updated in scripts/credential-bridge.sha256 and KeychainCredentialStore.swift\n\n'
else
  printf 'Three pins must be updated to adopt this build:\n'
  printf '  1. scripts/credential-bridge.sha256\n'
  printf '  2. Sources/Bandwagon/Services/KeychainCredentialStore.swift  (helperSHA256)\n'
  printf '  3. ReleaseAssets/BandwagonCredentialBridge-%s\n' "$VERSION"
  printf '  Re-run with --update-pin to rewrite 1 and 2.\n\n'
fi

printf 'Reminder: replacing the installed helper invalidates the Keychain ACL.\n'
printf 'Credentials will have to be re-entered once, and the old Keychain item\n'
printf 'keeps its ACL until deleted. install-credential-bridge.sh refuses to\n'
printf 'replace a helper that already owns a v3 item.\n'
