#!/bin/bash
set -e

APP_DIR="Velora.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS" "$RESOURCES"

# Copy binary
cp swift/.build/debug/Velora "$MACOS/Velora"

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

touch "$APP_DIR"
echo "✅ Velora.app created successfully!"
