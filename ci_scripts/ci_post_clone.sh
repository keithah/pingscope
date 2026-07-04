#!/bin/bash
set -euo pipefail

echo "Xcode Cloud post-clone: resolving PingScope package dependencies"

if [[ -n "${CI_WORKSPACE:-}" ]]; then
  cd "${CI_WORKSPACE}"
else
  cd "$(dirname "$0")/.."
fi

DERIVED_DATA_PATH="${CI_DERIVED_DATA_PATH:-${CI_WORKSPACE:-$(pwd)}/.build/xcode-cloud-derived-data}"

xcodebuild \
  -resolvePackageDependencies \
  -project PingScope.xcodeproj \
  -scheme PingScope-AppStore \
  -derivedDataPath "${DERIVED_DATA_PATH}"
