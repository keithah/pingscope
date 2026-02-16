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
    [--notary-profile "NotarytoolProfile"]

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

if [[ ! -d "${APP_PATH}" ]]; then
  echo "App not found: ${APP_PATH}" >&2
  exit 2
fi

ARTIFACT_DIR="/private/tmp/artifacts/PingScope-v${VERSION}"
rm -rf "${ARTIFACT_DIR}"
mkdir -p "${ARTIFACT_DIR}"

echo "Copying app bundle..."
cp -R "${APP_PATH}" "${ARTIFACT_DIR}/PingScope.app"

cd "${ARTIFACT_DIR}"

echo "Signing app: ${SIGN_APP_IDENTITY}"
codesign --force --deep --options runtime --timestamp --sign "${SIGN_APP_IDENTITY}" "PingScope.app"

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "PingScope.app"

echo "Creating DMG..."
rm -rf dmg_staging
mkdir -p dmg_staging
cp -R "PingScope.app" dmg_staging/
ln -s /Applications dmg_staging/Applications

DMG_NAME="PingScope-v${VERSION}.dmg"
hdiutil create -volname "PingScope v${VERSION}" \
  -srcfolder dmg_staging \
  -ov -format UDZO \
  "${DMG_NAME}"

PKG_NAME=""
if [[ -n "${SIGN_INSTALLER_IDENTITY}" ]]; then
  echo "Creating PKG..."
  pkgbuild --root "PingScope.app" \
    --identifier "com.hadm.pingscope" \
    --version "${VERSION}" \
    --install-location "/Applications/PingScope.app" \
    "unsigned.pkg"

  PKG_NAME="PingScope-v${VERSION}.pkg"
  echo "Signing PKG: ${SIGN_INSTALLER_IDENTITY}"
  productsign --sign "${SIGN_INSTALLER_IDENTITY}" "unsigned.pkg" "${PKG_NAME}"
  rm -f "unsigned.pkg"
fi

echo "Submitting DMG for notarization..."
xcrun notarytool submit "${DMG_NAME}" --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple "${DMG_NAME}"

if [[ -n "${PKG_NAME}" ]]; then
  echo "Submitting PKG for notarization..."
  xcrun notarytool submit "${PKG_NAME}" --keychain-profile "${NOTARY_PROFILE}" --wait
  xcrun stapler staple "${PKG_NAME}"
fi

echo "Verifying with spctl..."
spctl -a -t exec -vv "PingScope.app" || true

if [[ -n "${PKG_NAME}" ]]; then
  spctl -a -t install -vv "${PKG_NAME}" || true
fi

echo "Creating checksums..."
CHECKSUM_FILE="checksums-v${VERSION}.txt"
shasum -a 256 "${DMG_NAME}" > "${CHECKSUM_FILE}"
if [[ -n "${PKG_NAME}" ]]; then
  shasum -a 256 "${PKG_NAME}" >> "${CHECKSUM_FILE}"
fi

echo "Done. Artifacts: ${ARTIFACT_DIR}"
