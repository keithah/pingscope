#!/bin/sh

# Xcode Cloud Post-Clone Script
# Runs after the repository is cloned.

set -e

echo "Starting post-clone setup..."

# Set version number from Xcode Cloud environment
if [ -n "$CI_TAG" ]; then
  VERSION="${CI_TAG#v}"
elif [ -n "$CI_BUILD_NUMBER" ]; then
  VERSION="0.0.$CI_BUILD_NUMBER"
else
  VERSION="0.0.0"
fi

echo "Setting version to: $VERSION"

# Update Info.plist with the version
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CI_PRIMARY_REPOSITORY_PATH/Info.plist" || true
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$CI_PRIMARY_REPOSITORY_PATH/Info.plist" || true

echo "Post-clone setup completed successfully"
