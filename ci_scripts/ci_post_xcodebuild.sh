#!/bin/sh
# Xcode Cloud Post-Xcodebuild Script
# Runs after xcodebuild completes.
#
# On release/* tag builds: calls Fastlane submit_review to submit
# the latest TestFlight build for App Store review via ASC API.
# Requires Xcode Cloud environment variables: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_CONTENT

set -e

echo "Post-xcodebuild: CI_XCODEBUILD_ACTION=${CI_XCODEBUILD_ACTION:-unset}"

if [ "$CI_XCODEBUILD_ACTION" = "archive" ]; then
  echo "Archive completed. Verifying code signing..."

  APP_PATH="$CI_ARCHIVE_PATH/Products/Applications/PingScope.app"
  if [ -d "$APP_PATH" ]; then
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
    codesign -d --entitlements - "$APP_PATH" 2>&1 || true
    echo "Code signing verification passed."
  else
    echo "Warning: Archive app not found at expected path: $APP_PATH"
    echo "Available paths in archive:"
    ls "$CI_ARCHIVE_PATH/Products/" 2>/dev/null || true
  fi

  # Auto-submit for App Store review on release tag builds
  # Trigger: CI_TAG must match release/x.y.z pattern
  if echo "$CI_TAG" | grep -qE '^release/[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
    echo "Release tag detected: $CI_TAG — triggering App Store submission via Fastlane"

    # Verify required ASC API env vars are present
    if [ -z "$ASC_KEY_ID" ] || [ -z "$ASC_ISSUER_ID" ] || [ -z "$ASC_KEY_CONTENT" ]; then
      echo "ERROR: ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_CONTENT must be set in Xcode Cloud environment variables."
      echo "Configure these in App Store Connect > Xcode Cloud > [Workflow] > Environment."
      exit 1
    fi

    # Install Fastlane via Bundler
    cd "$CI_PRIMARY_REPOSITORY_PATH"
    gem install bundler --quiet
    bundle install --quiet

    # Submit latest build for App Store review
    bundle exec fastlane submit_review
    echo "App Store submission triggered successfully."
  else
    echo "Non-release build (CI_TAG=${CI_TAG:-none}) — skipping App Store submission."
  fi
fi

echo "Post-xcodebuild completed."
