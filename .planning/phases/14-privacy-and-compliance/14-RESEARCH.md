# Phase 14: Privacy and Compliance - Research

**Researched:** 2026-02-16
**Domain:** macOS App Store privacy manifest, compliance declarations, and sandbox testing
**Confidence:** HIGH

## Summary

Phase 14 completes all App Store compliance requirements to enable submission to App Review. The key deliverables are: (1) a valid PrivacyInfo.xcprivacy declaring required reason API usage, (2) privacy nutrition label questionnaire completion stating "Data Not Collected", (3) age rating questionnaire completion for 4+ rating, (4) export compliance declaration in Info.plist, and (5) verification that the App Store sandboxed build functions correctly with ICMP hidden and TCP/UDP working.

PingScope is in an excellent compliance position. The existing PrivacyInfo.xcprivacy already declares UserDefaults access with the correct CA92.1 reason code. The app collects no user data (no analytics, no tracking, no telemetry). Network access uses only standard OS-level APIs (TCP sockets, UDP sockets, ICMP raw sockets) with no custom encryption. The dual-build infrastructure from Phase 13 provides both App Store (sandboxed) and Developer ID (non-sandboxed) variants from the same codebase, with runtime sandbox detection already functional.

**Primary recommendation:** Verify existing privacy manifest is complete, add ITSAppUsesNonExemptEncryption=NO to Info.plist, complete App Store Connect questionnaires (nutrition label and age rating), test archived App Store build on clean environment, and document dual-mode behavior in reviewer notes.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PRIV-01 | PrivacyInfo.xcprivacy created declaring network client access | Already exists at Sources/PingScope/Resources/PrivacyInfo.xcprivacy with UserDefaults CA92.1 declared; network client is implicit in sandboxed apps via entitlements, not privacy manifest |
| PRIV-02 | Privacy manifest explicitly states "Data Not Collected" | NSPrivacyCollectedDataTypes is optional when no data is collected; omit the key entirely or provide empty array (best practice: omit) |
| PRIV-03 | Privacy Nutrition Label questionnaire completed in App Store Connect | Navigate to App Store Connect → App Privacy → answer questionnaire stating app collects no data across all 14 categories |
| PRIV-04 | Age rating questionnaire completed (4+ rating) | Complete updated age rating questionnaire in App Store Connect by January 31, 2026 deadline; PingScope qualifies for 4+ (no objectionable content) |
| PRIV-05 | Export compliance declaration added (ITSAppUsesNonExemptEncryption = NO) | Add to Configuration/Info.plist; app uses only OS-provided encryption (TCP/UDP networking), no custom encryption |
| PRIV-06 | Archived App Store build tested in sandbox environment | Archive via Xcode → Export → test on clean macOS environment; SandboxDetector.isRunningInSandbox should return true |
| PRIV-07 | ICMP option correctly hidden in App Store sandboxed build | PingMethod.availableCases returns [.tcp, .udp] when SandboxDetector.isRunningInSandbox is true (already implemented) |
| PRIV-08 | TCP/UDP options work correctly in App Store sandboxed build | Verify TCP port 80 and UDP port 53 connectivity work under sandbox (com.apple.security.network.client entitlement enables this) |
</phase_requirements>

## Standard Stack

### Core Components

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| PrivacyInfo.xcprivacy | N/A | Privacy manifest file | Mandatory starting May 1, 2024 for apps using required reason APIs |
| App Store Connect | Web UI | Privacy questionnaires and compliance forms | Only method to submit privacy nutrition label and age rating |
| TestFlight (macOS) | Built-in | Internal testing in sandbox environment | Official Apple beta testing platform for pre-submission verification |

**Critical deadline:** Updated age rating questionnaire must be completed by January 31, 2026 for all apps to avoid submission interruptions.

### Compliance Keys

