#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-/Applications/PingScope.app}"
GROUP_ID="${PING_SCOPE_APP_GROUP:-6R7S5GA944.group.com.hadm.PingScope}"
WIDGET_PATH="${PING_SCOPE_WIDGET_PATH:-}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_file() {
  [[ -e "$1" ]] || fail "missing $1"
}

require_entitlement() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  if ! codesign -d --entitlements :- "$path" 2>/dev/null | grep -q "$pattern"; then
    fail "${label} entitlement missing from ${path}"
  fi
}

require_file "${APP_PATH}/Contents/Info.plist"
if [[ -z "${WIDGET_PATH}" ]]; then
  WIDGET_PATH="$(find "${APP_PATH}/Contents/PlugIns" -maxdepth 1 -name '*.appex' -type d 2>/dev/null | sort | head -n 1)"
fi
[[ -n "${WIDGET_PATH}" ]] || fail "missing widget extension in ${APP_PATH}/Contents/PlugIns"
require_file "${WIDGET_PATH}/Contents/Info.plist"

point_id="$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "${WIDGET_PATH}/Contents/Info.plist")"
[[ "${point_id}" == "com.apple.widgetkit-extension" ]] || fail "unexpected widget extension point: ${point_id}"

require_entitlement "${APP_PATH}" "${GROUP_ID}" "app group"
require_entitlement "${WIDGET_PATH}" "${GROUP_ID}" "widget app group"
require_entitlement "${WIDGET_PATH}" "com.apple.security.app-sandbox" "widget sandbox"

swift -e 'import Foundation
let suite = ProcessInfo.processInfo.environment["PING_SCOPE_APP_GROUP"] ?? "6R7S5GA944.group.com.hadm.PingScope"
guard let defaults = UserDefaults(suiteName: suite) else {
  fatalError("missing suite \(suite)")
}
let fresh = defaults.data(forKey: "PingScopeWidgetSnapshot")?.count ?? 0
let legacy = defaults.data(forKey: "widgetData")?.count ?? 0
guard fresh > 0 else {
  fatalError("PingScopeWidgetSnapshot missing or empty")
}
guard legacy > 0 else {
  fatalError("legacy widgetData missing or empty")
}
print("Widget defaults: PingScopeWidgetSnapshot=\(fresh) bytes widgetData=\(legacy) bytes")
'

echo "PASS: widget bundle validation passed (${WIDGET_PATH})"
