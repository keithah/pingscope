#!/usr/bin/env bash
set -euo pipefail

DB_PATH="${1:-$HOME/Library/Application Support/PingScope/History.sqlite}"
OUTPUT_DIR="${2:-}"
RANGE_SECONDS="${PING_SCOPE_EXPORT_RANGE_SECONDS:-86400}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "${DB_PATH}" ]] || fail "history database not found: ${DB_PATH}"

validate_output_dir() {
  local path="$1"
  local tmp_prefix="${TMPDIR:-/tmp}"
  case "${path}" in
    ""|"/"|"."|".."|"${HOME}"|"${HOME}/"|"$PWD"|"$PWD/") fail "refusing unsafe output directory: ${path}" ;;
    "${tmp_prefix%/}/"*|/tmp/*) ;;
    *) fail "output directory must be under ${tmp_prefix%/}/ or /tmp/: ${path}" ;;
  esac
  case "${path}" in
    *"/../"*|*".."|../*|/*"/.."|*"/./"*|*"//"*) fail "refusing unsafe output directory: ${path}" ;;
  esac
}

if [[ -z "${OUTPUT_DIR}" ]]; then
  OUTPUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pingscope-export-smoke.XXXXXX")"
else
  validate_output_dir "${OUTPUT_DIR}"
  rm -rf "${OUTPUT_DIR}"
  mkdir -p "${OUTPUT_DIR}"
fi

host_row="$(sqlite3 "${DB_PATH}" "select host_id,address,method,coalesce(port,'') from ping_samples order by timestamp desc limit 1;")"
[[ -n "${host_row}" ]] || fail "no history samples available"

IFS='|' read -r host_id address method port <<<"${host_row}"
# host_id came out of the database and is interpolated into the next query (and
# into the CLI args), so refuse anything that is not a plain UUID.
[[ "${host_id}" =~ ^[0-9a-fA-F-]{36}$ ]] || fail "unexpected host_id format: ${host_id}"
# Count the real rows for the chosen host so the gate and the PASS message are
# not hardcoded to 1 by the row-selection query.
sample_count="$(sqlite3 "${DB_PATH}" "select count(*) from ping_samples where host_id = '${host_id}';")"
[[ "${sample_count}" -gt 0 ]] || fail "no samples available for export"

args=(
  --db "${DB_PATH}"
  --output-dir "${OUTPUT_DIR}"
  --host-id "${host_id}"
  --name "Export Validation Host"
  --address "${address}"
  --method "${method}"
  --range-seconds "${RANGE_SECONDS}"
)
if [[ -n "${port}" ]]; then
  args+=(--port "${port}")
fi

swift run PingScopeExportValidate "${args[@]}"

for file in "${OUTPUT_DIR}/pingscope-export-smoke.csv" "${OUTPUT_DIR}/pingscope-export-smoke.json" "${OUTPUT_DIR}/pingscope-export-smoke.txt"; do
  [[ -s "${file}" ]] || fail "export output missing or empty: ${file}"
done

grep -q "timestamp,host,address,method,port,result,latency_ms" "${OUTPUT_DIR}/pingscope-export-smoke.csv" || fail "CSV header missing"
grep -q "PingScope History" "${OUTPUT_DIR}/pingscope-export-smoke.txt" || fail "text export header missing"
ruby -rjson -e 'JSON.parse(File.read(ARGV.fetch(0)))' "${OUTPUT_DIR}/pingscope-export-smoke.json" || fail "JSON export is invalid"

echo "PASS: history export validation passed (${sample_count} available samples, outputs in ${OUTPUT_DIR})"
