#!/usr/bin/env bash

validate_ios_live_activity_log() {
  local log_path="$1"
  local minimum_updates="${2:-2}"
  local update_count
  local delivered_count

  if [[ ! -f "${log_path}" ]]; then
    echo "Live Activity log not found: ${log_path}" >&2
    return 1
  fi

  if ! rg -q 'PingScope\[[^]]+\].*activityClient.*Requesting an activity:' "${log_path}"; then
    echo "PingScope did not request a Live Activity during the smoke window." >&2
    return 1
  fi

  if ! rg -q 'liveactivitiesd\[[^]]+\].*dismissParticipant.*Activity did start' "${log_path}"; then
    echo "ActivityKit did not report a successfully started PingScope Live Activity." >&2
    return 1
  fi

  update_count="$(rg -c 'PingScope\[[^]]+\].*activityClient.*Updating activity:' "${log_path}" || true)"
  delivered_count="$(rg -c 'liveactivitiesd\[[^]]+\].*outputParticipant.*Activity updated:' "${log_path}" || true)"

  if (( update_count < minimum_updates )); then
    echo "Expected at least ${minimum_updates} PingScope Live Activity updates; observed ${update_count}." >&2
    return 1
  fi

  if (( delivered_count < minimum_updates )); then
    echo "Expected at least ${minimum_updates} delivered Live Activity updates; observed ${delivered_count}." >&2
    return 1
  fi

  if rg -q 'Activity continues to be chatty' "${log_path}"; then
    echo "ActivityKit reported that the PingScope Live Activity continues to be chatty." >&2
    return 1
  fi

  if rg -q 'PingScope\[[^]]+\].*activityClient.*Ending activity:' "${log_path}"; then
    echo "The PingScope Live Activity ended during the smoke observation window." >&2
    return 1
  fi

  echo "Observed ${update_count} requested and ${delivered_count} delivered Live Activity updates without chatty warnings"
}
