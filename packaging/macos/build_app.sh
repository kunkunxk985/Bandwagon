#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
APP="$PWD/dist/Bandwagon.app"
CONTENTS="$APP/Contents"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
python3 packaging/macos/make_icon.py
iconutil -c icns packaging/macos/icon.iconset -o "$CONTENTS/Resources/AppIcon.icns"
cp packaging/macos/Info.plist "$CONTENTS/Info.plist"
cc -O2 -o "$CONTENTS/MacOS/Bandwagon" packaging/macos/launcher.c
chmod +x "$CONTENTS/MacOS/Bandwagon"
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
DEST="$HOME/Desktop/Bandwagon.app"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
echo "已生成 $APP"
echo "已复制到 $DEST"
