#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="0.1.0"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
APP="dist/한영키 도우미.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN_DIR/HangeulKeyApp" "$APP/Contents/MacOS/HangeulKeyApp"
cp "$BIN_DIR/key-agent" "$APP/Contents/Helpers/key-agent"
cp resources/사용안내.html "$APP/Contents/Resources/사용안내.html"
/usr/bin/swift scripts/icon.swift "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.hangeulkey.helper</string>
<key>CFBundleName</key><string>한영키 도우미</string>
<key>CFBundleDisplayName</key><string>한영키 도우미</string>
<key>CFBundleExecutable</key><string>HangeulKeyApp</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
if [ -n "${SIGNING_IDENTITY:-}" ]; then
  /usr/bin/codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP/Contents/Helpers/key-agent"
  /usr/bin/codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
else
  /usr/bin/codesign --force --sign - "$APP/Contents/Helpers/key-agent"
  /usr/bin/codesign --force --sign - "$APP"
fi
/usr/bin/codesign --verify --deep --strict "$APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/HangeulKeyHelper-$VERSION-macOS.zip"
/usr/bin/shasum -a 256 "dist/HangeulKeyHelper-$VERSION-macOS.zip" > dist/SHA256SUMS
printf 'Built: %s\n' "$APP"
