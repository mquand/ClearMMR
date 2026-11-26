#!/bin/bash
# Build ClearMMR.app trực tiếp bằng swiftc — không cần Xcode, không cần SwiftPM.
set -euo pipefail

cd "$(dirname "$0")/.."

BIN_DIR=".build"
BIN="$BIN_DIR/ClearMMR"
APP="build/ClearMMR.app"

echo "==> swiftc -O (macOS 13+)"
mkdir -p "$BIN_DIR"
swiftc -O -module-name ClearMMR \
    -target arm64-apple-macosx13.0 \
    -o "$BIN" \
    Sources/ClearMMR/*.swift

echo "==> Tạo bundle $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ClearMMR"
chmod +x "$APP/Contents/MacOS/ClearMMR"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>ClearMMR</string>
    <key>CFBundleDisplayName</key>
    <string>ClearMMR</string>
    <key>CFBundleIdentifier</key>
    <string>com.clearmmr.app</string>
    <key>CFBundleExecutable</key>
    <string>ClearMMR</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> Ký ad-hoc (để macOS coi là app hợp lệ, cần cho notification/login item)"
codesign --force --sign - "$APP"

echo "==> Xong: $APP"
echo "    Chạy thử: open $APP"
echo "    Copy vào Applications: cp -R $APP /Applications/"
