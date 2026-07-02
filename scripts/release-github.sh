#!/usr/bin/env bash
set -euo pipefail

VERSION=""
NOTARY_PROFILE="NotarytoolProfile"
NOTARY_KEY="${NOTARY_KEY:-}"
NOTARY_KEY_ID="${NOTARY_KEY_ID:-}"
NOTARY_ISSUER="${NOTARY_ISSUER:-}"
SIGN_APP_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Keith Herrington (6R7S5GA944)}"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-pingscope-ed25519}"
RELEASE_NOTES=""
DRY_RUN=0
PAGES_BRANCH="${PING_SCOPE_PAGES_BRANCH:-gh-pages}"
PAGES_APPCAST_PATH="${PING_SCOPE_PAGES_APPCAST_PATH:-appcast.xml}"
PAGES_BASE_URL="${PING_SCOPE_PAGES_BASE_URL:-https://keithah.github.io/pingscope}"
PAGES_SITE_DIR="${PING_SCOPE_PAGES_SITE_DIR:-deploy/site}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/release-github.sh --version <x.y.z> [--release-notes <file>] [--dry-run]
                            [--notary-profile <profile>]
                            [--notary-key <AuthKey.p8> --notary-key-id <key-id> --notary-issuer <issuer-id>]

Builds the Developer ID app, signs and notarizes a DMG, generates Sparkle
appcast.xml, and publishes a GitHub release with gh.

Required local credentials:
  - Developer ID Application certificate in login keychain.
  - notarytool keychain profile, default: NotarytoolProfile, or App Store Connect API key auth.
  - Sparkle EdDSA private key in Keychain, default account: pingscope-ed25519.

The generated appcast is also published to GitHub Pages at:
  https://keithah.github.io/pingscope/appcast.xml
USAGE
}

validate_version() {
  [[ "$1" =~ ^[0-9]+[.][0-9]+[.][0-9]+([-.][0-9A-Za-z]+)*$ ]]
}

publish_pages_updates() {
  local update_dir="$1"
  local version="$2"
  local remote_url
  local pages_dir

  remote_url=$(git config --get remote.origin.url)
  if [[ -z "${remote_url}" ]]; then
    echo "Cannot publish appcast: origin remote is not configured." >&2
    return 1
  fi

  pages_dir=$(mktemp -d "${TMPDIR:-/tmp}/pingscope-pages.XXXXXX")
  if git ls-remote --exit-code --heads origin "${PAGES_BRANCH}" >/dev/null 2>&1; then
    git clone --depth 1 --branch "${PAGES_BRANCH}" "${remote_url}" "${pages_dir}" >/dev/null
  else
    git init "${pages_dir}" >/dev/null
    git -C "${pages_dir}" remote add origin "${remote_url}"
    git -C "${pages_dir}" checkout --orphan "${PAGES_BRANCH}" >/dev/null
  fi

  mkdir -p "${pages_dir}/$(dirname "${PAGES_APPCAST_PATH}")"
  ditto "${update_dir}/appcast.xml" "${pages_dir}/${PAGES_APPCAST_PATH}"
  find "${update_dir}" -maxdepth 1 -type f ! -name appcast.xml -exec ditto {} "${pages_dir}/" \;
  if [[ -d "${PAGES_SITE_DIR}" ]]; then
    ditto "${PAGES_SITE_DIR}" "${pages_dir}"
  fi

  git -C "${pages_dir}" add .
  if git -C "${pages_dir}" diff --cached --quiet; then
    echo "GitHub Pages updates are already current."
  else
    git -C "${pages_dir}" commit -m "Publish PingScope ${version} appcast" >/dev/null
    git -C "${pages_dir}" push origin "${PAGES_BRANCH}" >/dev/null
    echo "Published GitHub Pages updates to ${PAGES_BRANCH}."
  fi

  if ! gh api repos/keithah/pingscope/pages >/dev/null 2>&1; then
    gh api repos/keithah/pingscope/pages \
      --method POST \
      -f 'source[branch]='"${PAGES_BRANCH}" \
      -f 'source[path]=/' >/dev/null || {
        echo "GitHub Pages update branch was pushed, but automatic Pages enablement failed." >&2
        echo "Enable Pages manually from ${PAGES_BRANCH}/ if needed." >&2
      }
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2-}"; shift 2 ;;
    --notary-profile)
      NOTARY_PROFILE="${2-}"; shift 2 ;;
    --notary-key)
      NOTARY_KEY="${2-}"; shift 2 ;;
    --notary-key-id)
      NOTARY_KEY_ID="${2-}"; shift 2 ;;
    --notary-issuer)
      NOTARY_ISSUER="${2-}"; shift 2 ;;
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
if ! validate_version "${VERSION}"; then
  echo "Invalid release version: ${VERSION}" >&2
  exit 64
fi

