#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PING_SCOPE_XCODE_PROJECT:-PingScope.xcodeproj}"
SCHEME="${PING_SCOPE_IOS_SCHEME:-PingScope-iOS}"
DERIVED_DATA_PATH="${PING_SCOPE_IOS_DERIVED_DATA_PATH:-.build/ios-validation}"
RUN_SWIFTPM_BUILD="${PING_SCOPE_VALIDATE_IOS_SWIFTPM_BUILD:-1}"

echo "== iOS-focused Swift tests =="
swift test --filter LiveMonitorSessionControllerTests

if [[ "${RUN_SWIFTPM_BUILD}" == "1" ]]; then
  echo
  echo "== SwiftPM iOS support product =="
  swift build --target PingScopeiOS
fi

echo
echo "== iOS Simulator build =="
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo
echo "== iOS device archive-style build =="
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo
echo "PASS: iOS validation passed"
