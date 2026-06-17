#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PING_SCOPE_XCODE_PROJECT:-PingScope.xcodeproj}"
SCHEME="${PING_SCOPE_IOS_SCHEME:-PingScope-iOS}"

echo "== iOS-focused Swift tests =="
swift test --filter LiveMonitorSessionControllerTests

echo
echo "== SwiftPM iOS support product =="
swift build --target PingScopeiOS

echo
echo "== iOS Simulator build =="
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build

echo
echo "== iOS device archive-style build =="
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build

echo
echo "PASS: iOS validation passed"
