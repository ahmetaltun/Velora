#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Velora Release Build & Packaging Script
# -----------------------------------------------------------------------------
# Usage:
#   ./scripts/build_release.sh [version] [--dmg] [--sign <identity>]
# Examples:
#   ./scripts/build_release.sh 0.3.0
#   ./scripts/build_release.sh 0.3.0 --dmg
#   ./scripts/build_release.sh 0.3.0 --dmg --sign "Developer ID Application: Company (TEAMID)"
# -----------------------------------------------------------------------------

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DEFAULT_VERSION=$(sed -nE 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$ROOT_DIR/Cargo.toml" | head -n 1)
RAW_VERSION="${DEFAULT_VERSION:-0.3.0}"
GENERATE_DMG=false
GENERATE_ZIP=false
SIGN_IDENTITY="${APPLE_SIGNING_IDENTITY:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dmg)
            GENERATE_DMG=true
            GENERATE_ZIP=true
            shift
            ;;
        --zip)
            GENERATE_ZIP=true
            shift
            ;;
        --sign)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        -*)
            echo "[ERROR] Unknown flag: $1"
            echo "Usage: $0 [version] [--dmg] [--zip] [--sign <identity>]"
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

echo "=================================================="
echo "  Velora Release Build Pipeline"
echo "  Target Version: v${VERSION}"
echo "=================================================="

# 0. Prerequisite Verification
if [ "$(uname -s)" != "Darwin" ]; then
    echo "[ERROR] Velora can only be built on macOS."
    exit 1
fi

HOST_ARCH=$(uname -m)
if [ "$HOST_ARCH" != "arm64" ]; then
    echo "[ERROR] Velora release pipeline strictly requires an Apple Silicon (ARM64) Mac. Detected: $HOST_ARCH."
    if [ "$HOST_ARCH" = "x86_64" ]; then
        if [ "$(sysctl -in sysctl.proc_translated 2>/dev/null)" = "1" ]; then
            echo "        Notice: Shell is running under Rosetta (x86_64 translation). Please run in a native arm64 shell."
        fi
    fi
    exit 1
fi

if [ "$(sysctl -in sysctl.proc_translated 2>/dev/null)" = "1" ]; then
    echo "[ERROR] Velora cannot be built under Rosetta 2 translation. Native Apple Silicon (ARM64) required."
    exit 1
fi

OS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "0")
OS_MAJOR=$(echo "$OS_VERSION" | cut -d. -f1)
if [ "$OS_MAJOR" -lt 15 ]; then
    echo "[ERROR] Velora requires macOS 15 (Sequoia) or later. Detected: macOS $OS_VERSION."
    exit 1
fi

command -v cargo >/dev/null 2>&1 || { echo "[ERROR] cargo is required but not installed."; exit 1; }
command -v swift >/dev/null 2>&1 || { echo "[ERROR] swift is required but not installed."; exit 1; }
if command -v rustup >/dev/null 2>&1; then
    if ! rustup target list --installed | grep -q "aarch64-apple-darwin"; then
        echo "[ERROR] Rust target 'aarch64-apple-darwin' is not installed."
        echo "        Install it via: rustup target add aarch64-apple-darwin"
        exit 1
    fi
fi
if [ "$GENERATE_DMG" = true ]; then
    command -v hdiutil >/dev/null 2>&1 || { echo "[ERROR] hdiutil is required for DMG creation."; exit 1; }
fi

# 1. Build Rust FFI core in release mode
echo "[STEP 1/8] Compiling Rust FFI core (release arm64, macOS 15+)..."
cargo build --release -p velora-ffi --target aarch64-apple-darwin
mkdir -p "$ROOT_DIR/target/release"
cp "$ROOT_DIR/target/aarch64-apple-darwin/release/libvelora_ffi.a" "$ROOT_DIR/target/release/libvelora_ffi.a" 2>/dev/null || true

# 2. Build Swift app in release mode (statically links libvelora_ffi.a, strictly arm64, macOS 15+)
echo "[STEP 2/8] Compiling Swift frontend (release arm64, macOS 15+)..."
(cd swift && swift build -c release --arch arm64)

# 3. Assemble Velora.app bundle
echo "[STEP 3/8] Assembling Velora.app bundle..."
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/Velora.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

# Copy binary
if [ -f "$ROOT_DIR/swift/.build/arm64-apple-macosx/release/Velora" ]; then
    cp "$ROOT_DIR/swift/.build/arm64-apple-macosx/release/Velora" "$MACOS_DIR/Velora"
elif [ -f "$ROOT_DIR/swift/.build/release/Velora" ]; then
    cp "$ROOT_DIR/swift/.build/release/Velora" "$MACOS_DIR/Velora"
else
    echo "[ERROR] Could not locate compiled release Velora binary."
    exit 1
fi
chmod +x "$MACOS_DIR/Velora"

