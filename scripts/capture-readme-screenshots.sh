#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${PING_SCOPE_APP_PATH:-/Applications/PingScope.app}"
OUTPUT_DIR="${1:-images}"

mkdir -p "${OUTPUT_DIR}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

capture_screen() {
  local path="$1"
  if ! screencapture -x "${path}" 2>/tmp/pingscope-screencapture.err; then
    cat /tmp/pingscope-screencapture.err >&2 || true
    fail "screencapture failed. Grant Screen Recording permission to the terminal app and rerun."
  fi
}

capture_window() {
  local path="$1"
  local window_id="$2"
  if ! screencapture -x -l "${window_id}" "${path}" 2>/tmp/pingscope-screencapture.err; then
    cat /tmp/pingscope-screencapture.err >&2 || true
    fail "screencapture failed. Grant Screen Recording permission to the terminal app and rerun."
  fi
}

capture_region() {
  local path="$1"
  local bounds="$2"
  IFS=',' read -r x y w h <<<"${bounds}"
  local pad=12
  local rx=$((x > pad ? x - pad : 0))
  local ry=$((y > pad ? y - pad : 0))
  local rw=$((w + pad * 2))
  local rh=$((h + pad * 2))
  if ! screencapture -x -R"${rx},${ry},${rw},${rh}" "${path}" 2>/tmp/pingscope-screencapture.err; then
    cat /tmp/pingscope-screencapture.err >&2 || true
    fail "screencapture failed. Grant Screen Recording permission to the terminal app and rerun."
  fi
}

click_global() {
  local x="$1"
  local y="$2"
  swift -e "import CoreGraphics; import Foundation; let point = CGPoint(x: Double(${x}), y: Double(${y})); CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap); usleep(120000); CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap); usleep(600000)"
}

first_window_bounds() {
  swift -e 'import CoreGraphics; let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []; let windows = info.compactMap { window -> (Int, Int, Int, Int)? in guard window[kCGWindowOwnerName as String] as? String == "PingScope", let bounds = window[kCGWindowBounds as String] as? [String: Any], let x = bounds["X"] as? Int, let y = bounds["Y"] as? Int, let w = bounds["Width"] as? Int, let h = bounds["Height"] as? Int else { return nil }; return (x, y, w, h) }.sorted { ($0.2 * $0.3) > ($1.2 * $1.3) }; guard let first = windows.first else { exit(1) }; print("\(first.0),\(first.1),\(first.2),\(first.3)")'
}

first_window_id() {
  swift -e 'import CoreGraphics; let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []; let windows = info.compactMap { window -> (Int, Int, Int)? in guard window[kCGWindowOwnerName as String] as? String == "PingScope", let id = window[kCGWindowNumber as String] as? Int, let bounds = window[kCGWindowBounds as String] as? [String: Any], let w = bounds["Width"] as? Int, let h = bounds["Height"] as? Int, w >= 120, h >= 48 else { return nil }; return (id, w, h) }.sorted { ($0.1 * $0.2) > ($1.1 * $1.2) }; guard let first = windows.first else { exit(1) }; print(first.0)'
}

smallest_window_bounds() {
  swift -e 'import CoreGraphics; let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []; let windows = info.compactMap { window -> (Int, Int, Int, Int)? in guard window[kCGWindowOwnerName as String] as? String == "PingScope", let bounds = window[kCGWindowBounds as String] as? [String: Any], let x = bounds["X"] as? Int, let y = bounds["Y"] as? Int, let w = bounds["Width"] as? Int, let h = bounds["Height"] as? Int, w >= 120, h >= 48 else { return nil }; return (x, y, w, h) }.sorted { ($0.2 * $0.3) < ($1.2 * $1.3) }; guard let first = windows.first else { exit(1) }; print("\(first.0),\(first.1),\(first.2),\(first.3)")'
}

smallest_window_id() {
  swift -e 'import CoreGraphics; let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []; let windows = info.compactMap { window -> (Int, Int, Int)? in guard window[kCGWindowOwnerName as String] as? String == "PingScope", let id = window[kCGWindowNumber as String] as? Int, let bounds = window[kCGWindowBounds as String] as? [String: Any], let w = bounds["Width"] as? Int, let h = bounds["Height"] as? Int, w >= 120, h >= 48 else { return nil }; return (id, w, h) }.sorted { ($0.1 * $0.2) < ($1.1 * $1.2) }; guard let first = windows.first else { exit(1) }; print(first.0)'
}

osascript -e 'tell application "System Events" to if not UI elements enabled then error "Accessibility is not enabled for this terminal"'

defaults write com.hadm.PingScope overlayVisible -bool true
defaults write com.hadm.PingScope overlayCompactMode -bool false
defaults write com.hadm.PingScope overlayFrame -string "{{80, 760}, {260, 120}}"
defaults write com.hadm.PingScope widgetsEnabled -bool false
pkill -x PingScope 2>/dev/null || true
open "${APP_PATH}"
sleep 3

overlay_window_id="$(smallest_window_id)"
capture_window "${OUTPUT_DIR}/overlay.png" "${overlay_window_id}"

osascript \
  -e 'tell application "PingScope" to activate' \
  -e 'delay 0.2' \
  -e 'tell application "System Events" to keystroke "," using command down'
sleep 1
settings_bounds="$(first_window_bounds)"
settings_window_id="$(first_window_id)"
capture_window "${OUTPUT_DIR}/settings-hosts.png" "${settings_window_id}"

osascript -e 'tell application "System Events" to tell process "PingScope" to keystroke "]" using {command down, shift down}' || true
sleep 0.5
settings_bounds="$(first_window_bounds)"
settings_window_id="$(first_window_id)"
capture_window "${OUTPUT_DIR}/settings-notifications.png" "${settings_window_id}"

osascript -e 'tell application "System Events" to tell process "PingScope" to keystroke "]" using {command down, shift down}' || true
sleep 0.5
settings_bounds="$(first_window_bounds)"
settings_window_id="$(first_window_id)"
capture_window "${OUTPUT_DIR}/settings-advanced.png" "${settings_window_id}"

echo "Screenshots written to ${OUTPUT_DIR}"