if [[ "${DRY_RUN}" -eq 0 ]]; then
  gh auth status >/dev/null
fi

if [[ -n "${NOTARY_KEY}${NOTARY_KEY_ID}${NOTARY_ISSUER}" ]]; then
  if [[ -z "${NOTARY_KEY}" || -z "${NOTARY_KEY_ID}" || -z "${NOTARY_ISSUER}" ]]; then
    echo "Notary API key auth requires --notary-key, --notary-key-id, and --notary-issuer." >&2
    exit 64
  fi
  if [[ ! -f "${NOTARY_KEY}" ]]; then
    echo "Notary API key file not found: ${NOTARY_KEY}" >&2
    exit 66
  fi
  NOTARY_ARGS=(--notary-key "${NOTARY_KEY}" --notary-key-id "${NOTARY_KEY_ID}" --notary-issuer "${NOTARY_ISSUER}")
  xcrun notarytool history --key "${NOTARY_KEY}" --key-id "${NOTARY_KEY_ID}" --issuer "${NOTARY_ISSUER}" >/dev/null
else
  NOTARY_ARGS=(--notary-profile "${NOTARY_PROFILE}")
  xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null
fi

# Prints the tool path, or nothing if it cannot be found. Always exits 0 so the
# caller's diagnostic runs: under `set -e` a non-zero return from the command
# substitution would abort the script before the "not found" message.
find_sparkle_tool() {
  local tool_name="$1"
  local tool=""
  local env_name="SPARKLE_$(printf '%s' "${tool_name}" | tr '[:lower:]' '[:upper:]')"
  local env_value="${!env_name:-}"
  if [[ -n "${env_value}" ]]; then
    if [[ ! -x "${env_value}" ]]; then
      # Name the bad override: the generic "build the Xcode project" advice
      # below cannot help, because an explicit override suppresses the search.
      echo "${env_name} is set but not executable: ${env_value}" >&2
    fi
    [[ -x "${env_value}" ]] && printf '%s' "${env_value}"
    return 0
  fi
  for tool in \
    ".build/artifacts/sparkle/Sparkle/bin/${tool_name}" \
    ".build/checkouts/Sparkle/bin/${tool_name}" \
    "${PWD}/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/${tool_name}"
  do
    [[ -x "${tool}" ]] && { printf '%s' "${tool}"; return 0; }
  done
  tool=$(find .build -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/${tool_name}" -type f -perm -111 -print -quit 2>/dev/null || true)
  if [[ -n "${tool}" && -x "${tool}" ]]; then
    printf '%s' "${tool}"
  fi
  return 0
}

GENERATE_KEYS=$(find_sparkle_tool generate_keys)
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
case "${BUILD_DIR}" in
  .build/release-github/v*) ;;
  *) echo "Refusing unsafe build dir: ${BUILD_DIR}" >&2; exit 65 ;;
esac
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

MARKETING_VERSION="${VERSION}" \
SKIP_CODESIGN_AFTER_BUILD=1 \
  scripts/build-xcode-app-bundle.sh release "${BUILD_DIR}" developer-id >/dev/null

deploy/sign-notarize.sh \
  --version "${VERSION}" \
  --app "${BUILD_DIR}/PingScope.app" \
  --sign-app "${SIGN_APP_IDENTITY}" \
  "${NOTARY_ARGS[@]}"

ARTIFACT_DIR="/private/tmp/artifacts/PingScope-v${VERSION}"
DMG="${ARTIFACT_DIR}/PingScope-v${VERSION}.dmg"
CHECKSUMS="${ARTIFACT_DIR}/checksums-v${VERSION}.txt"
UPDATE_DIR="${ARTIFACT_DIR}/updates"
DOWNLOAD_PREFIX="${PAGES_BASE_URL}"

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

# appcast.sh only writes the standalone notes asset when --release-notes was
# supplied, and it keeps that file's extension. Referencing the hard-coded .md
# unconditionally made every release without a Markdown notes file fail after
# the tag had already been pushed.
RELEASE_ASSETS=("${DMG}" "${UPDATE_DIR}/appcast.xml" "${CHECKSUMS}")
if [[ -n "${RELEASE_NOTES}" ]]; then
  NOTES_ASSET="${UPDATE_DIR}/PingScope-v${VERSION}.${RELEASE_NOTES##*.}"
  if [[ -f "${NOTES_ASSET}" ]]; then
    RELEASE_ASSETS+=("${NOTES_ASSET}")
  fi
fi

gh release create "${TAG}" \
  "${RELEASE_ASSETS[@]}" \
  --title "PingScope ${VERSION}" \
  --notes-file "${RELEASE_NOTES:-/dev/stdin}" <<EOF
PingScope ${VERSION}
EOF

publish_pages_updates "${UPDATE_DIR}" "${VERSION}"

echo "Published GitHub release ${TAG}."
