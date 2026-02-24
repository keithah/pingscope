#!/bin/sh
# Xcode Cloud Post-Clone Script
# Runs after the repository is cloned.
#
# Build number (CFBundleVersion) is managed automatically by Xcode Cloud via
# the CI_BUILD_NUMBER environment variable and App Store Connect product settings.
# Marketing version (CFBundleShortVersionString) is set in the Xcode project's
# MARKETING_VERSION build setting — no manual plist manipulation needed here.

set -e

echo "Post-clone: Xcode Cloud environment ready."
echo "  CI_BUILD_NUMBER: ${CI_BUILD_NUMBER:-unset}"
echo "  CI_TAG:          ${CI_TAG:-unset}"
echo "  CI_BRANCH:       ${CI_BRANCH:-unset}"
echo "  CI_WORKFLOW:     ${CI_WORKFLOW:-unset}"