| Info.plist Key | Value | Purpose | Required |
|----------------|-------|---------|----------|
| ITSAppUsesNonExemptEncryption | Boolean (NO) | Declares app uses only exempt encryption | Yes (streamlines export compliance) |
| NSPrivacyTracking | Boolean (false) | App does not track users | Optional (defaults to false if omitted) |
| NSPrivacyTrackingDomains | Array of strings | Domains used for tracking | Optional (required only if NSPrivacyTracking is true) |

**Installation:**
Privacy manifest already exists. Export compliance requires one Info.plist addition.

## Architecture Patterns

### Privacy Manifest Structure

```
PrivacyInfo.xcprivacy
├── NSPrivacyAccessedAPITypes          # Required reason APIs used
│   └── [Array of API type dictionaries]
│       ├── NSPrivacyAccessedAPIType          # Category (e.g., UserDefaults)
│       └── NSPrivacyAccessedAPITypeReasons   # Reason codes (e.g., CA92.1)
├── NSPrivacyCollectedDataTypes        # OPTIONAL if no data collected
│   └── [Empty or omitted]
├── NSPrivacyTracking                  # OPTIONAL (defaults false)
│   └── false
└── NSPrivacyTrackingDomains           # OPTIONAL (required only if tracking=true)
    └── [Empty or omitted]
```

**Key principle:** Privacy manifest declares API usage (what your app calls), not capabilities. Network access comes from entitlements (com.apple.security.network.client), not privacy manifest.

### Pattern 1: Required Reason API Declaration

**What:** Declare specific OS APIs that could be used for fingerprinting, with reasons justifying their use.

**When to use:** When app uses UserDefaults, file timestamp APIs, system boot time, disk space, or active keyboard APIs.

**Current PingScope usage:**
```xml
<key>NSPrivacyAccessedAPITypes</key>
<array>
    <dict>
        <key>NSPrivacyAccessedAPIType</key>
        <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
        <key>NSPrivacyAccessedAPITypeReasons</key>
        <array>
            <string>CA92.1</string>
        </array>
    </dict>
</array>
```

**CA92.1 meaning:** "Declare this reason to access user defaults for reading and writing data exclusive to the app itself. It does not allow reading data from other apps or the system, nor writing data accessible by other apps."

**Other categories to verify:**
- File Timestamp: NSPrivacyAccessedAPICategoryFileTimestamp (if using file modification dates)
- System Boot Time: NSPrivacyAccessedAPICategorySystemBootTime (if checking uptime)
- Disk Space: NSPrivacyAccessedAPICategoryDiskSpace (if checking available space)
- Active Keyboards: NSPrivacyAccessedAPICategoryActiveKeyboards (if querying keyboard layouts)

**PingScope status:** Only UserDefaults is used (for app preferences). No file timestamps, system boot time, disk space, or keyboard queries detected in codebase.

### Pattern 2: Data Collection Declaration (None)

**What:** NSPrivacyCollectedDataTypes declares the 14 data categories your app collects (contact info, health, financial, location, sensitive info, contacts, user content, browsing history, search history, identifiers, purchases, usage data, diagnostics, other data).

**When to omit:** When app collects no user data whatsoever.

**PingScope case:**
- No analytics SDKs
- No crash reporting to external services
- No user accounts or authentication
- No telemetry or usage tracking
- Network monitoring data stays local, never leaves device

**Best practice:** Omit NSPrivacyCollectedDataTypes key entirely from privacy manifest when no data is collected. This generates the "Data Not Collected" label automatically.

**Alternative:** Include key with empty array:
```xml
<key>NSPrivacyCollectedDataTypes</key>
<array/>
```

**Recommendation for PingScope:** Omit the key entirely (cleaner, less ambiguous).

### Pattern 3: Export Compliance Declaration

**What:** ITSAppUsesNonExemptEncryption declares whether app uses encryption requiring export documentation.

**When to set NO:**
- App uses only OS-provided encryption (HTTPS, URLSession, standard networking)
- No custom cryptography libraries (CryptoKit used only for hashing, not encryption)
- No proprietary encryption algorithms

