#!/usr/bin/env bash
set -euo pipefail

DB_PATH="${1:-$HOME/Library/Application Support/PingScope/History.sqlite}"
OUTPUT_DIR="${2:-/tmp/pingscope-export-smoke}"
RANGE_SECONDS="${PING_SCOPE_EXPORT_RANGE_SECONDS:-86400}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "${DB_PATH}" ]] || fail "history database not found: ${DB_PATH}"

# sample_count is a placeholder here; this smoke test only needs the latest exportable host row.
host_row="$(sqlite3 "${DB_PATH}" "select host_id,address,method,coalesce(port,''),1 from ping_samples order by timestamp desc limit 1;")"
[[ -n "${host_row}" ]] || fail "no history samples available"

IFS='|' read -r host_id address method port sample_count <<<"${host_row}"
[[ "${sample_count}" -gt 0 ]] || fail "no samples available for export"

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

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
