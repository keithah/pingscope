#!/usr/bin/env bash
set -euo pipefail

RELEASE_DIR=""
DMG_PATH=""
DOWNLOAD_URL_PREFIX=""
RELEASE_NOTES=""
KEY_ACCOUNT="pingscope-ed25519"
GENERATE_APPCAST="${SPARKLE_GENERATE_APPCAST:-}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/appcast.sh \
    --release-dir <ignored-dir> \
    --dmg <PingScope.dmg> \
    --download-url-prefix <https-url> \
    [--release-notes <file>] \
    [--key-account <account>] \
    [--generate-appcast <tool>]

Generates a Sparkle appcast for a signed and notarized PingScope DMG. The
Sparkle private EdDSA key must be stored in Keychain; do not pass private keys
on the command line.
USAGE
}

require_value() {
  local option="$1"
  local value="${2-}"
  if [[ -z "${value}" ]]; then
    echo "Invalid appcast option: ${option} requires a value." >&2
    exit 64
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release-dir)
      require_value "$1" "${2-}"; RELEASE_DIR="$2"; shift 2 ;;
    --dmg)
      require_value "$1" "${2-}"; DMG_PATH="$2"; shift 2 ;;
    --download-url-prefix)
      require_value "$1" "${2-}"; DOWNLOAD_URL_PREFIX="$2"; shift 2 ;;
    --release-notes)
      require_value "$1" "${2-}"; RELEASE_NOTES="$2"; shift 2 ;;
    --key-account)
      require_value "$1" "${2-}"; KEY_ACCOUNT="$2"; shift 2 ;;
    --generate-appcast)
      require_value "$1" "${2-}"; GENERATE_APPCAST="$2"; shift 2 ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      echo "Invalid appcast option: $1" >&2
      usage
      exit 64
      ;;
  esac
done

if [[ -z "${RELEASE_DIR}" || -z "${DMG_PATH}" || -z "${DOWNLOAD_URL_PREFIX}" ]]; then
  echo "Invalid appcast option: --release-dir, --dmg, and --download-url-prefix are required." >&2
  exit 64
fi
if [[ "${DOWNLOAD_URL_PREFIX}" != https://* ]]; then
  echo "Invalid appcast option: --download-url-prefix must use https." >&2
  exit 64
fi
if [[ "${DOWNLOAD_URL_PREFIX}" != */ ]]; then
  DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX}/"
fi
if [[ ! -f "${DMG_PATH}" ]]; then
  echo "Invalid appcast option: DMG file does not exist: ${DMG_PATH}" >&2
  exit 66
fi
if [[ -n "${RELEASE_NOTES}" && ! -f "${RELEASE_NOTES}" ]]; then
  echo "Invalid appcast option: release notes file does not exist: ${RELEASE_NOTES}" >&2
  exit 66
fi

find_generate_appcast() {
  if [[ -n "${GENERATE_APPCAST}" ]]; then
    [[ -x "${GENERATE_APPCAST}" ]] && { printf '%s' "${GENERATE_APPCAST}"; return 0; }
    return 1
  fi

  local tool
  tool=$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast' -type f -perm -111 2>/dev/null | sort | tail -n 1)
  if [[ -n "${tool}" ]]; then
    printf '%s' "${tool}"
    return 0
  fi
  return 1
}

TOOL=$(find_generate_appcast) || {
  echo "Sparkle generate_appcast was not found. Resolve Xcode packages or pass --generate-appcast." >&2
  exit 69
}

mkdir -p "${RELEASE_DIR}"
DMG_NAME=$(basename "${DMG_PATH}")
ditto "${DMG_PATH}" "${RELEASE_DIR}/${DMG_NAME}"

if [[ -n "${RELEASE_NOTES}" ]]; then
  NOTES_EXT="${RELEASE_NOTES##*.}"
  ditto "${RELEASE_NOTES}" "${RELEASE_DIR}/${DMG_NAME%.*}.${NOTES_EXT}"
fi

"${TOOL}" \
  --account "${KEY_ACCOUNT}" \
  --download-url-prefix "${DOWNLOAD_URL_PREFIX}" \
  "${RELEASE_DIR}"

echo "Sparkle appcast generated: ${RELEASE_DIR}/appcast.xml"
