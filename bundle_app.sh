#!/bin/bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

DEFAULT_VERSION=$(sed -nE 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$ROOT_DIR/Cargo.toml" | head -n 1)
VERSION="${1:-${DEFAULT_VERSION:-0.3.0}}"

APP_DIR="Velora.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"

mkdir -p "$MACOS" "$RESOURCES" "$FRAMEWORKS"

# Copy binary (remove old inode first to avoid 'Text file busy' if running)
rm -f "$MACOS/Velora"
CANDIDATES=(
    "swift/.build/arm64-apple-macosx/release/Velora"
    "swift/.build/release/Velora"
    "swift/.build/arm64-apple-macosx/debug/Velora"
    "swift/.build/debug/Velora"
)
NEWEST_FILE=""
for cand in "${CANDIDATES[@]}"; do
    if [ -f "$cand" ]; then
        if [ -z "$NEWEST_FILE" ] || [ "$cand" -nt "$NEWEST_FILE" ]; then
            NEWEST_FILE="$cand"
        fi
    fi
done

if [ -n "$NEWEST_FILE" ]; then
    echo "📦 Bundling newest binary: $NEWEST_FILE"
    cp "$NEWEST_FILE" "$MACOS/Velora"
else
    echo "❌ Error: Velora binary not found. Please compile with 'swift build --arch arm64' first."
    exit 1
fi

# Copy Sparkle.framework for auto-updates
rm -rf "$FRAMEWORKS/Sparkle.framework"
if [ -d "swift/.build/arm64-apple-macosx/release/Sparkle.framework" ]; then
    cp -R "swift/.build/arm64-apple-macosx/release/Sparkle.framework" "$FRAMEWORKS/"
elif [ -d "swift/.build/release/Sparkle.framework" ]; then
    cp -R "swift/.build/release/Sparkle.framework" "$FRAMEWORKS/"
elif [ -d "swift/.build/arm64-apple-macosx/debug/Sparkle.framework" ]; then
    cp -R "swift/.build/arm64-apple-macosx/debug/Sparkle.framework" "$FRAMEWORKS/"
elif [ -d "swift/.build/debug/Sparkle.framework" ]; then
    cp -R "swift/.build/debug/Sparkle.framework" "$FRAMEWORKS/"
elif [ -d "swift/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" ]; then
    cp -R "swift/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$FRAMEWORKS/"
else
    echo "⚠️ Warning: Sparkle.framework not found in build directory."
fi

# Ensure executable can locate embedded frameworks via @executable_path/../Frameworks
if ! otool -l "$MACOS/Velora" | grep -F -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/Velora" 2>/dev/null || true
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
cat << EOF > "$CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Velora</string>
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
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSArchitecturePriority</key>
    <array>
        <string>arm64</string>
    </array>
    <key>LSRequiresNativeExecution</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Velora Contributors</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Velora needs access to scan and clean project artifacts on your Desktop.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Velora needs access to scan and clean project artifacts in Documents.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Velora needs access to scan and clean downloaded caches.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>Velora needs access to scan and clean project artifacts on external storage drives.</string>
    <key>NSNetworkVolumesUsageDescription</key>
    <string>Velora needs access to scan and clean project artifacts on network volumes.</string>
    <!-- Sparkle 2 Auto-Update Configuration -->
    <key>SUFeedURL</key>
    <string>https://github.com/ahmetaltun/Velora/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>u6Ia9qb88dLrJtaXLJ2vGVaq3PQk930yi5IxRduM/Ss=</string>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
    <key>SUEnableAutomaticChecks</key>
    <true/>
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

# Ad-hoc inside-out code signing for local execution
if [ -d "$FRAMEWORKS/Sparkle.framework" ]; then
    codesign --force --deep --sign - "$FRAMEWORKS/Sparkle.framework" 2>/dev/null || true
fi
codesign --force --sign - "$APP_DIR" 2>/dev/null || true

touch "$APP_DIR"
echo "✅ Velora.app created successfully!"
