#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
XIABB_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$SCRIPT_DIR/build"
APP_DIR="$BUILD_DIR/XiaBB.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

VERSION=$(cat "$XIABB_DIR/VERSION" 2>/dev/null || echo "0.0.0")
echo "🦞 Building XiaBB v${VERSION}..."

# Clean
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS" "$RESOURCES"

# Compile
echo "   Compiling Swift..."
swiftc -O \
    -o "$MACOS/XiaBB" \
    -framework AppKit \
    -framework AVFoundation \
    -framework CoreGraphics \
    -framework CoreAudio \
    -framework WebKit \
    -target arm64-apple-macosx14.0 \
    "$SCRIPT_DIR/main.swift"

echo "   Binary size: $(du -h "$MACOS/XiaBB" | cut -f1)"

# Info.plist
cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>XiaBB</string>
    <key>CFBundleDisplayName</key>
    <string>XiaBB</string>
    <key>CFBundleIdentifier</key>
    <string>com.xiabb</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>XiaBB</string>
    <key>CFBundleIconFile</key>
    <string>XiaBB</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>XiaBB needs microphone access to record your voice for transcription.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>XiaBB needs to simulate keyboard input to paste transcribed text.</string>
</dict>
</plist>
PLIST

# Copy icons
for icon in icon.png icon@2x.png icon@3x.png icon-red.png icon-red@2x.png icon-red@3x.png XiaBB.icns; do
    if [ -f "$XIABB_DIR/$icon" ]; then
        cp "$XIABB_DIR/$icon" "$RESOURCES/"
    fi
done

# Code sign with stable identity (preserves TCC permissions across rebuilds)
echo "   Code signing..."
SIGN_ID=$(security find-identity -v -p codesigning | head -1 | sed 's/.*"\(.*\)"/\1/')
if [ -n "$SIGN_ID" ] && [ "$SIGN_ID" != "0 valid identities found" ]; then
    codesign --force --deep --sign "$SIGN_ID" "$APP_DIR"
    echo "   Signed with: $SIGN_ID"
else
    codesign --force --deep --sign - "$APP_DIR"
    echo "   Signed ad-hoc (no developer identity found)"
fi

echo ""
echo "✅ Built: $APP_DIR"

# Install to /Applications — update in-place to preserve permissions
INSTALL_DIR="/Applications/XiaBB.app"
if [ -d "$INSTALL_DIR" ]; then
    echo "   Updating existing install..."
    cp "$MACOS/XiaBB" "$INSTALL_DIR/Contents/MacOS/XiaBB"
    cp "$CONTENTS/Info.plist" "$INSTALL_DIR/Contents/Info.plist"
    cp -f "$RESOURCES"/* "$INSTALL_DIR/Contents/Resources/" 2>/dev/null
    # Re-sign with same identity to keep TCC permissions valid
    SIGN_ID=$(security find-identity -v -p codesigning | head -1 | sed 's/.*"\(.*\)"/\1/')
    if [ -n "$SIGN_ID" ] && [ "$SIGN_ID" != "0 valid identities found" ]; then
        codesign --force --deep --sign "$SIGN_ID" "$INSTALL_DIR"
    else
        codesign --force --deep --sign - "$INSTALL_DIR"
    fi
    echo "   ✅ Updated /Applications/XiaBB.app"
else
    echo "   Fresh install to /Applications..."
    cp -R "$APP_DIR" "$INSTALL_DIR"
    echo "   ✅ Installed /Applications/XiaBB.app"
fi
echo ""
echo "To run:  open /Applications/XiaBB.app"