# Copy Sparkle.framework for auto-updates
echo "[INFO] Embedding Sparkle.framework for auto-updates..."
rm -rf "$FRAMEWORKS_DIR/Sparkle.framework"
if [ -d "$ROOT_DIR/swift/.build/arm64-apple-macosx/release/Sparkle.framework" ]; then
    cp -R "$ROOT_DIR/swift/.build/arm64-apple-macosx/release/Sparkle.framework" "$FRAMEWORKS_DIR/"
elif [ -d "$ROOT_DIR/swift/.build/release/Sparkle.framework" ]; then
    cp -R "$ROOT_DIR/swift/.build/release/Sparkle.framework" "$FRAMEWORKS_DIR/"
elif [ -d "$ROOT_DIR/swift/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" ]; then
    cp -R "$ROOT_DIR/swift/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$FRAMEWORKS_DIR/"
else
    echo "[ERROR] Sparkle.framework not found in build artifacts."
    exit 1
fi

thin_binary_to_arm64() {
    local target="$1"
    if [ -f "$target" ]; then
        if lipo -info "$target" 2>/dev/null | grep -q "^Architectures in the fat file:"; then
            echo "[INFO] Thinning $target to arm64..."
            local tmp="${target}.arm64"
            lipo -thin arm64 "$target" -output "$tmp"
            mv -f "$tmp" "$target"
            chmod +x "$target"
        fi
    fi
}

# Thin embedded Sparkle framework binaries to pure arm64
echo "[INFO] Thinning Sparkle.framework binaries to Apple Silicon (arm64 only)..."
thin_binary_to_arm64 "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/Sparkle"
thin_binary_to_arm64 "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/Autoupdate"
thin_binary_to_arm64 "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater"
find "$FRAMEWORKS_DIR/Sparkle.framework" -type f -perm +111 2>/dev/null | while read -r bin_file; do
    if file "$bin_file" | grep -q "Mach-O"; then
        thin_binary_to_arm64 "$bin_file"
    fi
done

# Ensure executable can locate embedded frameworks via @executable_path/../Frameworks
if ! otool -l "$MACOS_DIR/Velora" | grep -F -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/Velora" 2>/dev/null || true
fi

# Copy app icon and image assets if present
if [ -f "$ROOT_DIR/assets/icons/AppIcon.icns" ]; then
    cp "$ROOT_DIR/assets/icons/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi
if [ -f "$ROOT_DIR/assets/icons/AppIcon.png" ]; then
    cp "$ROOT_DIR/assets/icons/AppIcon.png" "$RESOURCES_DIR/AppIcon.png"
fi
for icon_asset in "$ROOT_DIR"/assets/icons/VeloraIcon-*.png; do
    if [ -f "$icon_asset" ]; then
        cp "$icon_asset" "$RESOURCES_DIR/"
    fi
done

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
    <key>LSMinimumSystemVersionByArchitecture</key>
    <dict>
        <key>arm64</key>
        <string>15.0</string>
    </dict>
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

# Touch app directory to register bundle changes
touch "$APP_DIR"

# 4. Validate Mach-O linkages (ensure zero leaked local developer paths)
echo "[STEP 4/8] Validating Mach-O linkages..."
if otool -L "$MACOS_DIR/Velora" | tail -n +2 | grep -E '/Users/|/home/'; then
    echo "[ERROR] Leaked local developer paths detected in binary dependencies!"
    exit 1
fi
echo "[OK] Binary verified: 100% self-contained and portable."

# 5. Validate Apple Silicon (arm64) architecture exclusivity across entire bundle
echo "[STEP 5/8] Validating Mach-O architecture (Apple Silicon arm64 only across bundle)..."
BINARY_ARCHS=$(lipo -archs "$MACOS_DIR/Velora")
if [ "$BINARY_ARCHS" != "arm64" ]; then
    echo "[ERROR] Binary must be strictly Apple Silicon (arm64). Found: $BINARY_ARCHS"
    exit 1
fi
echo "[OK] Main binary verified: 100% pure Apple Silicon (arm64)."

echo "[INFO] Auditing all embedded bundle Mach-O binaries for Apple Silicon (arm64) exclusivity..."
while IFS= read -r bin_file; do
    if file "$bin_file" | grep -q "Mach-O"; then
        ARCHS=$(lipo -archs "$bin_file")
        if [ "$ARCHS" != "arm64" ]; then
            echo "[ERROR] Non-arm64 architecture ($ARCHS) detected in: $bin_file"
            exit 1
        fi
    fi
done < <(find "$APP_DIR" -type f -perm +111)
echo "[OK] Complete bundle verified: 100% pure Apple Silicon (arm64)."

