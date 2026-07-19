#!/usr/bin/env bash

validate_developer_id_profile() {
  local profile_path="$1"
  local expected_bundle_id="$2"
  local decoded_profile

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

  if ! /usr/bin/python3 - "${decoded_profile}" "${expected_bundle_id}" <<'PY'
import datetime
import plistlib
import sys

path, expected_bundle_id = sys.argv[1:]
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
application_identifier = entitlements.get("application-identifier", "")
if not application_identifier.endswith("." + expected_bundle_id):
    raise SystemExit(
        f"profile {name!r} is for {application_identifier or 'an unknown app'}, not {expected_bundle_id}"
    )
if entitlements.get("get-task-allow") is True:
    raise SystemExit(f"profile {name!r} permits debugging and is not suitable for release")
if "iCloud.com.hadm.PingScope" not in entitlements.get(
    "com.apple.developer.icloud-container-identifiers", []
):
    raise SystemExit(f"profile {name!r} does not authorize PingScope's CloudKit container")
if "CloudKit" not in entitlements.get("com.apple.developer.icloud-services", []):
    raise SystemExit(f"profile {name!r} does not authorize CloudKit")

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
