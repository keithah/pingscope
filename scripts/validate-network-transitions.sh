#!/usr/bin/env bash
set -euo pipefail

WIFI_SERVICE="${PING_SCOPE_WIFI_SERVICE:-Wi-Fi}"
ALLOW_WIFI_CYCLE="${PING_SCOPE_WIFI_CYCLE:-0}"
ALLOW_DNS_FAILURE="${PING_SCOPE_DNS_FAILURE:-1}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

section() {
  echo "== $* =="
}

gateway() {
  route -n get default 2>/dev/null | awk '/gateway:/ {print $2; exit}'
}

network_status() {
  if scutil -r 1.1.1.1 >/dev/null 2>&1; then
    echo "reachable"
  else
    echo "unreachable"
  fi
}

section "Current network"
echo "Reachability: $(network_status)"
CURRENT_GATEWAY="$(gateway || true)"
[[ -n "${CURRENT_GATEWAY}" ]] || fail "default gateway not detected"
echo "Default gateway: ${CURRENT_GATEWAY}"

section "Probe validation"
scripts/validate-probes.sh

if [[ "${ALLOW_DNS_FAILURE}" -eq 1 ]]; then
  section "DNS failure validation"
  if dscacheutil -q host -a name definitely-invalid.pingscope.invalid | grep -q 'ip_address'; then
    fail "unexpected DNS result for definitely-invalid.pingscope.invalid"
  fi
  echo "Expected DNS failure path observed"
fi

if [[ "${ALLOW_WIFI_CYCLE}" -eq 1 ]]; then
  section "Wi-Fi cycle"
  before_gateway="${CURRENT_GATEWAY}"
  networksetup -setairportpower "${WIFI_SERVICE}" off
  sleep 5
  echo "After Wi-Fi off: $(network_status)"
  networksetup -setairportpower "${WIFI_SERVICE}" on
  sleep 12
  after_gateway="$(gateway || true)"
  [[ -n "${after_gateway}" ]] || fail "default gateway not detected after Wi-Fi cycle"
  echo "Gateway before: ${before_gateway}"
  echo "Gateway after:  ${after_gateway}"
  scripts/validate-probes.sh
else
  echo "Skipping Wi-Fi cycle. Set PING_SCOPE_WIFI_CYCLE=1 to enable it."
fi

echo "PASS: network transition validation completed"
