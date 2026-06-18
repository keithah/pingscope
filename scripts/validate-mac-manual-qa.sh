#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-/Applications/PingScope.app}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

overlay_bounds() {
  swift -e 'import CoreGraphics
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let windows = info.compactMap { window -> (Int, Int, Int, Int)? in
    guard window[kCGWindowOwnerName as String] as? String == "PingScope",
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let x = bounds["X"] as? Int,
          let y = bounds["Y"] as? Int,
          let w = bounds["Width"] as? Int,
          let h = bounds["Height"] as? Int,
          w >= 120,
          h >= 48
    else { return nil }
    return (x, y, w, h)
}
guard let overlay = windows.sorted(by: { ($0.2 * $0.3) < ($1.2 * $1.3) }).first else { exit(1) }
print("\(overlay.0),\(overlay.1),\(overlay.2),\(overlay.3)")'
}

require_overlay() {
  local frame_csv
  frame_csv="$(overlay_bounds)" || fail "PingScope overlay window was not visible"
  [[ -n "$frame_csv" ]] || fail "PingScope overlay window was not visible"
  echo "$frame_csv"
}

cleanup_fullscreen_app() {
  osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
tell application "System Events"
  if exists process "TextEdit" then
    tell process "TextEdit"
      set frontmost to true
      delay 0.2
      key code 3 using {control down, command down}
      delay 1
    end tell
  end if
end tell
tell application "TextEdit" to quit
APPLESCRIPT
}

osascript -e 'tell application "System Events" to if not UI elements enabled then error "Accessibility is not enabled for this terminal"'

trap cleanup_fullscreen_app EXIT

echo "== Overlay, popover, settings, and About smoke =="
scripts/validate-app-smoke.sh "$APP_PATH"

echo "== Full-screen Space overlay visibility =="
pkill -x PingScope 2>/dev/null || true
sleep 0.5
defaults write com.hadm.PingScope overlayVisible -bool true
defaults write com.hadm.PingScope overlayCompactMode -bool false
defaults write com.hadm.PingScope overlayAlwaysOnTop -bool true
defaults write com.hadm.PingScope overlayOpacity -float 1
defaults read com.hadm.PingScope >/dev/null
open "$APP_PATH"
sleep 3
require_overlay >/dev/null

open -a TextEdit
sleep 1
osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "TextEdit"
    set frontmost to true
    delay 0.2
    key code 3 using {control down, command down}
  end tell
end tell
APPLESCRIPT
sleep 4
fullscreen_frame="$(require_overlay)"

echo "PASS: macOS manual QA automation passed; overlay remained visible in full-screen Space (${fullscreen_frame})"
