#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-/Applications/PingScope.app}"
LOG_PATH="/tmp/pingscope-debug.log"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_log() {
  local pattern="$1"
  if ! grep -q "$pattern" "$LOG_PATH"; then
    echo "---- ${LOG_PATH} ----" >&2
    tail -200 "$LOG_PATH" >&2 || true
    fail "missing log pattern: ${pattern}"
  fi
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
defaults write com.hadm.PingScope overlayVisible -bool true
defaults write com.hadm.PingScope overlayCompactMode -bool false
defaults write com.hadm.PingScope widgetsEnabled -bool false
pkill -x PingScope 2>/dev/null || true
sleep 0.5
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

echo "PASS: PingScope app smoke validation passed (${w}x${h} overlay at ${x},${y})"
