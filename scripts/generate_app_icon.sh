#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="${ROOT_DIR}/assets/icons"
MASTER_PNG="${ASSETS_DIR}/AppIcon.png"
ICONSET_DIR="${ASSETS_DIR}/AppIcon.iconset"
OUTPUT_ICNS="${ASSETS_DIR}/AppIcon.icns"

if [[ ! -f "${MASTER_PNG}" ]] && [[ -f "${ASSETS_DIR}/VeloraIcon-1024.png" ]]; then
    MASTER_PNG="${ASSETS_DIR}/VeloraIcon-1024.png"
fi

if [[ ! -f "${MASTER_PNG}" ]]; then
    echo "❌ Error: Master icon '${MASTER_PNG}' not found." >&2
    exit 1
fi

echo "🎨 Generating iconset resolutions from ${MASTER_PNG}..."
mkdir -p "${ICONSET_DIR}"

sips -z 16 16     "${MASTER_PNG}" --out "${ICONSET_DIR}/icon_16x16.png" > /dev/null
sips -z 32 32     "${MASTER_PNG}" --out "${ICONSET_DIR}/icon_16x16@2x.png" > /dev/null
sips -z 32 32     "${MASTER_PNG}" --out "${ICONSET_DIR}/icon_32x32.png" > /dev/null
sips -z 64 64     "${MASTER_PNG}" --out "${ICONSET_DIR}/icon_32x32@2x.png" > /dev/null
sips -z 128 128   "${MASTER_PNG}" --out "${ICONSET_DIR}/icon_128x128.png" > /dev/null
sips -z 256 256   "${MASTER_PNG}" --out "${ICONSET_DIR}/icon_128x128@2x.png" > /dev/null
sips -z 256 256   "${MASTER_PNG}" --out "${ICONSET_DIR}/icon_256x256.png" > /dev/null
sips -z 512 512   "${MASTER_PNG}" --out "${ICONSET_DIR}/icon_256x256@2x.png" > /dev/null
sips -z 512 512   "${MASTER_PNG}" --out "${ICONSET_DIR}/icon_512x512.png" > /dev/null
sips -z 1024 1024 "${MASTER_PNG}" --out "${ICONSET_DIR}/icon_512x512@2x.png" > /dev/null

echo "📦 Compiling ${OUTPUT_ICNS} with iconutil..."
iconutil -c icns "${ICONSET_DIR}" -o "${OUTPUT_ICNS}"

echo "✅ AppIcon.icns generated successfully at ${OUTPUT_ICNS}!"
