#!/usr/bin/env bash
# verify-sandbox.sh - Validate App Store build compliance

APP_PATH="$1"

if [ -z "$APP_PATH" ]; then
    echo "Usage: $0 /path/to/PingScope.app"
    exit 1
fi

echo "=== PingScope Sandbox Verification ==="
echo "App: $APP_PATH"
echo

EXIT_CODE=0

# 1. Check sandbox entitlement
echo "1. Checking sandbox entitlement..."
SANDBOX_STATUS=$(codesign -d --entitlements :- "$APP_PATH" 2>/dev/null | grep -A1 "com.apple.security.app-sandbox")

if echo "$SANDBOX_STATUS" | grep -q "<true/>"; then
    echo "✓ Sandbox: ENABLED (correct for App Store)"
elif echo "$SANDBOX_STATUS" | grep -q "<false/>"; then
    echo "✓ Sandbox: DISABLED (expected for Developer ID build)"
    echo "  Note: Developer ID builds use separate entitlements"
else
    echo "✗ Sandbox: NOT FOUND (ERROR - entitlement missing)"
    EXIT_CODE=1
fi

# 2. Check network client entitlement
echo
echo "2. Checking network client entitlement..."
NETWORK_STATUS=$(codesign -d --entitlements :- "$APP_PATH" 2>/dev/null | grep -A1 "com.apple.security.network.client")

if echo "$NETWORK_STATUS" | grep -q "<true/>"; then
    echo "✓ Network Client: ENABLED (required for TCP/UDP)"
else
    echo "✗ Network Client: DISABLED (ERROR - app needs network access)"
    EXIT_CODE=1
fi

# 3. Check privacy manifest exists
echo
echo "3. Checking privacy manifest..."
PRIVACY_MANIFEST="$APP_PATH/Contents/Resources/PrivacyInfo.xcprivacy"

if [ -f "$PRIVACY_MANIFEST" ]; then
    echo "✓ Privacy Manifest: PRESENT"

    # 4. Check UserDefaults API declaration
    echo
    echo "4. Checking UserDefaults API declaration..."
    if grep -q "NSPrivacyAccessedAPICategoryUserDefaults" "$PRIVACY_MANIFEST"; then
        echo "✓ UserDefaults API: DECLARED"
    else
        echo "✗ UserDefaults API: NOT DECLARED (ERROR - required for App Store)"
        EXIT_CODE=1
    fi

    # 5. Check CA92.1 reason code
    echo
    echo "5. Checking CA92.1 reason code..."
    if grep -q "CA92.1" "$PRIVACY_MANIFEST"; then
        echo "✓ Reason Code CA92.1: PRESENT (app-only UserDefaults)"
    else
        echo "✗ Reason Code CA92.1: MISSING (ERROR - required for UserDefaults access)"
        EXIT_CODE=1
    fi
else
    echo "✗ Privacy Manifest: MISSING (ERROR - required for App Store)"
    EXIT_CODE=1
fi

# 6. Check export compliance
echo
echo "6. Checking export compliance..."
INFO_PLIST="$APP_PATH/Contents/Info.plist"

if [ -f "$INFO_PLIST" ]; then
    EXPORT_STATUS=$(/usr/libexec/PlistBuddy -c "Print ITSAppUsesNonExemptEncryption" "$INFO_PLIST" 2>/dev/null)

    if [ "$EXPORT_STATUS" = "false" ]; then
        echo "✓ Export Compliance: DECLARED (ITSAppUsesNonExemptEncryption=false)"
        echo "  Enables streamlined App Store uploads"
    else
        echo "⚠ Export Compliance: NOT DECLARED (will require manual questionnaire)"
        echo "  Add ITSAppUsesNonExemptEncryption=false to Info.plist"
    fi
else
    echo "✗ Info.plist: NOT FOUND (ERROR - invalid app bundle)"
    EXIT_CODE=1
fi

echo
echo "=== Verification Complete ==="
if [ $EXIT_CODE -eq 0 ]; then
    echo "✓ All checks passed - app is ready for App Store submission"
else
    echo "✗ Some checks failed - please review errors above"
fi

exit $EXIT_CODE
