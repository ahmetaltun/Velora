#!/bin/bash
set -e

APP_DIR="Velora.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS" "$RESOURCES"

# Copy binary (remove old inode first to avoid 'Text file busy' if running)
rm -f "$MACOS/Velora"
if [ -f "swift/.build/arm64-apple-macosx/debug/Velora" ]; then
    cp "swift/.build/arm64-apple-macosx/debug/Velora" "$MACOS/Velora"
elif [ -f "swift/.build/debug/Velora" ]; then
    cp "swift/.build/debug/Velora" "$MACOS/Velora"
else
    echo "❌ Error: Velora debug binary not found. Please compile with 'swift build --arch arm64' first."
    exit 1
fi

# Copy app icon and image assets if available
if [ -f "assets/icons/AppIcon.icns" ]; then
    cp assets/icons/AppIcon.icns "$RESOURCES/AppIcon.icns"
fi
if [ -f "assets/icons/AppIcon.png" ]; then
    cp assets/icons/AppIcon.png "$RESOURCES/AppIcon.png"
fi
for icon_asset in assets/icons/VeloraIcon-*.png; do
    if [ -f "$icon_asset" ]; then
        cp "$icon_asset" "$RESOURCES/"
    fi
done

# Create Info.plist
cat << 'EOF' > "$CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Velora</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.velora.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Velora</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSArchitecturePriority</key>
    <array>
        <string>arm64</string>
    </array>
    <key>LSRequiresNativeExecution</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

chmod +x "$MACOS/Velora"

# Validate Apple Silicon (arm64) architecture exclusivity
BINARY_ARCHS=$(lipo -archs "$MACOS/Velora")
if [ "$BINARY_ARCHS" != "arm64" ]; then
    echo "❌ Error: Binary must be strictly Apple Silicon (arm64). Found: $BINARY_ARCHS"
    exit 1
fi
echo "✅ Architecture verified: Apple Silicon (arm64)."

# Validate macOS 15+ minimum OS requirement
MIN_OS=$(otool -l "$MACOS/Velora" | awk '/LC_BUILD_VERSION/{getline; getline; getline; print $2}')
if [ -n "$MIN_OS" ]; then
    MAJOR_OS=$(echo "$MIN_OS" | cut -d. -f1)
    if [ "$MAJOR_OS" -lt 15 ]; then
        echo "❌ Error: Binary minimum OS requirement is $MIN_OS, but must be 15.0 (Sequoia) or later."
        exit 1
    fi
    echo "✅ Minimum OS verified: macOS $MIN_OS (Sequoia+)."
fi

touch "$APP_DIR"
echo "✅ Velora.app created successfully!"