# Validate macOS 15+ minimum OS requirement in Mach-O headers
echo "[INFO] Validating Mach-O minimum macOS deployment target (macOS 15+)..."
MIN_OS=$(otool -l "$MACOS_DIR/Velora" | awk '/LC_BUILD_VERSION/{getline; getline; getline; print $2}')
if [ -n "$MIN_OS" ]; then
    MAJOR_OS=$(echo "$MIN_OS" | cut -d. -f1)
    if [ "$MAJOR_OS" -lt 15 ]; then
        echo "[ERROR] Binary minimum OS requirement is $MIN_OS, but must be 15.0 (Sequoia) or later."
        exit 1
    fi
    echo "[OK] Minimum deployment target verified: macOS $MIN_OS (Sequoia+)."
fi

# 6. Optional Code Signing (Inside-Out per Apple TN3127)
if [ -n "$SIGN_IDENTITY" ]; then
    echo "[STEP 6/8] Code-signing Velora.app with Hardened Runtime (inside-out)..."
    if [ -d "$FRAMEWORKS_DIR/Sparkle.framework" ]; then
        echo "[INFO] Signing embedded Sparkle components inside-out..."
        find "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/XPCServices" -type d -name "*.xpc" 2>/dev/null | while read -r xpc; do
            echo "[INFO] Signing XPC service: $xpc"
            codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$xpc"
        done
        if [ -f "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/Autoupdate" ]; then
            echo "[INFO] Signing Sparkle Autoupdate binary..."
            codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/Autoupdate"
        fi
        if [ -d "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/Updater.app" ]; then
            echo "[INFO] Signing Sparkle Updater.app helper..."
            codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/Updater.app"
        fi
        echo "[INFO] Signing Sparkle.framework bundle..."
        codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$FRAMEWORKS_DIR/Sparkle.framework"
    fi

    # Sign the main application Mach-O executable with Hardened Runtime and Entitlements
    echo "[INFO] Signing main executable Mach-O binary..."
    codesign --force --options runtime --timestamp \
        --entitlements "$ROOT_DIR/Velora.entitlements" \
        --sign "$SIGN_IDENTITY" \
        "$MACOS_DIR/Velora"

    # Sign the top-level application bundle WITHOUT --deep
    echo "[INFO] Signing outer Velora.app bundle..."
    codesign --force --options runtime --timestamp \
        --entitlements "$ROOT_DIR/Velora.entitlements" \
        --sign "$SIGN_IDENTITY" \
        "$APP_DIR"

    echo "[INFO] Verifying application bundle signature strictly..."
    codesign --verify --deep --strict --verbose=2 "$APP_DIR"
    echo "[OK] Velora.app signed and verified."
else
    echo "[INFO] [STEP 6/8] Skipping code signing (no identity provided)."
fi

# 7. Optional ZIP generation for Sparkle auto-updates
if [ "$GENERATE_ZIP" = true ]; then
    echo "[STEP 7/8] Packaging into distribution ZIP for Sparkle..."
    ZIP_OUTPUT="$BUILD_DIR/Velora-${VERSION}.zip"
    rm -f "$ZIP_OUTPUT"
    ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_OUTPUT"
    echo "[OK] ZIP generated at: $ZIP_OUTPUT"
else
    echo "[INFO] [STEP 7/8] Skipping ZIP generation (--zip not specified)."
fi

# 8. Optional DMG generation
if [ "$GENERATE_DMG" = true ]; then
    echo "[STEP 8/8] Packaging into styled DMG..."
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
        echo "[INFO] Using create-dmg for styled installer presentation..."
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
            echo "[WARN] create-dmg encountered an issue, falling back to standard hdiutil..."
            ln -s /Applications "$DMG_STAGE/Applications"
            hdiutil create -volname "Velora" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_OUTPUT"
        }
    else
        echo "[INFO] create-dmg not found or background missing; using native hdiutil fallback..."
        ln -s /Applications "$DMG_STAGE/Applications"
        hdiutil create \
            -volname "Velora" \
            -srcfolder "$DMG_STAGE" \
            -ov \
            -format UDZO \
            "$DMG_OUTPUT"
    fi

    rm -rf "$DMG_STAGE"
    echo "[OK] DMG generated at: $DMG_OUTPUT"

    if [ -n "$SIGN_IDENTITY" ]; then
        echo "[INFO] Signing DMG..."
        codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_OUTPUT"
        codesign --verify --strict --verbose=2 "$DMG_OUTPUT"
        echo "[OK] DMG signed and verified."
    fi
else
    echo "[INFO] [STEP 8/8] Skipping DMG generation (--dmg not specified)."
fi

echo "=================================================="
echo "[SUCCESS] Pipeline finished successfully!"
echo "   Artifact: $APP_DIR"
if [ "$GENERATE_ZIP" = true ]; then
    echo "   ZIP:      $BUILD_DIR/Velora-${VERSION}.zip"
fi
if [ "$GENERATE_DMG" = true ]; then
    echo "   DMG:      $DMG_OUTPUT"
fi
echo "=================================================="
