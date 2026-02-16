#!/usr/bin/env bash
set -euo pipefail

# Build PingScope into a minimal `.app` bundle.
#
# Why: macOS notification prompts and signing/notarization require a real bundle.
#
# Usage:
#   scripts/build-app-bundle.sh [debug|release] [output_dir]
#
# Examples:
#   scripts/build-app-bundle.sh debug
#   scripts/build-app-bundle.sh release /private/tmp/artifacts

CONFIGURATION="${1:-debug}"
OUTPUT_DIR="${2:-}"

case "${CONFIGURATION}" in
  debug|release) ;;
  *)
    echo "Unknown configuration: ${CONFIGURATION} (expected debug|release)" >&2
    exit 2
    ;;
esac

SWIFT_BUILD_ARGS=("-c" "${CONFIGURATION}")

BIN_DIR="$(swift build --show-bin-path "${SWIFT_BUILD_ARGS[@]}")"
APP_DIR="${BIN_DIR}/PingScope.app"
if [[ -n "${OUTPUT_DIR}" ]]; then
  mkdir -p "${OUTPUT_DIR}"
  APP_DIR="${OUTPUT_DIR}/PingScope.app"
fi

CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BIN_DIR}/PingScope" "${MACOS_DIR}/PingScope"
cp "Info.plist" "${CONTENTS_DIR}/Info.plist"

# SwiftPM resources are built into this bundle when present.
if [[ -d "${BIN_DIR}/PingScope_PingScope.bundle" ]]; then
  cp -R "${BIN_DIR}/PingScope_PingScope.bundle" "${RESOURCES_DIR}/"
fi

# Privacy manifest.
if [[ -f "Sources/PingScope/Resources/PrivacyInfo.xcprivacy" ]]; then
  cp "Sources/PingScope/Resources/PrivacyInfo.xcprivacy" "${RESOURCES_DIR}/"
fi

# App icon (CFBundleIconFile expects it in the main app Resources).
if [[ -f "Sources/PingScope/Resources/AppIcon.icns" ]]; then
  cp "Sources/PingScope/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

chmod +x "${MACOS_DIR}/PingScope"

echo "${APP_DIR}"
