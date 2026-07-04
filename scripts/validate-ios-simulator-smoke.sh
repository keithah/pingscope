#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PING_SCOPE_XCODE_PROJECT:-PingScope.xcodeproj}"
SCHEME="${PING_SCOPE_IOS_SCHEME:-PingScope-iOS}"
SIMULATOR_NAME="${PING_SCOPE_IOS_SIMULATOR_NAME:-iPhone 17 Pro}"
DERIVED_DATA_PATH="${PING_SCOPE_IOS_SMOKE_DERIVED_DATA:-.build/ios-smoke}"
SCREENSHOT_PATH="${PING_SCOPE_IOS_SMOKE_SCREENSHOT:-.build/ios-smoke/screenshots/pingscope-ios-home.png}"
APP_BUNDLE_ID="${PING_SCOPE_IOS_BUNDLE_ID:-com.hadm.PingScope}"
CLEAN_BUILD="${PING_SCOPE_CLEAN:-0}"

echo "== Build iOS app for simulator =="
if [[ "${CLEAN_BUILD}" == "1" ]]; then
  rm -rf "${DERIVED_DATA_PATH}"
else
  rm -rf "${DERIVED_DATA_PATH}/Build/Products/Debug-iphonesimulator/PingScope.app"
fi
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -destination "platform=iOS Simulator,name=${SIMULATOR_NAME}" \
  -configuration Debug \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  CODE_SIGNING_ALLOWED=NO \
  build >/dev/null

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Debug-iphonesimulator/PingScope.app"
if [[ ! -d "${APP_PATH}" ]]; then
  echo "Expected simulator app not found: ${APP_PATH}" >&2
  exit 1
fi

SIM_ID="$(xcrun simctl list devices available | sed -n "s/.*${SIMULATOR_NAME} (\([-A-F0-9]*\)) (Booted).*/\1/p" | head -n 1)"
if [[ -z "${SIM_ID}" ]]; then
  SIM_ID="$(xcrun simctl list devices available | sed -n "s/.*${SIMULATOR_NAME} (\([-A-F0-9]*\)) (Shutdown).*/\1/p" | head -n 1)"
  if [[ -z "${SIM_ID}" ]]; then
    echo "Could not find available simulator named ${SIMULATOR_NAME}" >&2
    exit 1
  fi
  xcrun simctl boot "${SIM_ID}"
fi

echo "== Install and launch on ${SIMULATOR_NAME} =="
xcrun simctl uninstall "${SIM_ID}" "${APP_BUNDLE_ID}" >/dev/null 2>&1 || true
xcrun simctl install "${SIM_ID}" "${APP_PATH}"
xcrun simctl launch "${SIM_ID}" "${APP_BUNDLE_ID}" >/dev/null

DATA_CONTAINER="$(xcrun simctl get_app_container "${SIM_ID}" "${APP_BUNDLE_ID}" data)"
HISTORY_DB="${DATA_CONTAINER}/Library/Application Support/PingScope-iOS/History.sqlite"

SAMPLE_EXISTS=0
for _ in {1..40}; do
  PROCESS_LIST="$(xcrun simctl spawn "${SIM_ID}" /bin/ps -ax || true)"
  if rg -q "PingScope.app/PingScope|${APP_BUNDLE_ID}" <<<"${PROCESS_LIST}" && [[ -f "${HISTORY_DB}" ]]; then
    SAMPLE_EXISTS="$(sqlite3 "${HISTORY_DB}" "SELECT EXISTS(SELECT 1 FROM ping_samples LIMIT 1);")"
    [[ "${SAMPLE_EXISTS}" == "1" ]] && break
  fi
  sleep 0.5
done

if [[ "${SAMPLE_EXISTS}" != "1" ]]; then
  echo "Expected at least one iOS smoke sample." >&2
  exit 1
fi
SAMPLE_COUNT="$(sqlite3 "${HISTORY_DB}" "SELECT COUNT(*) FROM ping_samples;")"
echo "Recorded ${SAMPLE_COUNT} simulator sample(s)"

mkdir -p "$(dirname "${SCREENSHOT_PATH}")"
xcrun simctl io "${SIM_ID}" screenshot "${SCREENSHOT_PATH}" >/dev/null
file "${SCREENSHOT_PATH}"

echo "PASS: iOS simulator smoke passed"
