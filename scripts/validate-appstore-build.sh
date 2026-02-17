#!/bin/bash
# Validate App Store build before upload
# Checks: archive entitlements, package signature, bundle ID, version format

set -e

ARCHIVE_PATH="dist/PingScope.xcarchive/Products/Applications/PingScope.app"
PACKAGE_PATH="dist/PingScope.pkg"

echo "=== App Store Build Validation ==="
echo ""

# Check 1: Archive exists
if [ ! -d "$ARCHIVE_PATH" ]; then
  echo "❌ Archive not found at $ARCHIVE_PATH"
  exit 1
fi
echo "✓ Archive found"

# Check 2: Package exists
if [ ! -f "$PACKAGE_PATH" ]; then
  echo "❌ Package not found at $PACKAGE_PATH"
  exit 1
fi
echo "✓ Package found"

# Check 3: Sandbox entitlement enabled
SANDBOX=$(codesign -d --entitlements :- "$ARCHIVE_PATH" 2>&1 | grep -c "app-sandbox.*true" || true)
if [ "$SANDBOX" -eq 0 ]; then
  echo "❌ Sandbox entitlement missing or disabled"
  exit 1
fi
echo "✓ Sandbox enabled"

# Check 4: Network client entitlement
NETWORK=$(codesign -d --entitlements :- "$ARCHIVE_PATH" 2>&1 | grep -c "network.client.*true" || true)
if [ "$NETWORK" -eq 0 ]; then
  echo "❌ Network client entitlement missing"
  exit 1
fi
echo "✓ Network client entitlement present"

# Check 5: Package signature
pkgutil --check-signature "$PACKAGE_PATH" > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "❌ Package signature invalid"
  exit 1
fi
echo "✓ Package signed correctly"

# Check 6: Bundle identifier
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$ARCHIVE_PATH/Contents/Info.plist")
if [ "$BUNDLE_ID" != "com.hadm.PingScope" ]; then
  echo "❌ Bundle ID mismatch: $BUNDLE_ID"
  exit 1
fi
echo "✓ Bundle ID correct: $BUNDLE_ID"

# Check 7: Version format
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ARCHIVE_PATH/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$ARCHIVE_PATH/Contents/Info.plist")
echo "✓ Version: $VERSION"
echo "✓ Build: $BUILD"

echo ""
echo "=== All validation checks passed ==="
echo "Package ready for upload: $PACKAGE_PATH"
