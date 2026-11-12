#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=xcode-env.sh
source "$ROOT_DIR/scripts/xcode-env.sh"
xcode_env
ROOT="$ROOT_DIR"
APP="$HOME/Desktop/Bandwagon.app"
ICONSET="$ROOT/packaging/icon.iconset"
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
cp -p "$ROOT/ReleaseAssets/BandwagonCredentialBridge-v1" "$STAGE/Contents/Resources/BandwagonCredentialBridge"
chmod 700 "$STAGE/Contents/Resources/BandwagonCredentialBridge"

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
[[ -f "$STAGE/Contents/Resources/BandwagonCredentialBridge" ]] || { printf 'Embedded BandwagonCredentialBridge missing\n' >&2; exit 1; }
rm -rf "$APP"
mv "$STAGE" "$APP"
SYSTEM_APP="/Applications/Bandwagon.app"
rm -rf "$SYSTEM_APP"
cp -R "$APP" "$SYSTEM_APP"
echo "Built: $APP and installed to $SYSTEM_APP (signed with $SIGNER)"
