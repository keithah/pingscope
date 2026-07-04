#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  deploy/sign-notarize.sh \
    --version <x.y.z> \
    --app <path/to/PingScope.app> \
    --sign-app "Developer ID Application: ..." \
    [--sign-installer "Developer ID Installer: ..."] \
    [--notary-profile "NotarytoolProfile"] \
    [--notary-key <AuthKey.p8> --notary-key-id <key-id> --notary-issuer <issuer-id>]

Notes:
  - Produces a DMG and (optionally) a PKG in /private/tmp/artifacts.
  - If --sign-installer is omitted, the PKG step is skipped.
EOF
}

VERSION=""
APP_PATH=""
SIGN_APP_IDENTITY=""
SIGN_INSTALLER_IDENTITY=""
NOTARY_PROFILE="NotarytoolProfile"
NOTARY_KEY=""
NOTARY_KEY_ID=""
NOTARY_ISSUER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"; shift 2 ;;
    --app)
      APP_PATH="$2"; shift 2 ;;
    --sign-app)
      SIGN_APP_IDENTITY="$2"; shift 2 ;;
    --sign-installer)
      SIGN_INSTALLER_IDENTITY="$2"; shift 2 ;;
    --notary-profile)
      NOTARY_PROFILE="$2"; shift 2 ;;
    --notary-key)
      NOTARY_KEY="$2"; shift 2 ;;
    --notary-key-id)
      NOTARY_KEY_ID="$2"; shift 2 ;;
    --notary-issuer)
      NOTARY_ISSUER="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${VERSION}" || -z "${APP_PATH}" || -z "${SIGN_APP_IDENTITY}" ]]; then
  usage
  exit 2
fi
if [[ ! "${VERSION}" =~ ^[0-9]+[.][0-9]+[.][0-9]+([-.][0-9A-Za-z]+)*$ ]]; then
  echo "Invalid version: ${VERSION}" >&2
  exit 2
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "App not found: ${APP_PATH}" >&2
  exit 2
fi
if [[ -n "${NOTARY_KEY}${NOTARY_KEY_ID}${NOTARY_ISSUER}" ]]; then
  if [[ -z "${NOTARY_KEY}" || -z "${NOTARY_KEY_ID}" || -z "${NOTARY_ISSUER}" ]]; then
    echo "Notary API key auth requires --notary-key, --notary-key-id, and --notary-issuer." >&2
    exit 2
  fi
  if [[ ! -f "${NOTARY_KEY}" ]]; then
    echo "Notary API key file not found: ${NOTARY_KEY}" >&2
    exit 2
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/codesign-macos.sh"
ARTIFACT_DIR="/private/tmp/artifacts/PingScope-v${VERSION}"
case "${ARTIFACT_DIR}" in
  /private/tmp/artifacts/PingScope-v*) ;;
  *) echo "Refusing unsafe artifact dir: ${ARTIFACT_DIR}" >&2; exit 2 ;;
esac
rm -rf "${ARTIFACT_DIR}"
mkdir -p "${ARTIFACT_DIR}"

NOTARY_ARGS=()
if [[ -n "${NOTARY_KEY}" ]]; then
  NOTARY_ARGS=(--key "${NOTARY_KEY}" --key-id "${NOTARY_KEY_ID}" --issuer "${NOTARY_ISSUER}")
else
  NOTARY_ARGS=(--keychain-profile "${NOTARY_PROFILE}")
fi

echo "Copying app bundle..."
cp -R "${APP_PATH}" "${ARTIFACT_DIR}/PingScope.app"

cd "${ARTIFACT_DIR}"

echo "Signing app: ${SIGN_APP_IDENTITY}"
SIGN_COMMON=("--force" "--options" "runtime" "--timestamp" "--sign" "${SIGN_APP_IDENTITY}")

codesign_sign_macos_bundle_contents "PingScope.app" "${PROJECT_ROOT}"

codesign_run --identifier "com.hadm.PingScope" --entitlements "${PROJECT_ROOT}/Configuration/PingScope-DeveloperID.entitlements" "PingScope.app"

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "PingScope.app"

echo "Creating DMG..."
rm -rf dmg_staging
mkdir -p dmg_staging
cp -R "PingScope.app" dmg_staging/
ln -s /Applications dmg_staging/Applications

DMG_NAME="PingScope-v${VERSION}.dmg"
NOTARY_TIMEOUT_SECONDS="${PING_SCOPE_NOTARY_TIMEOUT_SECONDS:-1800}"

retry() {
  local attempts="$1"
  local delay="$2"
  shift 2
  local attempt=1
  while true; do
    if "$@"; then
      return 0
    fi
    if [[ "${attempt}" -ge "${attempts}" ]]; then
      return 1
    fi
    sleep "${delay}"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
}

run_with_timeout() {
  local timeout_seconds="$1"
  shift
  perl -e 'alarm shift @ARGV; exec @ARGV' "${timeout_seconds}" "$@"
}

notarize_artifact() {
  local artifact="$1"
  retry 3 10 run_with_timeout "${NOTARY_TIMEOUT_SECONDS}" xcrun notarytool submit "${artifact}" "${NOTARY_ARGS[@]}" --wait
  retry 3 5 xcrun stapler staple "${artifact}"
}

hdiutil create -volname "PingScope v${VERSION}" \
  -srcfolder dmg_staging \
  -ov -format UDZO \
  "${DMG_NAME}"

echo "Signing DMG: ${SIGN_APP_IDENTITY}"
codesign "${SIGN_COMMON[@]}" "${DMG_NAME}"

PKG_NAME=""
if [[ -n "${SIGN_INSTALLER_IDENTITY}" ]]; then
  echo "Creating PKG..."
  pkgbuild --root "PingScope.app" \
    --identifier "com.hadm.PingScope" \
    --version "${VERSION}" \
    --install-location "/Applications/PingScope.app" \
    "unsigned.pkg"

  PKG_NAME="PingScope-v${VERSION}.pkg"
  echo "Signing PKG: ${SIGN_INSTALLER_IDENTITY}"
  productsign --sign "${SIGN_INSTALLER_IDENTITY}" "unsigned.pkg" "${PKG_NAME}"
  rm -f "unsigned.pkg"
fi

echo "Submitting DMG for notarization..."
notarize_artifact "${DMG_NAME}"

if [[ -n "${PKG_NAME}" ]]; then
  echo "Submitting PKG for notarization..."
  notarize_artifact "${PKG_NAME}"
fi

echo "Verifying with spctl..."
spctl -a -t exec -vv "PingScope.app"
spctl -a -t open --context context:primary-signature -vv "${DMG_NAME}"

if [[ -n "${PKG_NAME}" ]]; then
  spctl -a -t install -vv "${PKG_NAME}"
fi

echo "Creating checksums..."
CHECKSUM_FILE="checksums-v${VERSION}.txt"
shasum -a 256 "${DMG_NAME}" > "${CHECKSUM_FILE}"
if [[ -n "${PKG_NAME}" ]]; then
  shasum -a 256 "${PKG_NAME}" >> "${CHECKSUM_FILE}"
fi

echo "Done. Artifacts: ${ARTIFACT_DIR}"
