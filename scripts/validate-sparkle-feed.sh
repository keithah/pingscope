#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/release-validation.sh
source "${SCRIPT_DIR}/lib/release-validation.sh"
# shellcheck source=lib/sparkle-tools.sh
source "${SCRIPT_DIR}/lib/sparkle-tools.sh"

project_setting() {
  local key="$1"
  awk -F' = ' -v key="${key}" '$1 ~ ("^[[:space:]]*" key "$") { gsub(/;/, "", $2); print $2; exit }' PingScope.xcodeproj/project.pbxproj
}

VERSION="${1:-$(project_setting MARKETING_VERSION)}"
BUILD_VERSION="${PING_SCOPE_BUILD_VERSION:-$(project_setting CURRENT_PROJECT_VERSION)}"
FEED_URL="${PING_SCOPE_SPARKLE_FEED_URL:-https://keithah.github.io/pingscope/appcast.xml}"
EXPECTED_SHA256="${PING_SCOPE_DMG_SHA256:-}"
WORK_DIR="${PING_SCOPE_SPARKLE_VALIDATE_DIR:-}"
KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-pingscope-ed25519}"
DOWNLOAD_DMG="${PING_SCOPE_DOWNLOAD_DMG:-1}"
CURL=(curl --fail --location --show-error --silent --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 120 --retry 3)

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

validate_version "${VERSION}" || fail "invalid version: ${VERSION}"
validate_build_version "${BUILD_VERSION}" || fail "invalid build version: ${BUILD_VERSION}"

EXPECTED_MINIMUM_SYSTEM="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Configuration/Info.plist)"

if [[ -z "${WORK_DIR}" ]]; then
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pingscope-sparkle-feed.XXXXXX")"
  trap 'rm -rf "${WORK_DIR}"' EXIT
else
  mkdir -p "${WORK_DIR}"
fi
chmod 700 "${WORK_DIR}"
APPCAST="${WORK_DIR}/appcast.xml"
META="${WORK_DIR}/appcast-meta.txt"

case "${FEED_URL}" in
  https://*) ;;
  *) fail "Sparkle feed URL must be https: ${FEED_URL}" ;;
esac

"${CURL[@]}" "${FEED_URL}" -o "${APPCAST}"

python3 - "${APPCAST}" "${VERSION}" "${BUILD_VERSION}" "${EXPECTED_MINIMUM_SYSTEM}" >"${META}" <<'PY'
import sys
import xml.etree.ElementTree as ET

appcast, expected_version, expected_build, expected_minimum_system = sys.argv[1:5]
sparkle = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
root = ET.parse(appcast).getroot()
item = root.find("./channel/item")
if item is None:
    raise SystemExit("missing channel item")
title = (item.findtext("title") or "").strip()
short_version = (item.findtext(f"{sparkle}shortVersionString") or "").strip()
build = (item.findtext(f"{sparkle}version") or "").strip()
minimum_system = (item.findtext(f"{sparkle}minimumSystemVersion") or "").strip()
release_notes = (item.findtext(f"{sparkle}releaseNotesLink") or "").strip()
enclosure = item.find("enclosure")
if enclosure is None:
    raise SystemExit("missing enclosure")
url = enclosure.attrib.get("url", "")
length = enclosure.attrib.get("length", "")
signature = enclosure.attrib.get(f"{sparkle}edSignature", "")
if title != expected_version or short_version != expected_version:
    raise SystemExit(f"expected version {expected_version}, got title={title!r} short={short_version!r}")
if build != expected_build:
    raise SystemExit(f"expected build {expected_build}, got {build!r}")
if not url.startswith("https://"):
    raise SystemExit(f"enclosure URL must be https: {url!r}")
if not length.isdigit() or int(length) <= 0:
    raise SystemExit(f"invalid enclosure length: {length!r}")
if not signature:
    raise SystemExit("missing Sparkle EdDSA signature")
if minimum_system != expected_minimum_system:
    raise SystemExit(f"expected minimum system {expected_minimum_system}, got {minimum_system!r}")
if release_notes and not release_notes.startswith("https://"):
    raise SystemExit(f"release notes URL must be https: {release_notes!r}")
print(url)
print(length)
print(signature)
PY

DMG_URL="$(sed -n '1p' "${META}")"
DMG_LENGTH="$(sed -n '2p' "${META}")"
DMG_SIGNATURE="$(sed -n '3p' "${META}")"

if [[ "${DOWNLOAD_DMG}" -eq 1 ]]; then
  DMG="${WORK_DIR}/$(basename "${DMG_URL}")"
  "${CURL[@]}" "${DMG_URL}" -o "${DMG}"

  actual_size=$(stat -f %z "${DMG}")
  [[ "${actual_size}" == "${DMG_LENGTH}" ]] || fail "DMG length mismatch: appcast=${DMG_LENGTH}, downloaded=${actual_size}"

  if [[ -n "${EXPECTED_SHA256}" ]]; then
    actual_sha=$(shasum -a 256 "${DMG}" | awk '{print $1}')
    [[ "${actual_sha}" == "${EXPECTED_SHA256}" ]] || fail "DMG sha256 mismatch: expected=${EXPECTED_SHA256}, actual=${actual_sha}"
  fi

  SIGN_UPDATE=$(find_sparkle_tool sign_update SPARKLE_SIGN_UPDATE) || fail "Sparkle sign_update was not found. Build the Xcode project once to resolve Sparkle."
  "${SIGN_UPDATE}" --account "${KEY_ACCOUNT}" --verify "${DMG}" "${DMG_SIGNATURE}"

  spctl --assess --type open --context context:primary-signature -v "${DMG}" >/dev/null
fi

echo "PASS: Sparkle feed ${VERSION} build ${BUILD_VERSION} validated"
