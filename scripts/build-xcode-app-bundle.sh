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
#   MARKETING_VERSION=0.1.0
#   CURRENT_PROJECT_VERSION=24

CONFIGURATION_INPUT="${1:-debug}"
OUTPUT_DIR="${2:-.build/xcode-install}"
FLAVOR="${3:-developer-id}"
MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION:-24}"

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
rm -rf "${PRODUCT_APP}"

XCODEBUILD_ARGS=(
  -project PingScope.xcodeproj
  -scheme "${SCHEME}"
  -configuration "${CONFIGURATION}"
  -destination 'platform=macOS'
  -derivedDataPath "${DERIVED_DATA_PATH}"
  CODE_SIGNING_ALLOWED=NO
  MARKETING_VERSION="${MARKETING_VERSION}"
  CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION}"
)
if [[ "${FLAVOR}" == "app-store" ]]; then
  XCODEBUILD_ARGS+=(SWIFT_ACTIVE_COMPILATION_CONDITIONS="APPSTORE \$(inherited)")
fi

xcodebuild \
  "${XCODEBUILD_ARGS[@]}" \
  build >/dev/null

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
if [[ -z "${SIGN_IDENTITY}" && "${FLAVOR}" == "developer-id" ]]; then
  SIGN_IDENTITY="$(default_developer_id_identity)"
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_COMMON=("--force" "--sign" "${SIGN_IDENTITY}")
if [[ "${FLAVOR}" == "developer-id" && "${SIGN_IDENTITY}" != "-" ]]; then
  SIGN_COMMON+=("--options" "runtime" "--timestamp")
fi

sign_framework_tree() {
  local framework="$1"
  while IFS= read -r executable; do
    codesign "${SIGN_COMMON[@]}" "${executable}" >/dev/null
  done < <(find "${framework}" -type f -perm -111 2>/dev/null | sort)

  while IFS= read -r bundle; do
    codesign "${SIGN_COMMON[@]}" "${bundle}" >/dev/null
  done < <(find "${framework}" \( -name '*.xpc' -o -name '*.app' \) -type d 2>/dev/null | sort -r)

  codesign "${SIGN_COMMON[@]}" "${framework}" >/dev/null
}

while IFS= read -r framework; do
  sign_framework_tree "${framework}"
done < <(find "${DEST_APP}/Contents/Frameworks" -name '*.framework' -type d 2>/dev/null | sort)

while IFS= read -r dylib; do
  codesign "${SIGN_COMMON[@]}" "${dylib}" >/dev/null
done < <(find "${DEST_APP}/Contents/MacOS" -name '*.dylib' -type f 2>/dev/null | sort)

while IFS= read -r appex; do
  while IFS= read -r framework; do
    sign_framework_tree "${framework}"
  done < <(find "${appex}/Contents/Frameworks" -name '*.framework' -type d 2>/dev/null | sort)
  while IFS= read -r dylib; do
    codesign "${SIGN_COMMON[@]}" "${dylib}" >/dev/null
  done < <(find "${appex}/Contents/MacOS" -name '*.dylib' -type f 2>/dev/null | sort)
  codesign "${SIGN_COMMON[@]}" --entitlements "PingScopeWidget/PingScopeWidget.entitlements" "${appex}" >/dev/null
done < <(find "${DEST_APP}/Contents/PlugIns" -name '*.appex' -type d 2>/dev/null)

codesign "${SIGN_COMMON[@]}" --identifier "com.hadm.PingScope" --entitlements "${APP_ENTITLEMENTS}" "${DEST_APP}" >/dev/null

echo "${DEST_APP}"
