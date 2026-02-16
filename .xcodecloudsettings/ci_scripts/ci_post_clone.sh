#!/bin/sh

# Wrapper for Xcode Cloud (kept under .xcodecloudsettings).

exec "$CI_PRIMARY_REPOSITORY_PATH/ci_scripts/ci_post_clone.sh"
