#!/usr/bin/env bash
set -euo pipefail

VERSION=""
NOTARY_PROFILE="NotarytoolProfile"
SIGN_APP_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Keith Herrington (6R7S5GA944)}"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-pingscope-ed25519}"
RELEASE_NOTES=""
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/release-github.sh --version <x.y.z> [--release-notes <file>] [--dry-run]

Builds the Developer ID app, signs and notarizes a DMG, generates Sparkle
appcast.xml, and publishes a GitHub release with gh.

Required local credentials:
  - Developer ID Application certificate in login keychain.
  - notarytool keychain profile, default: NotarytoolProfile.
  - Sparkle EdDSA private key in Keychain, default account: pingscope-ed25519.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2-}"; shift 2 ;;
    --notary-profile)
      NOTARY_PROFILE="${2-}"; shift 2 ;;
    --sign-app)
      SIGN_APP_IDENTITY="${2-}"; shift 2 ;;
    --release-notes)
      RELEASE_NOTES="${2-}"; shift 2 ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      echo "Unknown release option: $1" >&2
      usage
      exit 64
      ;;
  esac
done

if [[ -z "${VERSION}" ]]; then
  usage
  exit 64
fi

if [[ "${DRY_RUN}" -eq 0 ]]; then
  gh auth status >/dev/null
fi

xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null

GENERATE_KEYS=$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys' -type f -perm -111 2>/dev/null | sort | tail -n 1)
if [[ -z "${GENERATE_KEYS}" ]]; then
  echo "Sparkle generate_keys was not found. Build the Xcode project once to resolve Sparkle." >&2
  exit 69
fi
"${GENERATE_KEYS}" --account "${SPARKLE_KEY_ACCOUNT}" -p >/dev/null

if ! security find-identity -v -p codesigning | grep -F "${SIGN_APP_IDENTITY}" >/dev/null; then
  echo "Developer ID Application identity not found: ${SIGN_APP_IDENTITY}" >&2
  exit 65
fi

BUILD_DIR=".build/release-github/v${VERSION}"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

MARKETING_VERSION="${VERSION}" CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION:-1}" \
CODESIGN_IDENTITY="${SIGN_APP_IDENTITY}" \
  scripts/build-xcode-app-bundle.sh release "${BUILD_DIR}" developer-id >/dev/null

deploy/sign-notarize.sh \
  --version "${VERSION}" \
  --app "${BUILD_DIR}/PingScope.app" \
  --sign-app "${SIGN_APP_IDENTITY}" \
  --notary-profile "${NOTARY_PROFILE}"

ARTIFACT_DIR="/private/tmp/artifacts/PingScope-v${VERSION}"
DMG="${ARTIFACT_DIR}/PingScope-v${VERSION}.dmg"
CHECKSUMS="${ARTIFACT_DIR}/checksums-v${VERSION}.txt"
UPDATE_DIR="${ARTIFACT_DIR}/updates"
DOWNLOAD_PREFIX="https://github.com/keithah/pingscope/releases/download/v${VERSION}"

APPCAST_ARGS=(
  --release-dir "${UPDATE_DIR}"
  --dmg "${DMG}"
  --download-url-prefix "${DOWNLOAD_PREFIX}"
  --key-account "${SPARKLE_KEY_ACCOUNT}"
)
if [[ -n "${RELEASE_NOTES}" ]]; then
  APPCAST_ARGS+=(--release-notes "${RELEASE_NOTES}")
fi
scripts/appcast.sh "${APPCAST_ARGS[@]}"

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "Dry run complete. Artifacts:"
  echo "  ${DMG}"
  echo "  ${UPDATE_DIR}/appcast.xml"
  echo "  ${CHECKSUMS}"
  exit 0
fi

TAG="v${VERSION}"
if git rev-parse "${TAG}" >/dev/null 2>&1; then
  echo "Tag already exists locally: ${TAG}" >&2
  exit 65
fi

git tag "${TAG}"
git push origin "${TAG}"

gh release create "${TAG}" \
  "${DMG}" \
  "${UPDATE_DIR}/appcast.xml" \
  "${CHECKSUMS}" \
  --title "PingScope ${VERSION}" \
  --notes-file "${RELEASE_NOTES:-/dev/stdin}" <<EOF
PingScope ${VERSION}
EOF

echo "Published GitHub release ${TAG}."
