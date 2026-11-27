#!/usr/bin/env bash
# Runs the PingScopeUITests XCUITest suite.
#
# Local runs sign with the project's automatic signing. CI (or anyone without
# the team certificate) passes --adhoc: the app is signed "Sign to Run
# Locally" without the restricted iCloud/App Group entitlements, which macOS
# refuses to launch without a provisioning profile.
#
# Usage: scripts/test-ui.sh [--adhoc] [--result-bundle PATH] [-- extra xcodebuild args]
set -euo pipefail

cd "$(dirname "$0")/.."

adhoc=0
result_bundle="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/PingScopeUITests.xcresult"
extra=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --adhoc) adhoc=1; shift ;;
    --result-bundle) result_bundle="$2"; shift 2 ;;
    --) shift; extra=("$@"); break ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done

signing=()
if [[ $adhoc -eq 1 ]]; then
  signing=(
    CODE_SIGN_IDENTITY=-
    CODE_SIGN_STYLE=Manual
    DEVELOPMENT_TEAM=
    PROVISIONING_PROFILE_SPECIFIER=
    CODE_SIGN_ENTITLEMENTS=
  )
fi

rm -rf "$result_bundle"
xcodebuild test \
  -project PingScope.xcodeproj \
  -scheme PingScope-UITests \
  -configuration Debug \
  -destination 'platform=macOS' \
  -resultBundlePath "$result_bundle" \
  ${signing[@]+"${signing[@]}"} \
  ${extra[@]+"${extra[@]}"}

echo "Result bundle: $result_bundle"