**PingScope case:**
- TCP/UDP/ICMP networking uses standard OS APIs
- No CryptoKit, CommonCrypto, or custom encryption detected
- Network protocols (ping) are unencrypted by design

**Implementation:**
```xml
<!-- Export Compliance -->
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

**Effect:** Bypasses manual export compliance questionnaire on each upload, streamlining submission process.

### Pattern 4: Sandbox Testing Verification

**What:** Test App Store build in sandboxed environment to verify runtime behavior matches expectations.

**Process:**
1. Archive via Xcode using AppStore scheme
2. Export for "Distribution" (not "Development")
3. Install on clean macOS environment (or different user account)
4. Launch app and verify:
   - SandboxDetector.isRunningInSandbox returns true
   - ICMP option is hidden in UI
   - TCP and UDP options are visible
   - TCP ping to standard ports (80, 443) succeeds
   - UDP ping to standard ports (53, 123) succeeds
   - App launches and functions normally

**Verification commands:**
```bash
# Check if app is sandboxed
codesign -d --entitlements - /path/to/PingScope.app | grep com.apple.security.app-sandbox

# Should output: <key>com.apple.security.app-sandbox</key><true/>

# Check bundle identifier matches expected
codesign -dv /path/to/PingScope.app 2>&1 | grep Identifier

