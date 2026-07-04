#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${PING_SCOPE_APP_PATH:-/Applications/PingScope.app}"
CLEAN_BUILD="${PING_SCOPE_CLEAN:-0}"
VALIDATE_DISTRIBUTION_BUILDS="${PING_SCOPE_VALIDATE_ROADMAP_DISTRIBUTION_BUILDS:-1}"

echo "== SwiftPM tests =="
swift test

echo
echo "== Live probe validation =="
scripts/validate-probes.sh

echo
echo "== Xcode Developer ID build with widget =="
if [[ "${VALIDATE_DISTRIBUTION_BUILDS}" == "1" ]]; then
  scripts/build-xcode-app-bundle.sh release /Applications developer-id
else
  echo "Skipping Developer ID build (PING_SCOPE_VALIDATE_ROADMAP_DISTRIBUTION_BUILDS=0)"
fi

echo
echo "== App smoke =="
scripts/validate-app-smoke.sh "${APP_PATH}"

echo
echo "== Widget bundle/shared data =="
defaults write com.hadm.PingScope widgetsEnabled -bool true
pkill -x PingScope 2>/dev/null || true
open "${APP_PATH}"
sleep 3
scripts/validate-widget-bundle.sh "${APP_PATH}"

echo
echo "== History export =="
scripts/validate-history-export.sh

echo
echo "== App Store sandbox bundle =="
if [[ "${VALIDATE_DISTRIBUTION_BUILDS}" == "1" ]]; then
  rm -rf /tmp/pingscope-appstore-roadmap
  if [[ "${CLEAN_BUILD}" == "1" ]]; then
    rm -rf .build/xcode-app-store-Release
  fi
  scripts/build-xcode-app-bundle.sh release /tmp/pingscope-appstore-roadmap app-store >/dev/null
  scripts/verify-sandbox.sh /tmp/pingscope-appstore-roadmap/PingScope.app appstore
else
  echo "Skipping App Store build (PING_SCOPE_VALIDATE_ROADMAP_DISTRIBUTION_BUILDS=0)"
fi

echo
echo "PASS: roadmap validation passed"
