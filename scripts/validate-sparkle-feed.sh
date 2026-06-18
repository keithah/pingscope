#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-0.1.2}"
BUILD_VERSION="${PING_SCOPE_BUILD_VERSION:-25}"
FEED_URL="${PING_SCOPE_SPARKLE_FEED_URL:-https://keithah.github.io/pingscope/appcast.xml}"
EXPECTED_SHA256="${PING_SCOPE_DMG_SHA256:-}"
WORK_DIR="${PING_SCOPE_SPARKLE_VALIDATE_DIR:-/tmp/pingscope-sparkle-feed}"
KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-pingscope-ed25519}"
DOWNLOAD_DMG="${PING_SCOPE_DOWNLOAD_DMG:-1}"

find_sign_update() {
  local tool
  tool=$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update' -type f -perm -111 2>/dev/null | sort | tail -n 1)
  if [[ -n "${tool}" ]]; then
    printf '%s' "${tool}"
    return 0
  fi
  return 1
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

mkdir -p "${WORK_DIR}"
APPCAST="${WORK_DIR}/appcast.xml"
META="${WORK_DIR}/appcast-meta.env"

curl -LfsS "${FEED_URL}" -o "${APPCAST}"

python3 - "${APPCAST}" "${VERSION}" "${BUILD_VERSION}" >"${META}" <<'PY'
import shlex
import sys
import xml.etree.ElementTree as ET

appcast, expected_version, expected_build = sys.argv[1:4]
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
if minimum_system != "26.0":
    raise SystemExit(f"expected minimum system 26.0, got {minimum_system!r}")
if release_notes and not release_notes.startswith("https://"):
    raise SystemExit(f"release notes URL must be https: {release_notes!r}")
print(f"DMG_URL={shlex.quote(url)}")
print(f"DMG_LENGTH={shlex.quote(length)}")
print(f"DMG_SIGNATURE={shlex.quote(signature)}")
PY

# shellcheck disable=SC1090
source "${META}"

if [[ "${DOWNLOAD_DMG}" -eq 1 ]]; then
  DMG="${WORK_DIR}/$(basename "${DMG_URL}")"
  curl -LfsS "${DMG_URL}" -o "${DMG}"

  actual_size=$(stat -f %z "${DMG}")
  [[ "${actual_size}" == "${DMG_LENGTH}" ]] || fail "DMG length mismatch: appcast=${DMG_LENGTH}, downloaded=${actual_size}"

  if [[ -n "${EXPECTED_SHA256}" ]]; then
    actual_sha=$(shasum -a 256 "${DMG}" | awk '{print $1}')
    [[ "${actual_sha}" == "${EXPECTED_SHA256}" ]] || fail "DMG sha256 mismatch: expected=${EXPECTED_SHA256}, actual=${actual_sha}"
  fi

  SIGN_UPDATE=$(find_sign_update) || fail "Sparkle sign_update was not found. Build the Xcode project once to resolve Sparkle."
  "${SIGN_UPDATE}" --account "${KEY_ACCOUNT}" --verify "${DMG}" "${DMG_SIGNATURE}"

  spctl --assess --type open --context context:primary-signature -v "${DMG}" >/dev/null
fi

echo "PASS: Sparkle feed ${VERSION} build ${BUILD_VERSION} validated"
