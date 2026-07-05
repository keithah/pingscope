#!/usr/bin/env bash
set -euo pipefail

# Remove local build outputs and logs created by PingScope validation/release scripts.
# This is intentionally manual so normal incremental SwiftPM/Xcode builds can keep
# their cache until disk usage or stale build state becomes a problem.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/.build"

if [[ ! -d "${BUILD_DIR}" ]]; then
  echo "No .build directory found."
  exit 0
fi

du -sh "${BUILD_DIR}" 2>/dev/null || true
rm -rf \
  "${BUILD_DIR}"/archives \
  "${BUILD_DIR}"/archive-dd \
  "${BUILD_DIR}"/developerid-validation \
  "${BUILD_DIR}"/index-build \
  "${BUILD_DIR}"/ios-dd \
  "${BUILD_DIR}"/ios-device-smoke \
  "${BUILD_DIR}"/ios-generic-* \
  "${BUILD_DIR}"/ios-smoke \
  "${BUILD_DIR}"/ios-validation \
  "${BUILD_DIR}"/logs \
  "${BUILD_DIR}"/macos-* \
  "${BUILD_DIR}"/network-reconcile-qa \
  "${BUILD_DIR}"/release-github \
  "${BUILD_DIR}"/screenshots \
  "${BUILD_DIR}"/xcode-* \
  "${BUILD_DIR}"/xcode-install \
  "${BUILD_DIR}"/xcode-verify-*

echo "Removed PingScope script-generated build artifacts from ${BUILD_DIR}."
