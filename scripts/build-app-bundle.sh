#!/usr/bin/env bash
set -euo pipefail

# Build PingScope into a minimal `.app` bundle.
#
# Why: macOS notification prompts and signing/notarization require a real bundle.
#
# Usage:
#   scripts/build-app-bundle.sh [debug|release] [output_dir] [developer-id|app-store]
#
# Examples:
#   scripts/build-app-bundle.sh debug
#   scripts/build-app-bundle.sh release /private/tmp/artifacts developer-id
#   scripts/build-app-bundle.sh release /private/tmp/artifacts app-store
#
# Optional environment:
#   CODESIGN_IDENTITY="Developer ID Application: ..."
#   APP_ENTITLEMENTS=/path/to/entitlements.plist
#   MARKETING_VERSION=0.1.0
#   CURRENT_PROJECT_VERSION=24

CONFIGURATION="${1:-debug}"
OUTPUT_DIR="${2:-}"
FLAVOR="${3:-developer-id}"
MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION:-24}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.hadm.PingScope}"

case "${CONFIGURATION}" in
  debug|release) ;;
  *)
    echo "Unknown configuration: ${CONFIGURATION} (expected debug|release)" >&2
    exit 2
    ;;
esac

case "${FLAVOR}" in
  developer-id|app-store) ;;
  *)
    echo "Unknown flavor: ${FLAVOR} (expected developer-id|app-store)" >&2
    exit 2
    ;;
esac

SWIFT_BUILD_ARGS=("-c" "${CONFIGURATION}")
if [[ "${FLAVOR}" == "app-store" ]]; then
  SWIFT_BUILD_ARGS+=("-Xswiftc" "-DAPPSTORE")
fi

swift build "${SWIFT_BUILD_ARGS[@]}" >/dev/null
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
cp "Configuration/Info.plist" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_IDENTIFIER}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${MARKETING_VERSION}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${CURRENT_PROJECT_VERSION}" "${CONTENTS_DIR}/Info.plist"

# SwiftPM resources are built into this bundle when present.
if [[ -d "${BIN_DIR}/PingScope_PingScope.bundle" ]]; then
  cp -R "${BIN_DIR}/PingScope_PingScope.bundle" "${RESOURCES_DIR}/"
fi

# Privacy manifest.
if [[ -f "Configuration/PrivacyInfo.xcprivacy" ]]; then
  cp "Configuration/PrivacyInfo.xcprivacy" "${RESOURCES_DIR}/"
fi

# App icon (CFBundleIconFile expects it in the main app Resources).
if [[ -f "Configuration/AppIcon.icns" ]]; then
  cp "Configuration/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

chmod +x "${MACOS_DIR}/PingScope"

default_developer_id_identity() {
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application: .* (.*)\)".*/\1/p' \
    | head -n 1
}

SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "${SIGN_IDENTITY}" && "${FLAVOR}" == "developer-id" ]]; then
  SIGN_IDENTITY="$(default_developer_id_identity)"
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_ARGS=("--force" "--sign" "${SIGN_IDENTITY}" "--identifier" "${BUNDLE_IDENTIFIER}")
if [[ "${FLAVOR}" == "developer-id" && "${SIGN_IDENTITY}" != "-" ]]; then
  SIGN_ARGS+=("--options" "runtime" "--timestamp")
fi
if [[ "${FLAVOR}" == "app-store" ]]; then
  ENTITLEMENTS="${APP_ENTITLEMENTS:-Configuration/PingScope-AppStore.entitlements}"
  SIGN_ARGS+=("--entitlements" "${ENTITLEMENTS}")
elif [[ "${FLAVOR}" == "developer-id" ]]; then
  ENTITLEMENTS="${APP_ENTITLEMENTS:-Configuration/PingScope-DeveloperID.entitlements}"
  SIGN_ARGS+=("--entitlements" "${ENTITLEMENTS}")
elif [[ -n "${APP_ENTITLEMENTS:-}" ]]; then
  SIGN_ARGS+=("--entitlements" "${APP_ENTITLEMENTS}")
fi
codesign "${SIGN_ARGS[@]}" "${APP_DIR}" >/dev/null

echo "${APP_DIR}"
