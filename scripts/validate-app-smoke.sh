#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-/Applications/PingScope.app}"
LOG_PATH="${HOME}/Library/Caches/PingScope/pingscope-debug.log"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_log() {
  local pattern="$1"
  for _ in {1..30}; do
    if [[ -f "$LOG_PATH" ]] && grep -q "$pattern" "$LOG_PATH"; then
      return 0
    fi
    sleep 0.1
  done
  echo "---- ${LOG_PATH} ----" >&2
  tail -200 "$LOG_PATH" >&2 || true
  fail "missing log pattern: ${pattern}"
}

require_settings_text() {
  local pattern="$1"
  local dump
  for _ in {1..8}; do
    dump="$(osascript <<'APPLESCRIPT'
on dumpElement(e, depth)
  if depth > 7 then return ""
  set lineText to ""
  tell application "System Events"
    try
      set n to name of e
      if n is not missing value then set lineText to lineText & (n as text) & linefeed
    end try
    try
      set v to value of e
      if v is not missing value then set lineText to lineText & (v as text) & linefeed
    end try
    set out to lineText
    try
      repeat with c in UI elements of e
        set out to out & my dumpElement(c, depth + 1)
      end repeat
    end try
    return out
  end tell
end dumpElement

tell application "System Events"
  tell process "PingScope"
    return my dumpElement(window "PingScope Settings", 0)
  end tell
end tell
APPLESCRIPT
)"
    if grep -q "$pattern" <<<"$dump"; then
      return 0
    fi
    sleep 0.5
  done
  if ! grep -q "$pattern" <<<"$dump"; then
    echo "---- PingScope Settings accessibility text ----" >&2
    echo "$dump" >&2
    fail "settings window missing text: ${pattern}"
  fi
}

select_settings_tab() {
  local tab="$1"
  case "$tab" in
    Hosts)
      swift -e 'import CoreGraphics; import Foundation
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
guard let window = info.first(where: {
    ($0[kCGWindowOwnerName as String] as? String) == "PingScope"
    && (($0[kCGWindowName as String] as? String)?.contains("Settings") ?? false)
}), let bounds = window[kCGWindowBounds as String] as? [String: Any],
   let x = bounds["X"] as? Int,
   let y = bounds["Y"] as? Int else { exit(0) }
let point = CGPoint(x: x + 78, y: y + 130)
CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(120000)
CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(500000)'
      ;;
  esac
}

post_click() {
  local x="$1"
  local y="$2"
  local button="${3:-left}"
  local down="leftMouseDown"
  local up="leftMouseUp"
  local cg_button="left"
  if [[ "$button" == "right" ]]; then
    down="rightMouseDown"
    up="rightMouseUp"
    cg_button="right"
  fi

  swift -e "import CoreGraphics; import Foundation; let p = CGPoint(x: Double(${x}), y: Double(${y})); CGEvent(mouseEventSource: nil, mouseType: .${down}, mouseCursorPosition: p, mouseButton: .${cg_button})?.post(tap: .cghidEventTap); usleep(120000); CGEvent(mouseEventSource: nil, mouseType: .${up}, mouseCursorPosition: p, mouseButton: .${cg_button})?.post(tap: .cghidEventTap); usleep(500000)"
}

window_bounds() {
  swift -e 'import CoreGraphics; let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []; for window in info { guard window[kCGWindowOwnerName as String] as? String == "PingScope", let bounds = window[kCGWindowBounds as String] as? [String: Any], let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"], (w as? Int ?? 0) >= 120, (h as? Int ?? 0) >= 48 else { continue }; print("\(x),\(y),\(w),\(h)"); exit(0) }; exit(1)'
}

osascript -e 'tell application "System Events" to if not UI elements enabled then error "Accessibility is not enabled for this terminal"'

rm -f "$LOG_PATH"
pkill -x PingScope 2>/dev/null || true
for _ in {1..30}; do
  if ! pgrep -x PingScope >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
defaults write com.hadm.PingScope overlayVisible -bool true
defaults write com.hadm.PingScope overlayCompactMode -bool false
defaults write com.hadm.PingScope overlayFrame -string '{{240, 620}, {240, 96}}'
defaults write com.hadm.PingScope widgetsEnabled -bool false
defaults write com.hadm.PingScope selectedSettingsTab hosts
killall cfprefsd 2>/dev/null || true
open "$APP_PATH"
sleep 2

frame_csv="$(window_bounds)"
[[ -n "$frame_csv" ]] || fail "PingScope overlay window was not found"

IFS=',' read -r raw_x raw_y raw_w raw_h <<<"$frame_csv"
x="$(echo "$raw_x" | tr -d ' ')"
y="$(echo "$raw_y" | tr -d ' ')"
w="$(echo "$raw_w" | tr -d ' ')"
h="$(echo "$raw_h" | tr -d ' ')"

[[ "$w" -ge 120 ]] || fail "overlay width is unexpectedly small: ${w}"
[[ "$h" -ge 48 ]] || fail "overlay height is unexpectedly small: ${h}"

center_x=$((x + w / 2))
graph_y=$((y + h - 24))

post_click "$center_x" "$graph_y" right
require_log "overlay context menu requested"
osascript -e 'tell application "System Events" to key code 53'
sleep 0.2

post_click "$center_x" "$graph_y" left
require_log "overlay graph click fired"
require_log "AppDelegate.openPopoverFromOverlay called"

osascript \
  -e 'tell application "System Events" to tell process "PingScope" to set frontmost to true' \
  -e 'delay 0.2' \
  -e 'tell application "System Events" to keystroke "," using command down'
sleep 1
settings_count="$(osascript -e 'tell application "System Events" to tell process "PingScope" to count windows whose title contains "Settings"')"
[[ "$settings_count" -ge 1 ]] || fail "settings window did not open from Command-,"
select_settings_tab "Hosts"
sleep 0.5
require_settings_text "PingScope"
require_settings_text "Monitored Hosts"
require_settings_text "Cloudflare DNS"
require_settings_text "PRIMARY"
require_settings_text "TCP 1.1.1.1:443"
require_settings_text "Internet"

echo "PASS: PingScope app smoke validation passed (${w}x${h} overlay at ${x},${y})"
