#!/usr/bin/env bash

find_sparkle_tool() {
  local tool_name="$1"
  local env_name="${2:-SPARKLE_$(printf '%s' "${tool_name}" | tr '[:lower:]' '[:upper:]')}"
  local env_value="${!env_name:-}"
  if [[ -n "${env_value}" ]]; then
    [[ -x "${env_value}" ]] && { printf '%s' "${env_value}"; return 0; }
    echo "${env_name} is set but not executable: ${env_value}" >&2
    return 1
  fi

  local tool
  for tool in \
    ".build/artifacts/sparkle/Sparkle/bin/${tool_name}" \
    ".build/checkouts/Sparkle/bin/${tool_name}" \
    "${PWD}/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/${tool_name}"
  do
    [[ -x "${tool}" ]] && { printf '%s' "${tool}"; return 0; }
  done

  if [[ "${SPARKLE_SEARCH_BUILD_ARTIFACTS:-0}" == "1" ]]; then
    tool=$(find .build -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/${tool_name}" -type f -perm -111 -print -quit 2>/dev/null || true)
    [[ -n "${tool}" && -x "${tool}" ]] && { printf '%s' "${tool}"; return 0; }
  fi

  return 1
}
