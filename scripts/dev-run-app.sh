#!/usr/bin/env bash
set -euo pipefail

# Build and run PingScope as a minimal .app bundle.
# This is required for macOS notification permission prompts.

# If a prior non-bundled `swift run` instance is running, it can interfere with testing.
pkill -f "/\\.build/.*?/debug/PingScope$" >/dev/null 2>&1 || true

# Optional: force restart the app bundle.
if [[ "${PING_SCOPE_RESTART:-0}" == "1" ]]; then
  pkill -f "/PingScope\\.app/Contents/MacOS/PingScope" >/dev/null 2>&1 || true
fi

BIN_DIR="$(swift build --show-bin-path)"
APP_DIR="${BIN_DIR}/PingScope.app"
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

# App icon (CFBundleIconFile expects it in the main app Resources).
if [[ -f "Sources/PingScope/Resources/AppIcon.icns" ]]; then
  cp "Sources/PingScope/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# Keep a copy of the privacy manifest at the app level as well.
if [[ -f "Sources/PingScope/Resources/PrivacyInfo.xcprivacy" ]]; then
  cp "Sources/PingScope/Resources/PrivacyInfo.xcprivacy" "${RESOURCES_DIR}/"
fi

open "${APP_DIR}"
