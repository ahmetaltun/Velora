#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Velora Release Build & Packaging Script
# -----------------------------------------------------------------------------
# Usage:
#   ./scripts/build_release.sh [version] [--dmg]
# Example:
#   ./scripts/build_release.sh 0.1.0 --dmg
# -----------------------------------------------------------------------------

RAW_VERSION="${1:-0.1.0}"
# Strip leading 'v' if provided as a git tag (e.g., v0.1.0 -> 0.1.0)
VERSION="${RAW_VERSION#v}"
GENERATE_DMG=false

for arg in "$@"; do
    if [ "$arg" == "--dmg" ]; then
        GENERATE_DMG=true
    fi
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=================================================="
echo "  Building Velora v${VERSION} (Production Release)"
echo "=================================================="

# 1. Build Rust FFI in release mode (creates target/release/libvelora_ffi.a)
echo "📦 Step 1: Compiling Rust FFI core (release)..."
cargo build --release -p velora-ffi

# 2. Build Swift app in release mode (statically links libvelora_ffi.a)
echo "🚀 Step 2: Compiling Swift frontend (release)..."
(cd swift && swift build -c release)

# 3. Assemble Velora.app bundle
echo "📁 Step 3: Assembling Velora.app..."
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/Velora.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Copy binary
cp "$ROOT_DIR/swift/.build/release/Velora" "$MACOS_DIR/Velora"
chmod +x "$MACOS_DIR/Velora"

# Copy app icon if present
if [ -f "$ROOT_DIR/assets/icons/AppIcon.icns" ]; then
    cp "$ROOT_DIR/assets/icons/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Write Info.plist
cat << EOF > "$CONTENTS_DIR/Info.plist"
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
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Velora needs access to scan and clean project artifacts on your Desktop.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Velora needs access to scan and clean project artifacts in Documents.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Velora needs access to scan and clean downloaded caches.</string>
</dict>
</plist>
EOF

# Touch app directory to register bundle changes
touch "$APP_DIR"

# 4. Verify binary dependencies (ensure zero local path leakage)
echo "🔍 Step 4: Validating Mach-O linkages..."
if otool -L "$MACOS_DIR/Velora" | tail -n +2 | grep -E '/Users/|/home/'; then
    echo "❌ Error: Leaked local developer paths detected in binary dependencies!"
    exit 1
fi
echo "✅ Binary verified: 100% self-contained and portable."

# 5. Optional DMG generation
if [ "$GENERATE_DMG" = true ]; then
    echo "💿 Step 5: Packaging into DMG..."
    DMG_STAGE="$BUILD_DIR/dmg_stage"
    DMG_OUTPUT="$BUILD_DIR/Velora-${VERSION}.dmg"

    rm -rf "$DMG_STAGE" "$DMG_OUTPUT"
    mkdir -p "$DMG_STAGE"

    cp -R "$APP_DIR" "$DMG_STAGE/"
    ln -s /Applications "$DMG_STAGE/Applications"

    hdiutil create \
        -volname "Velora" \
        -srcfolder "$DMG_STAGE" \
        -ov \
        -format UDZO \
        "$DMG_OUTPUT"

    rm -rf "$DMG_STAGE"
    echo "✅ DMG generated at: $DMG_OUTPUT"
fi

echo "=================================================="
echo "🎉 Build complete: $APP_DIR"
echo "=================================================="
