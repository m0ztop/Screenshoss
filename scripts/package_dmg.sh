#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

ARM64_BUILD_DIR=".build/arm64-apple-macosx/release"
X86_64_BUILD_DIR=".build/x86_64-apple-macosx/release"
DIST_DIR="dist"
OUTPUT_APP_ZIP_PATH="$DIST_DIR/Screenshoss.app.zip"
OUTPUT_DMG_PATH="$DIST_DIR/Screenshoss.dmg"
PACKAGE_ROOT="/private/tmp/shoss-package"
APP_DIR="$PACKAGE_ROOT/Screenshoss.app"
STAGING_DIR="$PACKAGE_ROOT/staging"
APP_ZIP_PATH="$STAGING_DIR/Screenshoss.app.zip"
ICONSET_DIR="$STAGING_DIR/Screenshoss.iconset"
DMG_BACKGROUND_DIR="$STAGING_DIR/dmg-background"
DMG_MOUNT_DIR=""
DMG_ATTACH_PLIST_PATH="$STAGING_DIR/dmg-attach.plist"
DMG_RW_PATH="$STAGING_DIR/Screenshoss-rw.dmg"
DMG_PATH="$STAGING_DIR/Screenshoss.dmg"
NOTARY_ZIP_PATH="$STAGING_DIR/Screenshoss-notary.zip"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
NOTARY_WAIT_TIMEOUT="${NOTARY_WAIT_TIMEOUT:-30m}"
SIGNING_MODE="ad-hoc"
NOTARIZATION_MODE="disabled"

if [ "$CODESIGN_IDENTITY" != "-" ]; then
    SIGNING_MODE="Developer ID"
fi

if [ -n "$NOTARY_PROFILE" ]; then
    if [ "$CODESIGN_IDENTITY" = "-" ]; then
        echo "NOTARY_PROFILE requires a Developer ID CODESIGN_IDENTITY." >&2
        exit 1
    fi
    NOTARIZATION_MODE="Apple notary service"
fi

echo "=== Building release binaries (Apple Silicon + Intel) ==="
swift build -c release --triple arm64-apple-macosx13.0
swift build -c release --triple x86_64-apple-macosx13.0

echo "=== Preparing .app bundle ==="
rm -rf "$PACKAGE_ROOT" "$DIST_DIR/Screenshoss.app" "$DIST_DIR/Shoss.app" "$DIST_DIR/Shoss.app.zip"
rm -f "$DIST_DIR/Shoss.dmg"
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

if [ -n "$NOTARY_PROFILE" ]; then
    echo "=== Notarizing app bundle ($NOTARIZATION_MODE) ==="
    rm -f "$NOTARY_ZIP_PATH"
    ditto -c -k --norsrc --keepParent "$APP_DIR" "$NOTARY_ZIP_PATH"
    xcrun notarytool submit "$NOTARY_ZIP_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait \
        --timeout "$NOTARY_WAIT_TIMEOUT"
    xcrun stapler staple -v "$APP_DIR"
    xcrun stapler validate -v "$APP_DIR"
    spctl --assess --type execute --verbose=2 "$APP_DIR"
fi

echo "=== Creating DMG ==="
rm -f "$DMG_PATH" "$DMG_RW_PATH"
mkdir -p "$DMG_BACKGROUND_DIR"

echo "=== Drawing DMG background ==="
python3 - "$DMG_BACKGROUND_DIR/background.png" "$DMG_BACKGROUND_DIR/background@2x.png" << 'PY'
import os
import subprocess
import sys
import tempfile

OUT_1X, OUT_2X = sys.argv[1:3]
WIDTH, HEIGHT = 640, 400
TOP = (246, 247, 250)
BOTTOM = (229, 230, 238)
ARROW = (151, 151, 160)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def set_pixel(buf, width, height, x, y, color):
    if 0 <= x < width and 0 <= y < height:
        idx = (y * width + x) * 3
        buf[idx:idx + 3] = bytes(color)


def rect(buf, width, height, x0, y0, x1, y1, color):
    for y in range(max(0, y0), min(height, y1)):
        for x in range(max(0, x0), min(width, x1)):
            set_pixel(buf, width, height, x, y, color)


