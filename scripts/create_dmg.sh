#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Velora Premium macOS DMG Installer Packaging Script
# -----------------------------------------------------------------------------
# Packages the compiled Velora.app into a styled, professional macOS DMG.
# Recreates a clean, modern, minimal, Apple-inspired layout:
# - Background: 1440x920 @2x Retina (720x460 pt, 144 DPI)
# - Window dimensions: 720x488 pt (720x460 pt content area)
# - Custom branded artwork, centered arrow, aligned Finder icons
# - Left slot: Velora.app at (195, 240)
# - Right slot: Applications symlink at (525, 240)
# - Hidden Finder toolbar, sidebar, and statusbar
#
# Usage:
#   ./scripts/create_dmg.sh [version] [--app <path>] [--output <path>] [--sign <identity>]
# Examples:
#   ./scripts/create_dmg.sh
#   ./scripts/create_dmg.sh 0.4.0
#   ./scripts/create_dmg.sh 0.4.0 --sign "Developer ID Application: Company (TEAMID)"
# -----------------------------------------------------------------------------

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DEFAULT_VERSION=$(sed -nE 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$ROOT_DIR/Cargo.toml" | head -n 1)
RAW_VERSION="${DEFAULT_VERSION:-0.4.0}"
APP_PATH="$ROOT_DIR/build/Velora.app"
CUSTOM_OUTPUT=""
SIGN_IDENTITY="${APPLE_SIGNING_IDENTITY:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)
            APP_PATH="$2"
            shift 2
            ;;
        --output)
            CUSTOM_OUTPUT="$2"
            shift 2
            ;;
        --sign)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        -*)
            echo "[ERROR] Unknown flag: $1"
            echo "Usage: $0 [version] [--app <path>] [--output <path>] [--sign <identity>]"
            exit 1
            ;;
        *)
            RAW_VERSION="$1"
            shift
            ;;
    esac
done

VERSION="${RAW_VERSION#v}"
BUILD_DIR="$ROOT_DIR/build"
mkdir -p "$BUILD_DIR"

FINAL_DMG="${CUSTOM_OUTPUT:-$BUILD_DIR/Velora.dmg}"
VERSIONED_DMG="$BUILD_DIR/Velora-${VERSION}.dmg"

echo "=================================================="
echo "  Velora Premium DMG Builder"
echo "  Target App:     $APP_PATH"
echo "  Target Version: v${VERSION}"
echo "  Output DMG:     $FINAL_DMG"
echo "=================================================="

# 1. Verify Prerequisites
if [ "$(uname -s)" != "Darwin" ]; then
    echo "[ERROR] DMG generation requires macOS."
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    echo "[ERROR] Application bundle not found at: $APP_PATH"
    echo "        Please build Velora.app before running this script."
    echo "        Run: ./scripts/build_release.sh ${VERSION}"
    exit 1
fi

command -v hdiutil >/dev/null 2>&1 || { echo "[ERROR] hdiutil is required for DMG creation."; exit 1; }

# 2. Verify / Generate Background Artwork
BG_DIR="$ROOT_DIR/assets/dmg"
BG_1X="$BG_DIR/background.png"
BG_2X="$BG_DIR/background@2x.png"

if [ ! -f "$BG_1X" ] || [ ! -f "$BG_2X" ]; then
    echo "[INFO] Background artwork missing. Generating fresh Retina assets with Swift..."
    if command -v swift >/dev/null 2>&1; then
        swift -module-cache-path /tmp/swift-cache "$ROOT_DIR/scripts/generate_dmg_background.swift"
    else
        echo "[ERROR] Swift compiler is required to generate background artwork."
        exit 1
    fi
fi

# Ensure DPI metadata is normalized to 144 DPI for 2x and 72 DPI for 1x
if command -v sips >/dev/null 2>&1; then
    sips -s dpiWidth 72 -s dpiHeight 72 "$BG_1X" >/dev/null 2>&1 || true
    sips -s dpiWidth 144 -s dpiHeight 144 "$BG_2X" >/dev/null 2>&1 || true
fi