# Should output: Identifier=com.hadm.PingScope
```

**Warning signs of sandbox issues:**
- App crashes on launch (entitlement configuration error)
- ICMP option still visible (sandbox detection failure)
- TCP/UDP connections fail (network.client entitlement missing)
- File access errors (sandbox container path mismatch)

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Privacy manifest validation | Manual XML validation scripts | Xcode privacy report generator | Built-in validation, matches App Store rules |
| Export compliance tracking | Custom questionnaire tracking | ITSAppUsesNonExemptEncryption key | Apple-provided streamlined flow |
| Sandbox detection | Multiple heuristics (checking entitlements, API calls) | Simple path check (NSHomeDirectory contains /Library/Containers/) | Reliable, fast, sandbox-specific |
| Privacy nutrition label generation | Manual HTML/markdown documentation | App Store Connect questionnaire | Automatically generates standardized labels |
| TestFlight distribution | Manual .app distribution via file sharing | TestFlight internal testing | Proper sandbox environment, crash logs, feedback |

**Key insight:** Apple provides complete infrastructure for privacy compliance. Custom solutions add complexity without benefit and risk non-compliance if Apple changes requirements.

## Common Pitfalls

### Pitfall 1: Missing NSPrivacyCollectedDataTypes Causes Validation Error

**What goes wrong:** Some developers report App Store Connect validation errors stating "Missing an expected key: 'NSPrivacyCollectedDataTypes'" even when no data is collected.

**Why it happens:** Apple's validation has been inconsistent. Some submissions require the key with empty array, others accept omission.

**How to avoid:**
1. Start by omitting NSPrivacyCollectedDataTypes entirely
2. If validation fails, add empty array:
   ```xml
   <key>NSPrivacyCollectedDataTypes</key>
   <array/>
   ```
3. Resubmit and monitor validation results

**Warning signs:**
- Upload to App Store Connect succeeds but processing fails
- Email from App Store Connect about missing privacy information
- Validation error ITMS-90683 or similar privacy-related code

**Current status:** Based on 2024-2025 submissions, omitting the key is generally accepted for apps with no data collection. Include empty array only if validation explicitly requires it.

### Pitfall 2: UserDefaults Reason Code Mismatch

**What goes wrong:** Using wrong reason code for UserDefaults access (e.g., C56D.1 for SDK wrapper instead of CA92.1 for app-only access).

**Why it happens:** Three reason codes exist for UserDefaults:
- CA92.1: App-only access (PingScope case)
- 1C8F.1: App Group access (shared containers)
- C56D.1: Third-party SDK wrapper (SDK authors only)

**How to avoid:**
1. Verify app doesn't use App Groups: check entitlements for com.apple.security.application-groups
2. If no App Groups, use CA92.1
3. Never use C56D.1 unless building a third-party SDK

**Warning signs:**
- App rejection citing "inappropriate required reason code"
- UserDefaults access described as "SDK wrapper" in rejection
- App Groups entitlement exists but no UserDefaults reason code 1C8F.1

**PingScope status:** Correct CA92.1 reason code already in place. No App Groups detected in entitlements.

### Pitfall 3: ITSAppUsesNonExemptEncryption Not Set, Manual Questionnaire Every Upload

**What goes wrong:** Every upload to App Store Connect triggers manual export compliance questionnaire, slowing down submission.

**Why it happens:** Without ITSAppUsesNonExemptEncryption key in Info.plist, Apple assumes app *might* use non-exempt encryption and requires manual confirmation.

**How to avoid:**
1. Add to Info.plist:
   ```xml
   <key>ITSAppUsesNonExemptEncryption</key>
   <false/>
   ```
2. Verify: app uses only standard OS networking (HTTPS via URLSession is exempt)
3. No CryptoKit encryption, no CommonCrypto, no proprietary algorithms

**Warning signs:**
- Every upload requires answering "Does your app use encryption?" questionnaire
- 15-30 minute delay on each submission while waiting for export compliance
- Confusion about whether to answer "yes" or "no" to encryption questions

**PingScope verification:** No custom encryption detected. TCP/UDP/ICMP are unencrypted protocols. Setting to NO is correct.

### Pitfall 4: Age Rating Questionnaire Not Updated by January 31, 2026 Deadline

**What goes wrong:** Attempting to submit app update after January 31, 2026 fails with error about missing age rating information.

**Why it happens:** Apple overhauled age ratings in July 2025, adding 13+, 16+, 18+ categories and removing 12+, 17+. New mandatory questions added.

**How to avoid:**
1. Complete updated questionnaire in App Store Connect before January 31, 2026
2. Navigate to App → App Information → Age Rating
3. Answer all new questions (in-app controls, medical content, violent themes)
4. Save even if calculated rating doesn't change (updates to new system)

**Warning signs:**
- Email from Apple: "Final reminder: Answer the updated age ratings questions"
- Submission error after January 31, 2026 citing missing age rating
- Age rating shows 12+ or 17+ (deprecated categories)

**PingScope case:** Network monitoring utility with no objectionable content qualifies for 4+ rating. Must still complete questionnaire to migrate to new system.

### Pitfall 5: Sandbox Detection Fails in Production Build

**What goes wrong:** App shows ICMP option in App Store build despite running in sandbox, or hides ICMP in Developer ID build when it should be available.

**Why it happens:** Sandbox detection relies on path check (NSHomeDirectory contains /Library/Containers/). If Apple changes container paths or developer tests in wrong environment, detection breaks.

**How to avoid:**
1. Test archived App Store build (not Xcode debug build)
2. Verify entitlements using codesign:
   ```bash
   codesign -d --entitlements - /path/to/PingScope.app | grep app-sandbox
   ```
3. Test on clean environment (different user account or VM)
4. Add logging to SandboxDetector for verification:
   ```swift
   print("Home directory: \(NSHomeDirectory())")
   print("Is sandboxed: \(isRunningInSandbox)")
   ```

**Warning signs:**
- SandboxDetector always returns false (path check broken)
- ICMP visible in sandboxed build (detection not applied to UI)
- App crashes when attempting ICMP in sandbox (detection bypassed)

**PingScope implementation:** SandboxDetector checks `/Library/Containers/` path. Verify during Phase 14 testing.

### Pitfall 6: TestFlight Build Not Properly Sandboxed

**What goes wrong:** TestFlight internal build behaves like Developer ID build (ICMP visible, no sandbox restrictions).

**Why it happens:** Wrong build scheme selected during archive, or entitlements not properly configured for App Store distribution.

**How to avoid:**
1. Xcode → Product → Scheme → Select "PingScope-AppStore" (not DeveloperID)
2. Xcode → Product → Archive
3. Organizer → Distribute App → App Store Connect
4. Upload to TestFlight
5. Download from TestFlight and verify sandbox behavior

**Warning signs:**
- TestFlight build shows ICMP option (wrong scheme)
- SandboxDetector.isRunningInSandbox returns false in TestFlight build
- Network access works without network.client entitlement

**Verification:** TestFlight builds MUST use AppStore scheme with sandbox enabled entitlements.

## Code Examples

### Complete Privacy Manifest (PingScope)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Required Reason APIs -->
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <!-- UserDefaults for app preferences (ping intervals, notification settings, etc.) -->
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <!-- CA92.1: App-only access, no sharing with other apps -->
                <string>CA92.1</string>
            </array>
        </dict>
    </array>

    <!-- Data Collection: None (omit NSPrivacyCollectedDataTypes entirely) -->
    <!-- Tracking: None (NSPrivacyTracking defaults to false when omitted) -->
    <!-- Tracking Domains: None (NSPrivacyTrackingDomains not needed when tracking=false) -->
</dict>
</plist>
```

