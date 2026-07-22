#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/ios-live-activity-validation.sh"

HEALTHY_LOG="$(mktemp)"
CHATTY_LOG="$(mktemp)"
MISSING_START_LOG="$(mktemp)"
trap 'rm -f "${HEALTHY_LOG}" "${CHATTY_LOG}" "${MISSING_START_LOG}"' EXIT

printf '%s\n' \
  'PingScope[101:1] [com.apple.activitykit:activityClient] Requesting an activity: PingScopeLiveActivityAttributes' \
  'liveactivitiesd[202:2] [com.apple.activitykit:dismissParticipant] Activity did start ACTIVITY-1' \
  'PingScope[101:1] [com.apple.activitykit:activityClient] Updating activity: ACTIVITY-1; payload: PAYLOAD-1' \
  'liveactivitiesd[202:2] [com.apple.activitykit:outputParticipant] Activity updated: ACTIVITY-1' \
  'PingScope[101:1] [com.apple.activitykit:activityClient] Updating activity: ACTIVITY-1; payload: PAYLOAD-2' \
  'liveactivitiesd[202:2] [com.apple.activitykit:outputParticipant] Activity updated: ACTIVITY-1' \
  >"${HEALTHY_LOG}"

validate_ios_live_activity_log "${HEALTHY_LOG}" 2

rg -v 'Requesting an activity|Activity did start' "${HEALTHY_LOG}" >"${MISSING_START_LOG}"
if validate_ios_live_activity_log "${MISSING_START_LOG}" 2 >/dev/null 2>&1; then
  echo "Expected a log without a successful activity start to fail validation." >&2
  exit 1
fi

cp "${HEALTHY_LOG}" "${CHATTY_LOG}"
printf '%s\n' \
  'liveactivitiesd[202:2] [com.apple.activitykit:activityManager] Activity continues to be chatty: ACTIVITY-1' \
  >>"${CHATTY_LOG}"

if validate_ios_live_activity_log "${CHATTY_LOG}" 2 >/dev/null 2>&1; then
  echo "Expected chatty ActivityKit log to fail validation." >&2
  exit 1
fi

echo "PASS: iOS Live Activity log validation tests passed"
