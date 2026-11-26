#!/bin/bash
# Build ClearMMR.app trực tiếp bằng swiftc — không cần Xcode, không cần SwiftPM.
# Usage: scripts/build-app.sh [version]   (mặc định: git tag gần nhất, fallback 1.0)
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
fi
VERSION="${VERSION:-1.0}"

BIN_DIR=".build"
APP="build/ClearMMR.app"

echo "==> Version: $VERSION"
echo "==> swiftc -O universal (arm64 + x86_64, macOS 13+)"
mkdir -p "$BIN_DIR"
for ARCH in arm64 x86_64; do
    swiftc -O -module-name ClearMMR \
        -target "${ARCH}-apple-macosx13.0" \
        -o "$BIN_DIR/ClearMMR-${ARCH}" \
        Sources/ClearMMR/*.swift
done
lipo -create "$BIN_DIR/ClearMMR-arm64" "$BIN_DIR/ClearMMR-x86_64" \
    -output "$BIN_DIR/ClearMMR"

echo "==> Tạo bundle $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/ClearMMR" "$APP/Contents/MacOS/ClearMMR"
chmod +x "$APP/Contents/MacOS/ClearMMR"

cat > "$APP/Contents/Info.plist" <<PLIST
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
    <string>${VERSION}</string>
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

echo "==> Ký ad-hoc + verify"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=1 "$APP"

echo "==> Xong: $APP (v$VERSION)"
echo "    Chạy thử: open $APP"
echo "    Copy vào Applications: cp -R $APP /Applications/"
