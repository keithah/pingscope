#!/bin/bash
set -euo pipefail

echo "Xcode Cloud post-clone: resolving PingScope package dependencies"

xcodebuild \
  -resolvePackageDependencies \
  -project PingScope.xcodeproj \
  -scheme PingScope-AppStore