**Source:** Based on existing Sources/PingScope/Resources/PrivacyInfo.xcprivacy with validation against Apple TN3183.

**Note:** If validation requires NSPrivacyCollectedDataTypes, add empty array:
```xml
<key>NSPrivacyCollectedDataTypes</key>
<array/>
```

### Export Compliance in Info.plist

```xml
<!-- Add to Configuration/Info.plist -->

<!-- Export Compliance -->
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

**Rationale:** PingScope uses only standard OS networking APIs. TCP, UDP, and ICMP protocols are unencrypted. No custom cryptography.

**Source:** [ITSAppUsesNonExemptEncryption | Apple Developer Documentation](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption)

### Sandbox Verification Script

```bash
#!/usr/bin/env bash
# verify-sandbox.sh - Check App Store build sandbox configuration

APP_PATH="$1"

if [ -z "$APP_PATH" ]; then
    echo "Usage: $0 /path/to/PingScope.app"
    exit 1
fi

echo "=== Sandbox Verification ==="
echo "App: $APP_PATH"
echo

# Check entitlements for sandbox
echo "1. Checking entitlements..."
SANDBOX_STATUS=$(codesign -d --entitlements - "$APP_PATH" 2>/dev/null | grep -A1 "com.apple.security.app-sandbox")

if echo "$SANDBOX_STATUS" | grep -q "<true/>"; then
    echo "✅ Sandbox: ENABLED (correct for App Store)"
else
    echo "❌ Sandbox: DISABLED (ERROR - App Store requires sandbox)"
    exit 1
fi

# Check network client entitlement
echo
echo "2. Checking network entitlement..."
NETWORK_STATUS=$(codesign -d --entitlements - "$APP_PATH" 2>/dev/null | grep -A1 "com.apple.security.network.client")

if echo "$NETWORK_STATUS" | grep -q "<true/>"; then
    echo "✅ Network Client: ENABLED (required for TCP/UDP)"
else
    echo "❌ Network Client: DISABLED (ERROR - app needs network access)"
    exit 1
fi

# Check privacy manifest
echo
echo "3. Checking privacy manifest..."
PRIVACY_MANIFEST="$APP_PATH/Contents/Resources/PrivacyInfo.xcprivacy"

if [ -f "$PRIVACY_MANIFEST" ]; then
    echo "✅ Privacy Manifest: PRESENT"

    # Check for UserDefaults declaration
    if grep -q "NSPrivacyAccessedAPICategoryUserDefaults" "$PRIVACY_MANIFEST"; then
        echo "✅ UserDefaults API: DECLARED"
    else
        echo "⚠️  UserDefaults API: NOT DECLARED (may be required)"
    fi

    # Check for CA92.1 reason code
    if grep -q "CA92.1" "$PRIVACY_MANIFEST"; then
        echo "✅ Reason Code CA92.1: PRESENT"
    else
        echo "⚠️  Reason Code: Different code used (verify correctness)"
    fi
