#!/usr/bin/env bash
set -euo pipefail

duration_to_seconds() {
  local value="$1"
  awk -v value="${value}" 'BEGIN {
    days = 0
    if (index(value, "-") > 0) {
      split(value, day_parts, "-")
      days = day_parts[1] + 0
      value = day_parts[2]
    }
    count = split(value, parts, ":")
    if (count == 3) {
      hours = parts[1] + 0
      minutes = parts[2] + 0
      seconds = parts[3] + 0
    } else if (count == 2) {
      hours = 0
      minutes = parts[1] + 0
      seconds = parts[2] + 0
    } else if (count == 1) {
      hours = 0
      minutes = 0
      seconds = parts[1] + 0
    } else {
      exit 2
    }
    printf "%.3f\n", days * 86400 + hours * 3600 + minutes * 60 + seconds
  }'
}

cpu_time_to_seconds() {
  duration_to_seconds "$1"
}

elapsed_time_to_seconds() {
  duration_to_seconds "$1"
}

duty_cycle_percent() {
  local cpu_seconds="$1"
  local elapsed_seconds="$2"
  awk -v cpu="${cpu_seconds}" -v elapsed="${elapsed_seconds}" 'BEGIN {
    if (elapsed <= 0) exit 2
    printf "%.3f\n", cpu * 100 / elapsed
  }'
}

soak_cpu_check_main() {
  local threshold="${1:-${PING_SCOPE_CPU_THRESHOLD_PERCENT:-5}}"
  local pid
  local process_table
  local process_row
  local cpu_time
  local elapsed_time
  local instantaneous_cpu
  local cpu_seconds
  local elapsed_seconds
  local duty_cycle
  local cpu_minutes_per_day

  if ! awk -v threshold="${threshold}" 'BEGIN { exit !(threshold >= 0) }'; then
    echo "Invalid CPU duty-cycle threshold: ${threshold}" >&2
    return 64
  fi

  pid="$(pgrep -x PingScope | head -n 1 || true)"
  if [[ -z "${pid}" ]]; then
    echo "PingScope is not running. Relaunch the installed build before checking the soak." >&2
    return 66
  fi

  echo '$ ps -Ao pid,time,etime,pcpu'
  process_table="$(ps -Ao pid,time,etime,pcpu)"
  process_row="$(printf '%s\n' "${process_table}" | awk -v pid="${pid}" '$1 == pid { print; exit }')"
  if [[ -z "${process_row}" ]]; then
    echo "PingScope PID ${pid} exited before it could be sampled." >&2
    return 69
  fi
  printf '%s\n%s\n' "$(printf '%s\n' "${process_table}" | head -n 1)" "${process_row}"

  read -r _ cpu_time elapsed_time instantaneous_cpu <<< "${process_row}"
  cpu_seconds="$(cpu_time_to_seconds "${cpu_time}")"
  elapsed_seconds="$(elapsed_time_to_seconds "${elapsed_time}")"
  duty_cycle="$(duty_cycle_percent "${cpu_seconds}" "${elapsed_seconds}")"
  cpu_minutes_per_day="$(awk -v duty="${duty_cycle}" 'BEGIN { printf "%.2f", duty * 14.4 }')"

  echo
  echo "PingScope PID: ${pid}"
  echo "Current ps CPU: ${instantaneous_cpu}%"
  echo "Cumulative CPU: ${cpu_time} (${cpu_seconds}s)"
  echo "Elapsed: ${elapsed_time} (${elapsed_seconds}s)"
  echo "Duty cycle: ${duty_cycle}% (threshold ${threshold}%)"
  echo "Projected CPU use: ${cpu_minutes_per_day} minutes/day at this duty cycle"

  if awk -v duty="${duty_cycle}" -v threshold="${threshold}" 'BEGIN { exit !(duty > threshold) }'; then
    echo "FAIL: cumulative CPU duty cycle exceeds ${threshold}%." >&2
    return 1
  fi
  echo "PASS: cumulative CPU duty cycle is at or below ${threshold}%."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  soak_cpu_check_main "$@"
fi
