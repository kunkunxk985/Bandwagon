#!/usr/bin/env bash
set -euo pipefail
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
export PATH="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
[[ -d "$SDKROOT" ]] || { printf 'Active Xcode macOS SDK missing\n' >&2; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$HOME/Desktop/Bandwagon.app"
ICONSET="$ROOT/packaging/macos/icon.iconset"
PACKAGING_DIR="$ROOT/.build/packaging"
STAGE="$PACKAGING_DIR/Bandwagon.app"
ICNS="$PACKAGING_DIR/AppIcon.icns"
SIGNER="${BANDWAGON_SIGNING_IDENTITY:-Bandwagon Local Code Signing}"

cleanup() { rm -rf "$PACKAGING_DIR"; }
trap cleanup EXIT

cd "$ROOT"
bash "$ROOT/scripts/verify-credential-bridge.sh"
swift build -c release --disable-sandbox
BIN="$(swift build -c release --disable-sandbox --show-bin-path)/Bandwagon"

rm -rf "$PACKAGING_DIR"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN" "$STAGE/Contents/MacOS/Bandwagon"
chmod +x "$STAGE/Contents/MacOS/Bandwagon"
printf 'APPL????' > "$STAGE/Contents/PkgInfo"

if [[ -d "$ICONSET" ]]; then
  iconutil -c icns "$ICONSET" -o "$ICNS"
  cp "$ICNS" "$STAGE/Contents/Resources/AppIcon.icns"
fi

cat > "$STAGE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Bandwagon</string>
    <key>CFBundleDisplayName</key>
    <string>Bandwagon</string>
    <key>CFBundleIdentifier</key>
    <string>com.kun.bandwagon</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>CFBundleShortVersionString</key>
    <string>3.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>Bandwagon</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

xattr -cr "$STAGE" 2>/dev/null || true
codesign --force --deep --sign "$SIGNER" "$STAGE"
codesign --verify --deep --strict "$STAGE"
[[ -f "$STAGE/Contents/Resources/AppIcon.icns" ]] || { printf 'AppIcon.icns missing\n' >&2; exit 1; }
rm -rf "$APP"
mv "$STAGE" "$APP"
echo "Built: $APP (signed with $SIGNER)"