else
    echo "❌ Privacy Manifest: MISSING (ERROR - required for App Store)"
    exit 1
fi

# Check Info.plist for export compliance
echo
echo "4. Checking export compliance..."
EXPORT_STATUS=$(/usr/libexec/PlistBuddy -c "Print ITSAppUsesNonExemptEncryption" "$APP_PATH/Contents/Info.plist" 2>/dev/null)

if [ "$EXPORT_STATUS" = "false" ]; then
    echo "✅ Export Compliance: DECLARED (ITSAppUsesNonExemptEncryption=NO)"
else
    echo "⚠️  Export Compliance: NOT DECLARED (will require manual questionnaire)"
fi

echo
echo "=== Verification Complete ==="
echo "App is ready for TestFlight upload if all checks passed."
```

**Usage:**
```bash
chmod +x verify-sandbox.sh
./verify-sandbox.sh ~/Library/Developer/Xcode/Archives/*/PingScope.xcarchive/Products/Applications/PingScope.app
```

### App Store Connect Reviewer Notes Template

```
App Review Notes for PingScope

OVERVIEW:
PingScope is a network latency monitoring utility that performs ping operations to user-configured hosts. The app supports three ping methods: TCP, UDP, and ICMP.

DUAL DISTRIBUTION MODEL:
PingScope is distributed through TWO channels:

1. App Store (THIS BUILD):
   - Runs in App Sandbox (com.apple.security.app-sandbox = true)
   - ICMP method is HIDDEN from UI (sandboxed apps cannot use raw sockets)
   - TCP and UDP methods are AVAILABLE and fully functional
   - Uses com.apple.security.network.client entitlement for network access

2. Developer ID (separate build, NOT this submission):
   - Distributed via GitHub releases for advanced users
   - Runs with hardened runtime but NO sandbox
   - All three methods (TCP, UDP, ICMP) are available
   - ICMP requires elevated privileges (sudo) for raw socket access

TESTING THIS BUILD:
To test TCP ping:
1. Add host: "google.com" or "1.1.1.1"
2. Select "TCP" method
3. Default port 80 will be used
4. Verify latency graph updates in real-time

To test UDP ping:
1. Add host: "8.8.8.8" (Google DNS)
2. Select "UDP" method
3. Default port 53 will be used
4. Verify latency graph updates in real-time

To verify ICMP is hidden:
1. Open Settings → Hosts
2. Add any host
3. Click method dropdown
4. Confirm only "TCP" and "UDP" are shown (no "ICMP" option)

PRIVACY:
- App collects NO user data (see Privacy Nutrition Label)
- Network monitoring data stays local on device
- No analytics, no tracking, no telemetry
- UserDefaults used only for app preferences (intervals, thresholds, UI state)

EXPORT COMPLIANCE:
- ITSAppUsesNonExemptEncryption = NO
- App uses only standard OS networking (TCP/UDP sockets, ICMP raw sockets)
- No custom encryption or proprietary algorithms

SYSTEM REQUIREMENTS:
- macOS 13.0 or later
- Network access required (monitors network latency)
- Menu bar access (app runs as menu bar utility)

Thank you for reviewing PingScope!
```

**Location to paste:** App Store Connect → App → Version → App Review Information → Notes

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Privacy policy webpage only | Privacy manifest + nutrition label | December 2020 (labels), May 2024 (manifests enforced) | Standardized, user-visible privacy disclosure |
| Manual export compliance questionnaire | ITSAppUsesNonExemptEncryption key | Available since iOS 10 (2016), recommended since 2020 | Streamlined submissions, one-time declaration |
| No required reason API disclosure | NSPrivacyAccessedAPITypes with reason codes | Announced WWDC 2023, enforced May 1, 2024 | Prevents fingerprinting abuse |
| Age ratings: 4+, 9+, 12+, 17+ | Age ratings: 4+, 9+, 13+, 16+, 18+ | July 2025 announcement, January 31, 2026 deadline | More granular content ratings |
| Separate TestFlight for iOS only | TestFlight for macOS | WWDC 2021 (macOS 12+) | Unified beta testing across Apple platforms |

**Deprecated/outdated:**
- **Standalone privacy policy webpage:** Still required for apps with accounts/data collection, but insufficient alone. Privacy manifest + nutrition label are mandatory.
- **12+ and 17+ age ratings:** Removed in July 2025 overhaul, replaced with 13+ and 18+.
- **altool for app validation:** Deprecated in fall 2023 for notarization; `xcrun altool --validate-app` still works for App Store validation but may be deprecated in future (watch for Apple announcements).
- **Privacy manifest optional:** Enforcement began May 1, 2024. Apps using required reason APIs (UserDefaults, file timestamps, etc.) MUST include privacy manifest or face rejection.

## Open Questions

1. **NSPrivacyCollectedDataTypes required or optional when empty?**
   - What we know: Apple docs say it's optional, some developers report validation errors requiring empty array
   - What's unclear: Whether App Store Connect validation has been updated to accept omission in all cases
   - Recommendation: Omit key initially; add empty array only if validation explicitly fails (ITMS-90683 error)

2. **TestFlight sandbox environment testing coverage**
   - What we know: TestFlight provides internal testing with sandboxed builds, up to 100 testers, 90-day test period
   - What's unclear: Whether TestFlight sandbox behavior exactly matches production App Store sandbox (historical discrepancies exist)
   - Recommendation: Test both TestFlight build AND production-archived build on clean environment; don't rely solely on TestFlight

3. **Privacy manifest changes after submission**
   - What we know: Privacy manifest is embedded in app bundle, cannot be changed without new build
   - What's unclear: If Apple adds new required reason API categories (they stated it's an "open list"), do existing approved apps need to update?
   - Recommendation: Monitor Apple Developer news for required reason API updates; update privacy manifest proactively when new categories announced

4. **Network access justification in privacy manifest**
   - What we know: Network access is granted via entitlements (com.apple.security.network.client), not privacy manifest
   - What's unclear: Whether future App Store requirements will require declaring network domains in privacy manifest (currently only tracking domains)
   - Recommendation: Current implementation (network.client entitlement only) is correct; monitor for policy changes

5. **Age rating 4+ with network access**
   - What we know: PingScope qualifies for 4+ (no objectionable content, violence, mature themes)
   - What's unclear: Whether network access alone triggers higher rating (unlikely, but questionnaire may ask)
   - Recommendation: Complete questionnaire honestly; if network access triggers higher rating, document rationale for appeal

## Sources

### Primary (HIGH confidence)

- [Privacy manifest files | Apple Developer Documentation](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) - Official privacy manifest structure
- [Describing use of required reason API | Apple Developer Documentation](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) - Required reason API categories and codes
- [ITSAppUsesNonExemptEncryption | Apple Developer Documentation](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption) - Export compliance declaration
- [Complying with Encryption Export Regulations | Apple Developer Documentation](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations) - When to use ITSAppUsesNonExemptEncryption=NO
- [App Privacy Details - App Store - Apple Developer](https://developer.apple.com/app-store/app-privacy-details/) - Privacy nutrition label overview
- [Age ratings values and definitions - App Store Connect](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/) - Age rating system
- [Age Rating Updates - Upcoming Requirements - Apple Developer](https://developer.apple.com/news/upcoming-requirements/?id=07242025a) - January 31, 2026 deadline for updated questionnaire
- [App review information - App Store Connect](https://developer.apple.com/help/app-store-connect/reference/app-review-information/) - Reviewer notes best practices
- [TestFlight overview - App Store Connect](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/) - Internal testing with sandbox

### Secondary (MEDIUM confidence)

- [TN3183: Adding required reason API entries to your privacy manifest | Apple Developer Documentation](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest) - Reason code details
- [Enforcement of Apple Privacy Manifest starting from May 1, 2024 - Bitrise Blog](https://bitrise.io/blog/post/enforcement-of-apple-privacy-manifest-starting-from-may-1-2024) - Enforcement timeline
- [Apple's New Privacy Requirements in the App Store | by Sachin Siwal | Medium](https://medium.com/@sachinsiwal/apples-new-privacy-requirements-in-the-app-store-92fb5b3e8a32) - Privacy manifest practical guide
- [Complying with Apple's New Privacy Requirements in the App Store | Bugfender](https://bugfender.com/blog/apple-privacy-requirements/) - Required reason API examples
- [TN3147: Migrating to the latest notarization tool | Apple Developer Documentation](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool) - altool deprecation for notarization
- [Apple Overhauls App Store Age Ratings - MacRumors](https://www.macrumors.com/2025/07/25/apple-overhauls-app-store-age-ratings/) - Age rating system changes
- [iOS Nutrition Labels: Your App Data Collection Policy | AppTweak](https://www.apptweak.com/en/aso-blog/ios-nutrition-labels-how-to-respond-to-apple-s-privacy-questions) - Nutrition label questionnaire tips

### Tertiary (LOW confidence - informational only)

- [How to add a privacy manifest file to your app | Donny Wals](https://www.donnywals.com/how-to-add-a-privacy-manifest-file-to-your-app-for-required-reason-api-usage/) - Community guide
- [Apple Privacy: A Comprehensive Guide to Privacy Manifest Files | Ostorlab](https://blog.ostorlab.co/apple-privacy-manifest-file.html) - Privacy manifest structure examples
- [Understanding Apple's Privacy Manifest for iOS Apps - Ottorino Bruni](https://www.ottorinobruni.com/understanding-apples-privacy-manifest-for-ios-apps/) - Privacy manifest walkthrough

## Metadata

**Confidence breakdown:**
- Privacy manifest requirements: HIGH - Official Apple documentation, enforced since May 2024, existing implementation verified
- Required reason API codes: HIGH - Apple TN3183 and official documentation, CA92.1 for UserDefaults confirmed
- Export compliance: HIGH - Official Apple documentation, straightforward no-encryption case
- Age rating questionnaire: HIGH - Official Apple requirements with January 31, 2026 deadline
- Privacy nutrition label: HIGH - Official App Store Connect documentation
- Sandbox testing: MEDIUM - Official Apple guidance, but TestFlight/production parity requires verification
- Reviewer notes best practices: MEDIUM - Official App Store Connect guidance plus community experience

**Research date:** 2026-02-16
**Valid until:** 2026-03-16 (30 days - stable domain with official requirements, but monitor for Apple policy updates)

**Current implementation status:**
- ✅ PrivacyInfo.xcprivacy exists with UserDefaults CA92.1 declared
- ✅ Sandbox detection implemented (SandboxDetector.isRunningInSandbox)
- ✅ ICMP hiding logic implemented (PingMethod.availableCases)
- ✅ Network client entitlement configured (com.apple.security.network.client in AppStore entitlements)
- ✅ Info.plist exists with required keys (LSApplicationCategoryType, LSMinimumSystemVersion, etc.)
- ⚠️ ITSAppUsesNonExemptEncryption not yet added (Phase 14 task)
- ⚠️ NSPrivacyCollectedDataTypes handling unclear (omit or empty array - verify during testing)
- ⚠️ Privacy nutrition label questionnaire not yet completed (App Store Connect task)
- ⚠️ Age rating questionnaire not yet completed (App Store Connect task)
- ⚠️ App Store build not yet tested in clean sandbox environment (Phase 14 verification task)
