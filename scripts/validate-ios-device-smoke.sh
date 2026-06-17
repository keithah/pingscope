#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PING_SCOPE_XCODE_PROJECT:-PingScope.xcodeproj}"
SCHEME="${PING_SCOPE_IOS_SCHEME:-PingScope-iOS}"
DEVICE_ID="${PING_SCOPE_IOS_DEVICE_ID:-}"
DERIVED_DATA_PATH="${PING_SCOPE_IOS_DEVICE_DERIVED_DATA:-.build/ios-device-smoke}"
APP_BUNDLE_ID="${PING_SCOPE_IOS_BUNDLE_ID:-com.hadm.PingScope}"

if [[ -z "${DEVICE_ID}" ]]; then
  DEVICE_ID="$(xcrun devicectl list devices | awk '/iPhone/ && /available/ {print $3; exit}')"
fi

if [[ -z "${DEVICE_ID}" ]]; then
  echo "No available iPhone found. Set PING_SCOPE_IOS_DEVICE_ID to a device UUID or UDID." >&2
  exit 1
fi

echo "== Device details =="
xcrun devicectl device info details --device "${DEVICE_ID}" | sed -n '/deviceProperties:/,/connectionProperties:/p'

echo
echo "== Build iOS app for physical device =="
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -destination "id=${DEVICE_ID}" \
  -configuration Debug \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  -allowProvisioningUpdates \
  build >/dev/null

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Debug-iphoneos/PingScope.app"
if [[ ! -d "${APP_PATH}" ]]; then
  echo "Expected device app not found: ${APP_PATH}" >&2
  exit 1
fi

echo
echo "== Install and launch on physical device =="
xcrun devicectl device install app --device "${DEVICE_ID}" "${APP_PATH}" >/dev/null
LAUNCH_LOG="${DERIVED_DATA_PATH}/launch.log"
if ! xcrun devicectl device process launch --device "${DEVICE_ID}" --terminate-existing "${APP_BUNDLE_ID}" >"${LAUNCH_LOG}" 2>&1; then
  if rg -q "Locked|could not be, unlocked|device was not" "${LAUNCH_LOG}"; then
    echo "Device launch was denied because the iPhone is locked. Unlock the device and rerun this script." >&2
  else
    echo "Device launch failed. Full launch log: ${LAUNCH_LOG}" >&2
  fi
  cat "${LAUNCH_LOG}" >&2
  exit 1
fi

echo
echo "== Verify process is running =="
xcrun devicectl device info processes --device "${DEVICE_ID}" --json-output "${DERIVED_DATA_PATH}/processes.json" >/tmp/pingscope-ios-device-processes.txt
if ! rg -q "PingScope.app/PingScope" /tmp/pingscope-ios-device-processes.txt "${DERIVED_DATA_PATH}/processes.json"; then
  echo "PingScope process was not found after launch." >&2
  exit 1
fi

echo "PASS: iOS physical-device smoke passed"
