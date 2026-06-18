#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

section() {
  echo "== $* =="
}

default_route_field() {
  local field="$1"
  route -n get default 2>/dev/null | awk -v field="${field}:" '$1 == field {print $2; exit}'
}

hardware_port_for_device() {
  local device="$1"
  networksetup -listallhardwareports 2>/dev/null | awk -v device="${device}" '
    /^Hardware Port:/ {
      port = substr($0, index($0, ":") + 2)
    }
    /^Device:/ {
      if ($2 == device) {
        print port
        exit
      }
    }
  '
}

is_ethernet_port() {
  local port="$1"
  [[ "${port}" == *Ethernet* || "${port}" == Thunderbolt* || "${port}" == "USB 10/100/1000 LAN" ]]
}

section "Default route"
GATEWAY="$(default_route_field gateway || true)"
INTERFACE="$(default_route_field interface || true)"
[[ -n "${GATEWAY}" ]] || fail "no default gateway detected"
[[ -n "${INTERFACE}" ]] || fail "no default route interface detected"

PORT="$(hardware_port_for_device "${INTERFACE}" || true)"
[[ -n "${PORT}" ]] || fail "default route interface ${INTERFACE} is not listed by networksetup"

echo "Gateway:   ${GATEWAY}"
echo "Interface: ${INTERFACE}"
echo "Port:      ${PORT}"

if ! is_ethernet_port "${PORT}"; then
  fail "default route is not Ethernet-backed; connect wired Ethernet and rerun"
fi

section "Gateway reachability"
ping -q -c 3 -W 1000 "${GATEWAY}"

section "Gateway TCP readiness"
python3 - "${GATEWAY}" <<'PY'
import socket
import sys

gateway = sys.argv[1]
last_error = None
for port in (80, 443):
    try:
        with socket.create_connection((gateway, port), timeout=2):
            print(f"PASS: TCP connection to {gateway}:{port}")
            break
    except OSError as error:
        last_error = error
else:
    raise SystemExit(f"FAIL: gateway did not accept TCP on 80 or 443: {last_error}")
PY

section "Probe validation"
swift run PingScopeProbeValidate

echo "PASS: Ethernet default gateway validation completed"
