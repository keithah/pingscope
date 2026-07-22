#!/usr/bin/env bash

validate_developer_id_profile() {
  local profile_path="$1"
  local expected_bundle_id="$2"
  local expected_signing_identity="${3:-}"
  local requires_cloudkit="${4:-1}"
  local signed_entitlements_path="${5:-}"
  local decoded_profile
  local expected_certificate_sha1=""

  if [[ ! -f "${profile_path}" ]]; then
    echo "Developer ID provisioning profile not found: ${profile_path}" >&2
    return 1
  fi

  decoded_profile=$(mktemp "${TMPDIR:-/tmp}/pingscope-profile.XXXXXX.plist")
  if ! security cms -D -i "${profile_path}" > "${decoded_profile}" 2>/dev/null; then
    echo "Unable to decode Developer ID provisioning profile: ${profile_path}" >&2
    rm -f "${decoded_profile}"
    return 1
  fi

  if [[ -n "${expected_signing_identity}" ]]; then
    expected_certificate_sha1=$(
      security find-certificate -c "${expected_signing_identity}" -Z 2>/dev/null \
        | awk '/^SHA-1 hash:/ { print $3; exit }'
    )
    if [[ -z "${expected_certificate_sha1}" ]]; then
      echo "Developer ID signing identity not found: ${expected_signing_identity}" >&2
      rm -f "${decoded_profile}"
      return 1
    fi
  fi

  if ! /usr/bin/python3 - "${decoded_profile}" "${expected_bundle_id}" "${expected_certificate_sha1}" "${requires_cloudkit}" "${signed_entitlements_path}" <<'PY'
import datetime
import hashlib
import plistlib
import sys

path, expected_bundle_id, expected_certificate_sha1, requires_cloudkit, signed_entitlements_path = sys.argv[1:]
with open(path, "rb") as profile_file:
    profile = plistlib.load(profile_file)

name = profile.get("Name", "unnamed profile")
expiration = profile.get("ExpirationDate")
if not isinstance(expiration, datetime.datetime):
    raise SystemExit(f"profile {name!r} has no valid ExpirationDate")
now = datetime.datetime.now(expiration.tzinfo) if expiration.tzinfo else datetime.datetime.now()
if expiration <= now:
    raise SystemExit(f"profile {name!r} expired at {expiration.isoformat()}")
if profile.get("ProvisionsAllDevices") is not True:
    raise SystemExit(f"profile {name!r} is not a Developer ID distribution profile")

entitlements = profile.get("Entitlements", {})
application_identifier = entitlements.get("com.apple.application-identifier") or entitlements.get(
    "application-identifier", ""
)
if not application_identifier.endswith("." + expected_bundle_id):
    raise SystemExit(
        f"profile {name!r} is for {application_identifier or 'an unknown app'}, not {expected_bundle_id}"
    )
if entitlements.get("get-task-allow") is True:
    raise SystemExit(f"profile {name!r} permits debugging and is not suitable for release")
if requires_cloudkit == "1":
    if "iCloud.com.hadm.PingScope" not in entitlements.get(
        "com.apple.developer.icloud-container-identifiers", []
    ):
        raise SystemExit(f"profile {name!r} does not authorize PingScope's CloudKit container")
    icloud_services = entitlements.get("com.apple.developer.icloud-services", [])
    if icloud_services != "*" and "CloudKit" not in icloud_services:
        raise SystemExit(f"profile {name!r} does not authorize CloudKit")
if expected_certificate_sha1:
    certificate_fingerprints = {
        hashlib.sha1(certificate).hexdigest().upper()
        for certificate in profile.get("DeveloperCertificates", [])
        if isinstance(certificate, bytes)
    }
    if expected_certificate_sha1.upper() not in certificate_fingerprints:
        raise SystemExit(
            f"profile {name!r} does not authorize signing identity certificate "
            f"{expected_certificate_sha1.upper()}"
        )
if signed_entitlements_path:
    with open(signed_entitlements_path, "rb") as entitlements_file:
        signed_entitlements = plistlib.load(entitlements_file)

    controlled_keys = {
        key
        for key in signed_entitlements
        if key.startswith("com.apple.developer.")
        or key == "com.apple.security.application-groups"
    }

    def value_is_authorized(requested, authorized):
        if authorized == "*":
            return True
        requested_values = requested if isinstance(requested, list) else [requested]
        authorized_values = authorized if isinstance(authorized, list) else [authorized]
        for requested_value in requested_values:
            if requested_value in authorized_values:
                continue
            if isinstance(requested_value, str) and any(
                isinstance(candidate, str)
                and candidate.endswith("*")
                and requested_value.startswith(candidate[:-1])
                for candidate in authorized_values
            ):
                continue
            return False
        return True

    for key in sorted(controlled_keys):
        if key not in entitlements or not value_is_authorized(
            signed_entitlements[key], entitlements[key]
        ):
            raise SystemExit(f"{key} is not authorized by profile {name!r}")

print(f"Validated Developer ID provisioning profile: {name} (expires {expiration.date()})")
PY
  then
    rm -f "${decoded_profile}"
    return 1
  fi

  rm -f "${decoded_profile}"
}

embed_developer_id_profile() {
  local profile_path="$1"
  local app_path="$2"
  local destination="${app_path}/Contents/embedded.provisionprofile"

  /usr/bin/ditto "${profile_path}" "${destination}"
  chmod 0644 "${destination}"
}
