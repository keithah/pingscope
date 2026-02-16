#!/bin/sh

# Xcode Cloud Post-Build Script
# Runs after Xcode build completes.

set -e

echo "Starting post-build processing..."

if [ "$CI_XCODEBUILD_ACTION" = "archive" ]; then
  echo "Archive build completed - verifying code signing"

  APP_PATH="$CI_ARCHIVE_PATH/Products/Applications/PingScope.app"
  if [ -d "$APP_PATH" ]; then
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
    codesign -d --entitlements - "$APP_PATH" 2>&1 || true
  else
    echo "Archive app not found at: $APP_PATH"
  fi

  # Create export options for App Store submission
  cat > "$CI_DERIVED_DATA_PATH/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>destination</key>
  <string>upload</string>
  <key>uploadSymbols</key>
  <true/>
  <key>compileBitcode</key>
  <false/>
</dict>
</plist>
EOF

  echo "Export options written to: $CI_DERIVED_DATA_PATH/ExportOptions.plist"
fi

echo "Post-build processing completed"
