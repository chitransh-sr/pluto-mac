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
    <string>com.raktimyoddha.pluto-mac</string>
    <key>CFBundleExecutable</key>
    <string>Pluto</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
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

codesign --force --sign - "$APP" 2>/dev/null || true

echo "✓ Built $APP"
