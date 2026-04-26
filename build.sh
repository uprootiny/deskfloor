#!/bin/bash
set -e

APP_DIR=~/Applications/builds/Deskfloor.app
BINARY="$APP_DIR/Contents/MacOS/Deskfloor"

echo "Building Deskfloor (release)..."
swift build -c release

echo "Updating .app bundle..."
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp .build/release/Deskfloor "$BINARY"

# Info.plist (create if missing)
if [ ! -f "$APP_DIR/Contents/Info.plist" ]; then
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Deskfloor</string>
    <key>CFBundleIdentifier</key><string>art.dissemblage.deskfloor</string>
    <key>CFBundleName</key><string>Deskfloor</string>
    <key>CFBundleDisplayName</key><string>Deskfloor</string>
    <key>CFBundleVersion</key><string>0.3.0</string>
    <key>CFBundleShortVersionString</key><string>0.3.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>NSAppleEventsUsageDescription</key><string>Deskfloor needs to control terminal apps (Ghostty / iTerm / Terminal) to spawn Claude sessions and SSH connections.</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
fi

# MUST sign after copying binary — macOS kills unsigned modified binaries
echo "Signing..."
codesign --force --sign - "$APP_DIR"
xattr -cr "$APP_DIR"

echo "Done: $APP_DIR"
echo "Launch: open $APP_DIR"
