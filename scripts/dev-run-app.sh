#!/usr/bin/env bash
set -euo pipefail

# Build and run PingScope as a minimal .app bundle.
# This is required for macOS notification permission prompts.

# If a prior non-bundled `swift run` instance is running, it can interfere with testing.
pkill -f "/\\.build/.*?/debug/PingScope$" >/dev/null 2>&1 || true

# Optional: force restart the app bundle.
if [[ "${PING_SCOPE_RESTART:-0}" == "1" ]]; then
  pkill -f "/PingScope\\.app/Contents/MacOS/PingScope" >/dev/null 2>&1 || true
fi

APP_DIR="$(scripts/build-app-bundle.sh debug)"
open "${APP_DIR}"
