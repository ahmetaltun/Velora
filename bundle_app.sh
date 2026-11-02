#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

# -----------------------------------------------------------------------------
# Host Environment Verification (Apple Silicon macOS 15+ only)
# -----------------------------------------------------------------------------
if [ "$(uname -s)" != "Darwin" ]; then
    echo "❌ Error: Velora can only be bundled and run on macOS."
    exit 1
fi

HOST_ARCH=$(uname -m)
if [ "$HOST_ARCH" != "arm64" ]; then
    echo "❌ Error: Velora requires Apple Silicon (ARM64). Detected host architecture: $HOST_ARCH."
    if [ "$HOST_ARCH" = "x86_64" ]; then
        if [ "$(sysctl -in sysctl.proc_translated 2>/dev/null)" = "1" ]; then
            echo "   ⚠️ Notice: Terminal is running under Rosetta (x86_64 translation). Please run in a native arm64 terminal."
        fi
    fi
    exit 1
fi

if [ "$(sysctl -in sysctl.proc_translated 2>/dev/null)" = "1" ]; then
    echo "❌ Error: Velora cannot run or build under Rosetta 2 translation. Native Apple Silicon (ARM64) required."
    exit 1
fi

OS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "0")
OS_MAJOR=$(echo "$OS_VERSION" | cut -d. -f1)
if [ "$OS_MAJOR" -lt 15 ]; then
    echo "❌ Error: Velora requires macOS 15 (Sequoia) or later. Detected: macOS $OS_VERSION."
    exit 1
fi

DEFAULT_VERSION=$(sed -nE 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$ROOT_DIR/Cargo.toml" | head -n 1)
VERSION="${1:-${DEFAULT_VERSION:-0.4.0}}"

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
    "swift/.build/arm64-apple-macosx/debug/Velora"
    "swift/.build/release/Velora"
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
elif [ -d "swift/.build/arm64-apple-macosx/debug/Sparkle.framework" ]; then
    cp -R "swift/.build/arm64-apple-macosx/debug/Sparkle.framework" "$FRAMEWORKS/"
elif [ -d "swift/.build/release/Sparkle.framework" ]; then
    cp -R "swift/.build/release/Sparkle.framework" "$FRAMEWORKS/"
elif [ -d "swift/.build/debug/Sparkle.framework" ]; then
    cp -R "swift/.build/debug/Sparkle.framework" "$FRAMEWORKS/"
elif [ -d "swift/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" ]; then
    cp -R "swift/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$FRAMEWORKS/"
else
    echo "⚠️ Warning: Sparkle.framework not found in build directory."
fi

thin_binary_to_arm64() {
    local target="$1"
    if [ -f "$target" ]; then
        if lipo -info "$target" 2>/dev/null | grep -q "^Architectures in the fat file:"; then
            echo "✂️ Thinning $target to arm64..."
            local tmp="${target}.arm64"
            lipo -thin arm64 "$target" -output "$tmp"
            mv -f "$tmp" "$target"
            chmod +x "$target"
        fi
    fi
}

# Thin embedded Sparkle framework binaries to pure arm64
if [ -d "$FRAMEWORKS/Sparkle.framework" ]; then
    echo "✂️ Thinning Sparkle.framework to Apple Silicon (arm64 only)..."
    thin_binary_to_arm64 "$FRAMEWORKS/Sparkle.framework/Versions/B/Sparkle"
    thin_binary_to_arm64 "$FRAMEWORKS/Sparkle.framework/Versions/B/Autoupdate"
    thin_binary_to_arm64 "$FRAMEWORKS/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater"
    find "$FRAMEWORKS/Sparkle.framework" -type f -perm +111 2>/dev/null | while read -r bin_file; do
        if file "$bin_file" | grep -q "Mach-O"; then
            thin_binary_to_arm64 "$bin_file"
        fi
    done
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

# Copy SPM resource bundles (including compiled Shaders and Assets)
find swift/.build -name "*.bundle" -maxdepth 3 2>/dev/null | while read -r spm_bundle; do
    if [ -d "$spm_bundle" ] && [[ "$spm_bundle" != *"Sparkle"* ]]; then
        echo "📦 Copying resource bundle: $(basename "$spm_bundle")"
        cp -R "$spm_bundle" "$RESOURCES/"
    fi
done

# Create Info.plist with explicit Apple Silicon and macOS 15+ constraints
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

chmod +x "$MACOS/Velora"

# Validate main executable Apple Silicon (arm64) architecture exclusivity
BINARY_ARCHS=$(lipo -archs "$MACOS/Velora")
if [ "$BINARY_ARCHS" != "arm64" ]; then
    echo "❌ Error: Binary must be strictly Apple Silicon (arm64). Found: $BINARY_ARCHS"
    exit 1
fi
echo "✅ Main binary architecture verified: Apple Silicon (arm64)."

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

# Recursive bundle audit: Verify 100% of all Mach-O binaries in Velora.app are strictly arm64
echo "🔬 Auditing all bundle Mach-O binaries for Apple Silicon (arm64) exclusivity..."
while IFS= read -r bin_file; do
    if file "$bin_file" | grep -q "Mach-O"; then
        ARCHS=$(lipo -archs "$bin_file")
        if [ "$ARCHS" != "arm64" ]; then
            echo "❌ Error: Found non-arm64 architecture ($ARCHS) in $bin_file"
            exit 1
        fi
    fi
done < <(find "$APP_DIR" -type f -perm +111)
echo "✅ Complete bundle verified: 100% pure Apple Silicon (arm64)."

# Ad-hoc inside-out code signing for local execution
if [ -d "$FRAMEWORKS/Sparkle.framework" ]; then
    codesign --force --deep --sign - "$FRAMEWORKS/Sparkle.framework" 2>/dev/null || true
fi
codesign --force --sign - "$APP_DIR" 2>/dev/null || true

touch "$APP_DIR"
echo "✅ Velora.app created successfully!"
