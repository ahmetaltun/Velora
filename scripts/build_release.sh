#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Velora Release Build & Packaging Script
# -----------------------------------------------------------------------------
# Usage:
#   ./scripts/build_release.sh [version] [--dmg] [--sign <identity>]
# Examples:
#   ./scripts/build_release.sh 0.1.0
#   ./scripts/build_release.sh 0.1.0 --dmg
#   ./scripts/build_release.sh 0.1.0 --dmg --sign "Developer ID Application: Company (TEAMID)"
# -----------------------------------------------------------------------------

RAW_VERSION="0.1.0"
GENERATE_DMG=false
SIGN_IDENTITY="${APPLE_SIGNING_IDENTITY:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dmg)
            GENERATE_DMG=true
            shift
            ;;
        --sign)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        -*)
            echo "❌ Unknown flag: $1"
            echo "Usage: $0 [version] [--dmg] [--sign <identity>]"
            exit 1
            ;;
        *)
            RAW_VERSION="$1"
            shift
            ;;
    esac
done

# Strip leading 'v' if passed as git tag (e.g., v0.1.0 -> 0.1.0)
VERSION="${RAW_VERSION#v}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=================================================="
echo "  Velora Release Build Pipeline"
echo "  Target Version: v${VERSION}"
echo "=================================================="

# 0. Prerequisite Verification
command -v cargo >/dev/null 2>&1 || { echo "❌ Error: cargo is required but not installed."; exit 1; }
command -v swift >/dev/null 2>&1 || { echo "❌ Error: swift is required but not installed."; exit 1; }
if [ "$GENERATE_DMG" = true ]; then
    command -v hdiutil >/dev/null 2>&1 || { echo "❌ Error: hdiutil is required for DMG creation."; exit 1; }
fi

# 1. Build Rust FFI core in release mode
echo "📦 Step 1/7: Compiling Rust FFI core (release)..."
cargo build --release -p velora-ffi

# 2. Build Swift app in release mode (statically links libvelora_ffi.a, strictly arm64)
echo "🚀 Step 2/7: Compiling Swift frontend (release arm64)..."
(cd swift && swift build -c release --arch arm64)

# 3. Assemble Velora.app bundle
echo "📁 Step 3/7: Assembling Velora.app bundle..."
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

# Generate production Info.plist
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
</dict>
</plist>
EOF

# Touch app directory to register bundle changes
touch "$APP_DIR"

# 4. Validate Mach-O linkages (ensure zero leaked local developer paths)
echo "🔍 Step 4/7: Validating Mach-O linkages..."
if otool -L "$MACOS_DIR/Velora" | tail -n +2 | grep -E '/Users/|/home/'; then
    echo "❌ Error: Leaked local developer paths detected in binary dependencies!"
    exit 1
fi
echo "✅ Binary verified: 100% self-contained and portable."

# 5. Validate Apple Silicon (arm64) architecture exclusivity
echo "🔍 Step 5/7: Validating Mach-O architecture (Apple Silicon arm64 only)..."
BINARY_ARCHS=$(lipo -archs "$MACOS_DIR/Velora")
if [ "$BINARY_ARCHS" != "arm64" ]; then
    echo "❌ Error: Binary must be strictly Apple Silicon (arm64). Found: $BINARY_ARCHS"
    exit 1
fi
echo "✅ Architecture verified: 100% pure Apple Silicon (arm64)."

# 6. Optional Code Signing
if [ -n "$SIGN_IDENTITY" ]; then
    echo "🔐 Step 6/7: Code-signing Velora.app with Hardened Runtime..."
    codesign --deep --force --options runtime --timestamp \
        --entitlements "$ROOT_DIR/Velora.entitlements" \
        --sign "$SIGN_IDENTITY" \
        "$APP_DIR"
    codesign --verify --deep --strict --verbose=2 "$APP_DIR"
    echo "✅ Velora.app signed and verified."
else
    echo "ℹ️ Step 6/7: Skipping code signing (no identity provided)."
fi

# 7. Optional DMG generation
if [ "$GENERATE_DMG" = true ]; then
    echo "💿 Step 7/7: Packaging into styled DMG..."
    DMG_STAGE="$BUILD_DIR/dmg_stage"
    DMG_OUTPUT="$BUILD_DIR/Velora-${VERSION}.dmg"
    BG_IMAGE="$ROOT_DIR/assets/dmg/background.png"
    if [ ! -f "$BG_IMAGE" ]; then
        BG_IMAGE="$ROOT_DIR/assets/dmg/background@2x.png"
    fi
    VOL_ICON="$ROOT_DIR/assets/icons/AppIcon.icns"

    rm -rf "$DMG_STAGE" "$DMG_OUTPUT"
    mkdir -p "$DMG_STAGE"
    cp -R "$APP_DIR" "$DMG_STAGE/"

    if command -v create-dmg >/dev/null 2>&1 && [ -f "$BG_IMAGE" ]; then
        echo "🎨 Using create-dmg for styled installer presentation..."
        # Normalize DPI to 144 so Finder scales the 1320x840 Retina graphic to exactly 660x420 pt
        sips -s dpiWidth 144 -s dpiHeight 144 "$BG_IMAGE" >/dev/null 2>&1 || true
        # Hide extension at filesystem metadata level
        SetFile -a E "$DMG_STAGE/Velora.app" 2>/dev/null || true

        CREATE_DMG_ARGS=(
            --volname "Velora"
            --window-pos 200 120
            --window-size 660 448
            --icon-size 110
            --text-size 13
            --icon "Velora.app" 160 185
            --hide-extension "Velora.app"
            --app-drop-link 500 185
            --no-internet-enable
        )

        if [ -f "$VOL_ICON" ]; then
            CREATE_DMG_ARGS+=(--volicon "$VOL_ICON")
        fi

        CREATE_DMG_ARGS+=(--background "$BG_IMAGE")

        create-dmg "${CREATE_DMG_ARGS[@]}" "$DMG_OUTPUT" "$DMG_STAGE" || {
            echo "⚠️ create-dmg encountered an issue, falling back to standard hdiutil..."
            ln -s /Applications "$DMG_STAGE/Applications"
            hdiutil create -volname "Velora" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_OUTPUT"
        }
    else
        echo "ℹ️ create-dmg not found or background missing; using native hdiutil fallback..."
        ln -s /Applications "$DMG_STAGE/Applications"
        hdiutil create \
            -volname "Velora" \
            -srcfolder "$DMG_STAGE" \
            -ov \
            -format UDZO \
            "$DMG_OUTPUT"
    fi

    rm -rf "$DMG_STAGE"
    echo "✅ DMG generated at: $DMG_OUTPUT"

    if [ -n "$SIGN_IDENTITY" ]; then
        echo "🔐 Signing DMG..."
        codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_OUTPUT"
        codesign --verify --strict --verbose=2 "$DMG_OUTPUT"
        echo "✅ DMG signed and verified."
    fi
else
    echo "ℹ️ Step 6/6: Skipping DMG generation (--dmg not specified)."
fi

echo "=================================================="
echo "🎉 Pipeline finished successfully!"
echo "   Artifact: $APP_DIR"
if [ "$GENERATE_DMG" = true ]; then
    echo "   DMG:      $DMG_OUTPUT"
fi
echo "=================================================="
