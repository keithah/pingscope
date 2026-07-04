#!/usr/bin/env bash
set -euo pipefail

# Build the Xcode app product, including the WidgetKit extension, and copy it to
# an installable .app bundle location.
#
# Usage:
#   scripts/build-xcode-app-bundle.sh [debug|release] [output_dir] [developer-id|app-store]
#
# Optional environment:
#   CODESIGN_IDENTITY="Developer ID Application: ..."
#   MARKETING_VERSION=0.1.4
#   CURRENT_PROJECT_VERSION=49
#   SKIP_CODESIGN_AFTER_BUILD=1

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/codesign-macos.sh"

CONFIGURATION_INPUT="${1:-debug}"
OUTPUT_DIR="${2:-.build/xcode-install}"
FLAVOR="${3:-developer-id}"

project_setting() {
  local key="$1"
  awk -F' = ' -v key="${key}" '$1 ~ ("^[[:space:]]*" key "$") { gsub(/;/, "", $2); print $2; exit }' PingScope.xcodeproj/project.pbxproj
}

MARKETING_VERSION="${MARKETING_VERSION:-$(project_setting MARKETING_VERSION)}"
CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION:-$(project_setting CURRENT_PROJECT_VERSION)}"
if [[ -z "${MARKETING_VERSION}" || -z "${CURRENT_PROJECT_VERSION}" ]]; then
  echo "Unable to derive MARKETING_VERSION/CURRENT_PROJECT_VERSION from project." >&2
  exit 65
fi

case "${CONFIGURATION_INPUT}" in
  debug|Debug) CONFIGURATION="Debug" ;;
  release|Release) CONFIGURATION="Release" ;;
  *)
    echo "Unknown configuration: ${CONFIGURATION_INPUT} (expected debug|release)" >&2
    exit 2
    ;;
esac

case "${FLAVOR}" in
  developer-id) SCHEME="PingScope-DeveloperID"; APP_ENTITLEMENTS="Configuration/PingScope-DeveloperID.entitlements" ;;
  app-store) SCHEME="PingScope-AppStore"; APP_ENTITLEMENTS="Configuration/PingScope-AppStore.entitlements" ;;
  *)
    echo "Unknown flavor: ${FLAVOR} (expected developer-id|app-store)" >&2
    exit 2
    ;;
esac

DERIVED_DATA_PATH=".build/xcode-${FLAVOR}-${CONFIGURATION}"
PRODUCT_APP="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/PingScope.app"
LOG_DIR=".build/logs"
BUILD_LOG="${LOG_DIR}/xcode-${FLAVOR}-${CONFIGURATION}.log"
rm -rf "${PRODUCT_APP}"
mkdir -p "${LOG_DIR}"

XCODEBUILD_ARGS=(
  -project PingScope.xcodeproj
  -scheme "${SCHEME}"
  -configuration "${CONFIGURATION}"
  -destination 'platform=macOS'
  -derivedDataPath "${DERIVED_DATA_PATH}"
  CODE_SIGNING_ALLOWED=NO
  COMPILER_INDEX_STORE_ENABLE="${PING_SCOPE_XCODE_INDEX_STORE_ENABLE:-NO}"
  MARKETING_VERSION="${MARKETING_VERSION}"
  CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION}"
)
if [[ "${FLAVOR}" == "app-store" ]]; then
  XCODEBUILD_ARGS+=(SWIFT_ACTIVE_COMPILATION_CONDITIONS="APPSTORE \$(inherited)")
fi

xcodebuild \
  "${XCODEBUILD_ARGS[@]}" \
  build >"${BUILD_LOG}" 2>&1 || {
    cat "${BUILD_LOG}" >&2
    exit 1
  }

if [[ ! -d "${PRODUCT_APP}" ]]; then
  echo "Expected Xcode product not found: ${PRODUCT_APP}" >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"
DEST_APP="${OUTPUT_DIR}/PingScope.app"
rm -rf "${DEST_APP}"
cp -R "${PRODUCT_APP}" "${DEST_APP}"

default_developer_id_identity() {
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application: .* (.*)\)".*/\1/p' \
    | head -n 1
}

SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ "${SKIP_CODESIGN_AFTER_BUILD:-0}" == "1" ]]; then
  echo "${DEST_APP}"
  exit 0
fi
if [[ -z "${SIGN_IDENTITY}" && "${FLAVOR}" == "developer-id" ]]; then
  SIGN_IDENTITY="$(default_developer_id_identity)"
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_COMMON=("--force" "--sign" "${SIGN_IDENTITY}")
if [[ "${FLAVOR}" == "developer-id" && "${SIGN_IDENTITY}" != "-" ]]; then
  SIGN_COMMON+=("--options" "runtime" "--timestamp")
fi
CODESIGN_QUIET=1

codesign_sign_macos_bundle_contents "${DEST_APP}" "${PROJECT_ROOT}"

codesign_run --identifier "com.hadm.PingScope" --entitlements "${APP_ENTITLEMENTS}" "${DEST_APP}"

echo "${DEST_APP}"