# Set invisible extension bit on app bundle so Finder hides .app
if command -v SetFile >/dev/null 2>&1; then
    SetFile -a E "$APP_PATH" 2>/dev/null || true
fi

# 3. Locate Best DMG Builder Tool (dmgbuild preferred for headless reliability)
DMGBUILD_CMD=""
if command -v dmgbuild >/dev/null 2>&1; then
    DMGBUILD_CMD="dmgbuild"
elif [ -x "$HOME/.pyenv/shims/dmgbuild" ]; then
    DMGBUILD_CMD="$HOME/.pyenv/shims/dmgbuild"
elif python3 -c "import dmgbuild" >/dev/null 2>&1; then
    DMGBUILD_CMD="python3 -m dmgbuild"
fi

SETTINGS_FILE="$ROOT_DIR/assets/dmg/dmgbuild_settings.py"
VOL_ICON="$ROOT_DIR/assets/icons/AppIcon.icns"

rm -f "$FINAL_DMG" "$VERSIONED_DMG"

if [ -n "$DMGBUILD_CMD" ] && [ -f "$SETTINGS_FILE" ]; then
    echo "[INFO] Using dmgbuild (headless, zero-permission, pixel-perfect DS_Store)..."
    
    DEFINES_ARGS=(
        -D app_path="$APP_PATH"
        -D bg_image="$BG_1X"
    )
    if [ -f "$VOL_ICON" ]; then
        DEFINES_ARGS+=(-D vol_icon="$VOL_ICON")
    fi

    $DMGBUILD_CMD \
        -s "$SETTINGS_FILE" \
        "${DEFINES_ARGS[@]}" \
        "Velora" \
        "$FINAL_DMG"

elif command -v create-dmg >/dev/null 2>&1; then
    echo "[INFO] dmgbuild not found; using create-dmg fallback..."
    DMG_STAGE="$BUILD_DIR/dmg_stage_temp"
    rm -rf "$DMG_STAGE"
    mkdir -p "$DMG_STAGE"
    cp -R "$APP_PATH" "$DMG_STAGE/"
    SetFile -a E "$DMG_STAGE/Velora.app" 2>/dev/null || true

    CREATE_DMG_ARGS=(
        --volname "Velora"
        --window-pos 200 120
        --window-size 720 488
        --icon-size 110
        --text-size 13
        --icon "Velora.app" 195 240
        --hide-extension "Velora.app"
        --app-drop-link 525 240
        --no-internet-enable
        --background "$BG_2X"
    )
    if [ -f "$VOL_ICON" ]; then
        CREATE_DMG_ARGS+=(--volicon "$VOL_ICON")
    fi

    create-dmg "${CREATE_DMG_ARGS[@]}" "$FINAL_DMG" "$DMG_STAGE"
    rm -rf "$DMG_STAGE"
else
    echo "[ERROR] Neither 'dmgbuild' nor 'create-dmg' is available."
    echo "        Please install dmgbuild for the highest quality headless builds:"
    echo "          pip install dmgbuild"
    echo "        Or install create-dmg via Homebrew:"
    echo "          brew install create-dmg"
    exit 1
fi

# Ensure versioned DMG is also created/linked for release publishing
if [ "$FINAL_DMG" != "$VERSIONED_DMG" ]; then
    cp -f "$FINAL_DMG" "$VERSIONED_DMG"
fi

# 4. Optional Code Signing
if [ -n "$SIGN_IDENTITY" ]; then
    echo "[INFO] Code-signing DMG installer ($FINAL_DMG)..."
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$FINAL_DMG"
    codesign --verify --strict --verbose=2 "$FINAL_DMG"
    if [ "$FINAL_DMG" != "$VERSIONED_DMG" ]; then
        codesign --force --timestamp --sign "$SIGN_IDENTITY" "$VERSIONED_DMG"
    fi
    echo "[OK] DMG signature verified."
fi

echo "=================================================="
echo "[SUCCESS] Velora DMG generated successfully!"
echo "   Output:    $FINAL_DMG"
if [ "$FINAL_DMG" != "$VERSIONED_DMG" ]; then
    echo "   Versioned: $VERSIONED_DMG"
fi
echo "=================================================="
