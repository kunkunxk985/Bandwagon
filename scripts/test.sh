#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
SWIFTC="$(xcrun --find swiftc)"
[[ -d "$SDKROOT" ]] || { printf 'Active Xcode macOS SDK missing\n' >&2; exit 1; }
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
ARGS=(-swift-version 6 -sdk "$SDKROOT" -target arm64-apple-macosx15.0)
# @Observable is an external macro. SwiftPM injects the plugin path itself, but a
# bare swiftc invocation does not, and fails with "ObservationMacros ... malformed
# response" on every file that uses it. Point at the toolchain's plugin directory.
PLUGINS="$(cd "$(dirname "$SWIFTC")/../lib/swift/host/plugins" 2>/dev/null && pwd || true)"
if [[ -n "$PLUGINS" && -d "$PLUGINS" ]]; then
  ARGS+=(-plugin-path "$PLUGINS")
fi
COMMON=(Sources/Bandwagon/Services/*.swift Sources/Bandwagon/Models/*.swift)
"$SWIFTC" "${ARGS[@]}" "${COMMON[@]}" Tests/HTTPRegression.swift -o "$OUT/http"
python3 Tests/http_fixture.py "$OUT/http"
"$SWIFTC" "${ARGS[@]}" "${COMMON[@]}" Tests/StateRegression.swift -o "$OUT/state"
"$OUT/state"

"$SWIFTC" "${ARGS[@]}" -parse-as-library \
  Sources/Bandwagon/Models/APIModels.swift \
  Tests/UsagePolicyRegression.swift -o "$OUT/usage-policy-regression"
"$OUT/usage-policy-regression"

"$SWIFTC" "${ARGS[@]}" -parse-as-library \
  Sources/Bandwagon/Views/Components/RomanCredentialField.swift \
  Tests/InputPolicyRegression.swift -o "$OUT/input-policy-regression"
"$OUT/input-policy-regression"

"$SWIFTC" "${ARGS[@]}" -parse-as-library \
  Sources/Bandwagon/Services/*.swift \
  Sources/Bandwagon/Models/*.swift \
  Tests/TrafficChartRegression.swift -o "$OUT/traffic-chart-regression"
"$OUT/traffic-chart-regression"

"$SWIFTC" "${ARGS[@]}" -parse-as-library \
  Sources/Bandwagon/Models/APIModels.swift \
  Sources/Bandwagon/Models/TrafficChartData.swift \
  Sources/Bandwagon/Models/TrafficForecast.swift \
  Tests/ForecastRegression.swift -o "$OUT/forecast-regression"
"$OUT/forecast-regression"

"$SWIFTC" "${ARGS[@]}" -parse-as-library \
  Sources/Bandwagon/Services/*.swift \
  Sources/Bandwagon/Models/*.swift \
  Tests/SettingsMigrationRegression.swift -o "$OUT/settings-migration-regression"
"$OUT/settings-migration-regression"

"$SWIFTC" "${ARGS[@]}" -parse-as-library \
  Sources/Bandwagon/Services/ProxyDiagnosis.swift \
  Sources/Bandwagon/Services/BWHClient.swift \
  Sources/Bandwagon/Services/JSONValue.swift \
  Sources/Bandwagon/Services/SecureURLPolicy.swift \
  Sources/Bandwagon/Services/SettingsStore.swift \
  Sources/Bandwagon/Services/KeychainCredentialStore.swift \
  Sources/Bandwagon/Services/CredentialBridgeClient.swift \
  Sources/Bandwagon/Models/*.swift \
  Tests/ProxyDiagnosisRegression.swift -o "$OUT/proxy-diagnosis-regression"
"$OUT/proxy-diagnosis-regression"

"$SWIFTC" "${ARGS[@]}" -parse-as-library \
  Tests/SecurityRegression.swift -o "$OUT/security-regression"
"$OUT/security-regression"

"$SWIFTC" "${ARGS[@]}" -parse-as-library \
  Tests/UICompositionRegression.swift -o "$OUT/ui-composition-regression"
"$OUT/ui-composition-regression"

# Credential bridge: wire format, digest pinning, ACL partitions, and the deployed
# helper's refusal of unsigned callers. This is the chain that keeps stored
# credentials readable across app re-signing, so it belongs in the default suite.
bash "$(dirname "$0")/test-credential-bridge.sh"

