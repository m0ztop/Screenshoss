#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

ARM64_BUILD_DIR=".build/arm64-apple-macosx/release"
X86_64_BUILD_DIR=".build/x86_64-apple-macosx/release"
DIST_DIR="dist"
APP_ZIP_PATH="$DIST_DIR/Screenshoss.app.zip"
PACKAGE_ROOT="/private/tmp/shoss-package"
APP_DIR="$PACKAGE_ROOT/Screenshoss.app"
STAGING_DIR="$PACKAGE_ROOT/staging"
ICONSET_DIR="$STAGING_DIR/Screenshoss.iconset"
DMG_TMP_DIR="$STAGING_DIR/dmg"
DMG_PATH="$DIST_DIR/Screenshoss.dmg"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
SIGNING_MODE="ad-hoc"

if [ "$CODESIGN_IDENTITY" != "-" ]; then
    SIGNING_MODE="Developer ID"
fi

echo "=== Building release binaries (Apple Silicon + Intel) ==="
swift build -c release --triple arm64-apple-macosx13.0
swift build -c release --triple x86_64-apple-macosx13.0

echo "=== Preparing .app bundle ==="
rm -rf "$PACKAGE_ROOT" "$DIST_DIR/Screenshoss.app" "$APP_ZIP_PATH" "$DIST_DIR/Shoss.app" "$DIST_DIR/Shoss.app.zip"
rm -f "$DMG_PATH" "$DIST_DIR/Shoss.dmg"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$ICONSET_DIR"

echo "=== Copying startup sound ==="
cp Assets/app-start.MP3 "$APP_DIR/Contents/Resources/app-start.mp3"

echo "=== Creating universal app executable ==="
lipo -create \
    "$ARM64_BUILD_DIR/Shoss" \
    "$X86_64_BUILD_DIR/Shoss" \
    -output "$APP_DIR/Contents/MacOS/Shoss"
chmod +x "$APP_DIR/Contents/MacOS/Shoss"
lipo -archs "$APP_DIR/Contents/MacOS/Shoss"

echo "=== Generating .icns from Assets/macapp.png ==="
SRC_PNG="Assets/macapp.png"

sips -z 16 16   "$SRC_PNG" --out "$ICONSET_DIR/icon_16x16.png"
sips -z 32 32   "$SRC_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png"
sips -z 32 32   "$SRC_PNG" --out "$ICONSET_DIR/icon_32x32.png"
sips -z 64 64   "$SRC_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png"
sips -z 128 128 "$SRC_PNG" --out "$ICONSET_DIR/icon_128x128.png"
sips -z 256 256 "$SRC_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png"
sips -z 256 256 "$SRC_PNG" --out "$ICONSET_DIR/icon_256x256.png"
sips -z 512 512 "$SRC_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png"
sips -z 512 512 "$SRC_PNG" --out "$ICONSET_DIR/icon_512x512.png"
sips -z 1024 1024 "$SRC_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/Screenshoss.icns"

echo "=== Creating Info.plist ==="
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>Shoss</string>
	<key>CFBundleIdentifier</key>
	<string>com.mert.screenshoss</string>
	<key>CFBundleName</key>
	<string>Screenshoss</string>
	<key>CFBundleDisplayName</key>
	<string>Screenshoss</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleIconFile</key>
	<string>Screenshoss</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

echo "=== Signing app bundle ($SIGNING_MODE) ==="
xattr -cr "$APP_DIR" || true
if [ "$CODESIGN_IDENTITY" = "-" ]; then
    codesign --force --deep --sign - "$APP_DIR"
else
    codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_DIR"
fi
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "=== Creating DMG ==="
rm -f "$DMG_PATH"
mkdir -p "$DMG_TMP_DIR"
cp -R "$APP_DIR" "$DMG_TMP_DIR/"
ln -sf /Applications "$DMG_TMP_DIR/Applications"

hdiutil create -volname Screenshoss -srcfolder "$DMG_TMP_DIR" -ov -format UDZO "$DMG_PATH"

if [ "$CODESIGN_IDENTITY" != "-" ]; then
    echo "=== Signing DMG ($SIGNING_MODE) ==="
    codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG_PATH"
fi

echo "=== Creating zipped app bundle ==="
ditto -c -k --keepParent "$APP_DIR" "$APP_ZIP_PATH"

echo "=== Cleaning up packaging workspace ==="
rm -rf "$PACKAGE_ROOT"

echo "=== Done ==="
echo "App ZIP: $APP_ZIP_PATH"
echo "DMG: $DMG_PATH"
echo "Signing: $SIGNING_MODE"