def render(scale, output_path):
    width, height = WIDTH * scale, HEIGHT * scale
    buf = bytearray(width * height * 3)

    for y in range(height):
        color = lerp(TOP, BOTTOM, y / max(1, height - 1))
        rect(buf, width, height, 0, y, width, y + 1, color)

    cy = 206 * scale
    start_x = 272 * scale
    end_x = 390 * scale
    line_height = max(3, 4 * scale)
    dash = 16 * scale
    gap = 12 * scale
    x = start_x
    while x < end_x:
        rect(buf, width, height, x, cy - line_height // 2, min(x + dash, end_x), cy + line_height // 2 + 1, ARROW)
        x += dash + gap

    fd, ppm_path = tempfile.mkstemp(suffix=".ppm")
    os.close(fd)
    with open(ppm_path, "wb") as ppm:
        ppm.write(f"P6\n{width} {height}\n255\n".encode("ascii"))
        ppm.write(buf)
    subprocess.run(["sips", "-s", "format", "png", ppm_path, "--out", output_path], check=True, stdout=subprocess.DEVNULL)
    os.remove(ppm_path)


render(1, OUT_1X)
render(2, OUT_2X)
PY

hdiutil create "$DMG_RW_PATH" -volname Screenshoss -size 100m -fs HFS+ -ov >/dev/null
rm -f "$DMG_ATTACH_PLIST_PATH"
hdiutil attach "$DMG_RW_PATH" -plist > "$DMG_ATTACH_PLIST_PATH"
DMG_MOUNT_DIR="$(python3 - "$DMG_ATTACH_PLIST_PATH" << 'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as plist_file:
    data = plistlib.load(plist_file)

for entity in data.get("system-entities", []):
    mount_point = entity.get("mount-point")
    if mount_point:
        print(mount_point)
        break
PY
)"
if [ -z "$DMG_MOUNT_DIR" ] || [ ! -d "$DMG_MOUNT_DIR" ]; then
    echo "Could not find mounted DMG volume." >&2
    exit 1
fi
DMG_FINDER_NAME="$(basename "$DMG_MOUNT_DIR")"
DMG_ATTACHED=1
cleanup_dmg_mount() {
    if [ "${DMG_ATTACHED:-0}" = "1" ] && [ -n "${DMG_MOUNT_DIR:-}" ]; then
        hdiutil detach "$DMG_MOUNT_DIR" -quiet || hdiutil detach "$DMG_MOUNT_DIR" -force -quiet || true
    fi
}
trap cleanup_dmg_mount EXIT

cp -R "$APP_DIR" "$DMG_MOUNT_DIR/"
ln -s /Applications "$DMG_MOUNT_DIR/Applications"
mkdir -p "$DMG_MOUNT_DIR/.background"
cp "$DMG_BACKGROUND_DIR/background.png" "$DMG_MOUNT_DIR/.background/background.png"
cp "$DMG_BACKGROUND_DIR/background@2x.png" "$DMG_MOUNT_DIR/.background/background@2x.png"
chflags hidden "$DMG_MOUNT_DIR/.background" || true

osascript - "$DMG_FINDER_NAME" << 'OSA'
on run argv
    set dmgName to item 1 of argv
    tell application "Finder"
        tell disk dmgName
            open
            delay 1
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set bounds of container window to {200, 120, 840, 520}
            set viewOptions to the icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 120
            set background picture of viewOptions to file ".background:background.png"
            set position of item "Screenshoss.app" of container window to {160, 205}
            set position of item "Applications" of container window to {480, 205}
            update without registering applications
            delay 1
            close
        end tell
    end tell
end run
OSA

if [ ! -f "$DMG_MOUNT_DIR/.DS_Store" ]; then
    echo "Finder did not save the custom DMG window layout." >&2
    exit 1
fi

sync
hdiutil detach "$DMG_MOUNT_DIR" -quiet || hdiutil detach "$DMG_MOUNT_DIR" -force -quiet
DMG_ATTACHED=0
trap - EXIT

hdiutil convert "$DMG_RW_PATH" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" -ov >/dev/null

if [ "$CODESIGN_IDENTITY" != "-" ]; then
    echo "=== Signing DMG ($SIGNING_MODE) ==="
    codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG_PATH"
fi

if [ -n "$NOTARY_PROFILE" ]; then
    echo "=== Notarizing DMG ($NOTARIZATION_MODE) ==="
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait \
        --timeout "$NOTARY_WAIT_TIMEOUT"
    xcrun stapler staple -v "$DMG_PATH"
    xcrun stapler validate -v "$DMG_PATH"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
fi

echo "=== Creating zipped app bundle ==="
ditto -c -k --norsrc --keepParent "$APP_DIR" "$APP_ZIP_PATH"

echo "=== Publishing verified release artifacts ==="
mkdir -p "$DIST_DIR"
mv -f "$APP_ZIP_PATH" "$OUTPUT_APP_ZIP_PATH"
mv -f "$DMG_PATH" "$OUTPUT_DMG_PATH"

echo "=== Cleaning up packaging workspace ==="
rm -rf "$PACKAGE_ROOT"

echo "=== Done ==="
echo "App ZIP: $OUTPUT_APP_ZIP_PATH"
echo "DMG: $OUTPUT_DMG_PATH"
echo "Signing: $SIGNING_MODE"
echo "Notarization: $NOTARIZATION_MODE"
