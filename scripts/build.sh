#!/bin/bash
# Pluto for Mac — build + app assembly. Produces out/Pluto.app (no Xcode needed; uses the macOS Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ Building (swiftc, release)…"
mkdir -p out
swiftc -O -swift-version 5 Sources/PlutoMac/*.swift -o /tmp/PlutoMac-bin

APP="out/Pluto.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

/bin/cp /tmp/PlutoMac-bin "$APP/Contents/MacOS/Pluto"

# Build the app icon from the source PNG.
if [ -f Resources/PlutoIcon.png ]; then
    echo "▸ Building app icon…"
    mkdir -p /tmp/Pluto.iconset
    sips -s format png -z 16 16     Resources/PlutoIcon.png --out /tmp/Pluto.iconset/icon_16x16.png     2>/dev/null
    sips -s format png -z 32 32     Resources/PlutoIcon.png --out /tmp/Pluto.iconset/icon_16x16@2x.png  2>/dev/null
    sips -s format png -z 32 32     Resources/PlutoIcon.png --out /tmp/Pluto.iconset/icon_32x32.png     2>/dev/null
    sips -s format png -z 64 64     Resources/PlutoIcon.png --out /tmp/Pluto.iconset/icon_32x32@2x.png   2>/dev/null
    sips -s format png -z 48 48     Resources/PlutoIcon.png --out /tmp/Pluto.iconset/icon_48x48.png     2>/dev/null
    sips -s format png -z 96 96     Resources/PlutoIcon.png --out /tmp/Pluto.iconset/icon_48x48@2x.png   2>/dev/null
    sips -s format png -z 128 128   Resources/PlutoIcon.png --out /tmp/Pluto.iconset/icon_128x128.png  2>/dev/null
    sips -s format png -z 256 256   Resources/PlutoIcon.png --out /tmp/Pluto.iconset/icon_128x128@2x.png 2>/dev/null
    sips -s format png -z 256 256   Resources/PlutoIcon.png --out /tmp/Pluto.iconset/icon_256x256.png  2>/dev/null
    sips -s format png -z 512 512   Resources/PlutoIcon.png --out /tmp/Pluto.iconset/icon_256x256@2x.png 2>/dev/null
    sips -s format png -z 512 512   Resources/PlutoIcon.png --out /tmp/Pluto.iconset/icon_512x512.png  2>/dev/null
    sips -s format png -z 1024 1024 Resources/PlutoIcon.png --out /tmp/Pluto.iconset/icon_512x512@2x.png 2>/dev/null
    iconutil -c icns /tmp/Pluto.iconset -o "$APP/Contents/Resources/Pluto.icns"
    rm -rf /tmp/Pluto.iconset
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Pluto</string>
    <key>CFBundleDisplayName</key>
    <string>Pluto</string>
    <key>CFBundleIdentifier</key>
    <string>com.chitransh-sr.pluto-mac</string>
    <key>CFBundleExecutable</key>
    <string>Pluto</string>
    <key>CFBundleIconFile</key>
    <string>Pluto</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.5</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Pluto brings an agent's app forward when you click its session in the list.</string>
    <key>NSHumanReadableCopyright</key>
    <string>MIT — adapted from Pluto for Windows by raktim-yoddha.</string>
</dict>
</plist>
PLIST

codesign --force --entitlements Pluto.entitlements --sign - "$APP" 2>/dev/null || \
    codesign --force --sign - "$APP" 2>/dev/null || true

echo "✓ Built $APP"
