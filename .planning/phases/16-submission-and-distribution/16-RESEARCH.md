# Phase 16: Submission and Distribution - Research

**Researched:** 2026-02-16
**Domain:** macOS App Store submission workflow and CI/CD automation
**Confidence:** HIGH

## Summary

Phase 16 establishes the complete workflow for submitting PingScope to the App Store and automating future releases. The technical challenge is orchestrating the multi-step submission process: local validation → App Store Connect upload → TestFlight internal testing → App Review submission → CI/CD automation. This phase transitions from manual first submission (for learning and verification) to automated release workflows.

PingScope already has all prerequisites: Xcode 26+ project with App Store build scheme, sandboxed entitlements, privacy compliance, and complete metadata. Phase 16 focuses on the mechanics of submission: using `xcrun altool` for validation/upload, Transporter as backup, TestFlight for internal testing, and GitHub Actions for reproducible release automation.

**Primary recommendation:** Execute first submission manually using `xcrun altool --validate-app` and `--upload-app` with App Store Connect API key authentication. Document the complete workflow in detail. Then create GitHub Actions workflow with `workflow_dispatch` manual trigger for App Store builds, using separate secrets for App Store distribution certificates and provisioning profiles.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SUBM-01 | App built with Xcode 26+ using macOS 26 SDK | Mandatory starting April 28, 2026 - official Apple requirement |
| SUBM-02 | App Store distribution certificate obtained | Requires Apple Developer account with Admin role; generated in Certificates, Identifiers & Profiles |
| SUBM-03 | App Store provisioning profile configured | Created in App Store Connect after app record exists; downloaded and installed in Xcode |
| SUBM-04 | App bundle validated locally with xcrun altool --validate-app | Pre-upload validation checks entitlements, code signing, Info.plist, asset catalog, and App Store compliance |
| SUBM-05 | App uploaded to App Store Connect via Transporter | Multiple upload methods available: Xcode GUI, Transporter app, xcrun altool CLI, App Store Connect API |
| SUBM-06 | TestFlight internal build tested (up to 100 users) | Internal testers = App Store Connect users; no review required; 90-day testing window; requires Xcode 13+ for macOS apps |
| SUBM-07 | First submission to App Review completed | Typical review time: 24-48 hours for new apps; 90% reviewed in <24 hours; requires complete metadata + screenshots |
| SUBM-08 | Manual submission workflow documented | Critical for reproducibility and team handoff; document all steps, credentials, gotchas, and verification checks |
| SUBM-09 | GitHub Actions workflow created for App Store builds (.github/workflows/appstore-release.yml) | Pattern: separate workflow from existing Developer ID production-release.yml; uses xcodebuild archive + exportArchive |
| SUBM-10 | CI/CD workflow tested with manual trigger | workflow_dispatch event enables manual triggers with custom inputs (version number, build number, release notes) |
</phase_requirements>

## Standard Stack

### Core Distribution Tools

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Xcode | 26+ | Archive and export | Mandatory for App Store uploads starting April 2026 |
| xcrun altool | Built-in | Validate and upload | Official command-line tool included with Xcode |
| Transporter | 1.3+ | GUI/CLI upload alternative | Official Apple tool; requires newer version in 2026 for Aspera/Signiant protocols |
| App Store Connect API | v1 | Programmatic submission | Recommended for CI/CD; uses JWT authentication; bypasses 2FA issues |
| TestFlight | Built-in | Internal/external testing | Official beta distribution; integrated with App Store Connect |

**Critical 2026 changes:**
- **Xcode 14+ required** for uploads (enforced starting 2026)
- **altool `-assetFile` command** required instead of `-f` (new 2026 requirement)
- **Transporter protocol updates** for Aspera/Signiant (HTTPS unaffected)

### Supporting Tools

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| notarytool | Built-in (Xcode 13+) | Notarization (Developer ID) | Not needed for App Store submission (already notarized by Apple) |
| fastlane deliver | 2.x | Metadata automation | Optional for first submission; useful for updates with metadata changes |
| fastlane pilot | 2.x | TestFlight automation | Optional; automates tester management and build upload to TestFlight |
| gh CLI | 2.x | GitHub release automation | Already used in existing production-release.yml workflow |

### Installation

```bash
# Xcode Command Line Tools (includes altool)
xcode-select --install

# Verify Xcode 26+
xcodebuild -version
# Expected: Xcode 26.0 or later

# Transporter (optional GUI upload tool)
# Download from Mac App Store: https://apps.apple.com/us/app/transporter/id1450874784

# fastlane (optional automation)
brew install fastlane

# App Store Connect API key setup
# 1. Generate in App Store Connect → Users and Access → Keys
# 2. Download .p8 private key file (one-time download)
# 3. Note Key ID and Issuer ID for authentication
```

## Architecture Patterns

### Recommended Workflow Structure

```
Manual First Submission (Phase 16)
├── 1. Local Validation
│   ├── xcodebuild archive (AppStore scheme)
│   ├── xcodebuild -exportArchive (method: app-store)
│   └── xcrun altool --validate-app (pre-upload check)
├── 2. Upload to App Store Connect
│   ├── xcrun altool --upload-app (primary method)
│   └── Transporter GUI (backup if altool fails)
├── 3. TestFlight Internal Testing
│   ├── Wait for build processing (5-30 min typical)
│   ├── Add internal testers in App Store Connect
│   ├── Install TestFlight app on test devices
│   └── Verify sandbox behavior matches Developer ID
├── 4. App Review Submission
│   ├── Complete metadata in App Store Connect
│   ├── Select processed build
│   ├── Submit for review
│   └── Wait 24-48 hours for first review
└── 5. Documentation
    └── Record all steps, commands, gotchas for automation

Automated Subsequent Releases (Post-Phase 16)
├── GitHub Actions workflow_dispatch trigger
├── xcodebuild archive + exportArchive
├── xcrun altool --upload-app with API key
└── Manual TestFlight → Review submission in UI
```

### Pattern 1: App Store Connect API Authentication

**What:** Use JWT tokens generated from App Store Connect API keys instead of username/password for authentication.

**Why it's superior:**
- Bypasses 2FA/app-specific password complexity
- Works reliably in CI/CD environments
- Recommended by Apple for automation
- Supports fastlane, Transporter CLI, and altool

**Setup:**

```bash
# 1. Generate API key in App Store Connect
# Navigate to: Users and Access → Keys → App Store Connect API
# Role required: Admin, App Manager, or Developer
# Download: AuthKey_ABCD123456.p8 (KEEP SECURE - one-time download)

# 2. Store credentials for notarytool (also works for altool)
xcrun notarytool store-credentials "AppStoreConnectAPI" \
  --key /path/to/AuthKey_ABCD123456.p8 \
  --key-id ABCD123456 \
  --issuer d1234567-e89b-12d3-a456-426614174000

# 3. Use in altool commands
xcrun altool --validate-app \
  -f PingScope.pkg \
  -t macos \
  --apiKey ABCD123456 \
  --apiIssuer d1234567-e89b-12d3-a456-426614174000
```

**GitHub Actions secrets:**
- `APP_STORE_CONNECT_API_KEY` = Contents of .p8 file (base64 encoded)
- `APP_STORE_CONNECT_KEY_ID` = Key ID (e.g., ABCD123456)
- `APP_STORE_CONNECT_ISSUER_ID` = Issuer ID (UUID format)

**Source:** [App Store Connect API - Generating Tokens](https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests)

### Pattern 2: xcodebuild Archive and Export for App Store

**What:** Two-step process to create App Store-ready .pkg file from Xcode project.

**Command sequence:**

```bash
# Step 1: Archive the app
xcodebuild archive \
  -project PingScope.xcodeproj \
  -scheme PingScope-AppStore \
  -destination 'generic/platform=macOS' \
  -archivePath dist/PingScope.xcarchive

# Step 2: Export as .pkg for App Store
xcodebuild -exportArchive \
  -archivePath dist/PingScope.xcarchive \
  -exportOptionsPlist Configuration/ExportOptions-AppStore.plist \
  -exportPath dist/

# ExportOptions-AppStore.plist contents:
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
    <key>uploadSymbols</key>
    <true/>
    <key>compileBitcode</key>
    <false/>
</dict>
</plist>
```

**Critical detail:** When `method` is set to `app-store`, xcodebuild implicitly exports a `.pkg` file instead of `.app` directory. This is macOS-specific behavior.

**Verification:**

```bash
# Verify .pkg was created
ls -lh dist/PingScope.pkg

# Inspect package contents
pkgutil --check-signature dist/PingScope.pkg
# Expected: signed by Apple Distribution certificate

# Verify entitlements in archived app
codesign -d --entitlements - dist/PingScope.xcarchive/Products/Applications/PingScope.app
# Expected: com.apple.security.app-sandbox = true
```

**Source:** [Customizing the Xcode archive process](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution/customizing_the_notarization_workflow/customizing_the_xcode_archive_process)

### Pattern 3: GitHub Actions Manual Trigger with Inputs

**What:** Use `workflow_dispatch` event to enable manual release triggers with custom parameters.

**Implementation:**

```yaml
name: App Store Release

on:
  workflow_dispatch:
    inputs:
      version:
        description: 'Marketing version (e.g., 1.1.0)'
        required: true
        type: string
      build:
        description: 'Build number (must be unique, increment from last)'
        required: true
        type: string
      skip_validation:
        description: 'Skip local validation (not recommended)'
        required: false
        type: boolean
        default: false

jobs:
  build-and-upload:
    runs-on: macos-latest  # GitHub-hosted or self-hosted
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set version numbers
        run: |
          # Update Info.plist or build settings
          /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${{ inputs.version }}" Configuration/Info.plist
          /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${{ inputs.build }}" Configuration/Info.plist

      # Additional steps: certificate import, build, upload
```

**Triggering from GitHub UI:**
1. Navigate to Actions tab → App Store Release workflow
2. Click "Run workflow" dropdown
3. Enter version (1.1.0), build (2), skip_validation (false)
4. Click "Run workflow"

**Triggering from GitHub CLI:**

```bash
gh workflow run appstore-release.yml \
  -f version=1.1.0 \
  -f build=2 \
  -f skip_validation=false
```

**Source:** [GitHub Actions - Triggering a workflow](https://docs.github.com/actions/using-workflows/triggering-a-workflow)

### Pattern 4: Certificate and Provisioning Profile Management in CI

**What:** Securely import App Store distribution certificates and provisioning profiles in GitHub Actions.

**Best practices:**

```yaml
- name: Import App Store certificates
  run: |
    # Create temporary keychain (isolated from system)
    security create-keychain -p "temp-pass" build.keychain
    security default-keychain -s build.keychain
    security unlock-keychain -p "temp-pass" build.keychain
    security set-keychain-settings -t 3600 -u build.keychain

    # Decode and import Apple Distribution certificate
    echo "${{ secrets.APPLE_DISTRIBUTION_P12 }}" | base64 -d > distribution.p12
    security import distribution.p12 \
      -k build.keychain \
      -P "${{ secrets.CERTIFICATE_PASSWORD }}" \
      -A

    # Set partition list for codesign access
    security set-key-partition-list \
      -S apple-tool:,apple:,codesign: \
      -s \
      -k "temp-pass" \
      build.keychain

- name: Install provisioning profile
  run: |
    mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
    echo "${{ secrets.APPSTORE_PROVISIONING_PROFILE }}" | \
      base64 -d > ~/Library/MobileDevice/Provisioning\ Profiles/appstore.provisionprofile

- name: Clean up (always run)
  if: always()
  run: |
    security delete-keychain build.keychain || true
    rm -f distribution.p12
```

**GitHub Secrets required:**
- `APPLE_DISTRIBUTION_P12` = Base64-encoded .p12 certificate file
- `CERTIFICATE_PASSWORD` = Password for .p12 file
- `APPSTORE_PROVISIONING_PROFILE` = Base64-encoded .provisionprofile file

**Encoding secrets:**

```bash
# Encode certificate
base64 -i AppleDistribution.p12 | pbcopy

# Encode provisioning profile
base64 -i AppStore.provisionprofile | pbcopy

# Paste into GitHub Settings → Secrets and variables → Actions
```

**Security notes:**
- Always create temporary keychain (don't modify system keychain)
- Always clean up keychain in post-action (use `if: always()`)
- Never log certificate contents or passwords
- Rotate certificates before expiration (annual renewal)

**Source:** [Installing an Apple certificate on macOS runners](https://docs.github.com/en/actions/deployment/deploying-xcode-applications/installing-an-apple-certificate-on-macos-runners-for-xcode-development)

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| App Store upload retry logic | Custom retry/timeout handling | `xcrun altool` built-in behavior | altool handles network failures, timeouts, and retries automatically |
| JWT token generation for App Store Connect API | Custom JWT signing code | `xcrun notarytool store-credentials` or fastlane | Apple's tooling manages token expiration, signing algorithm (ES256), and header formatting |
| Build processing status polling | Custom polling scripts | App Store Connect email notifications or fastlane pilot | Apple sends email when build finishes processing; fastlane can poll status via API |
| Screenshot dimension validation | Custom image size checks | `sips` built-in macOS tool | sips can resize, validate dimensions, and convert formats reliably |
| Version number incrementation | Manual tracking in files | Xcode build settings (MARKETING_VERSION, CURRENT_PROJECT_VERSION) | Xcode can auto-increment build numbers; git tags can drive version numbers |
| Metadata management | Custom plist/JSON files | App Store Connect UI or fastlane deliver | Metadata has complex validation rules; UI provides immediate feedback; deliver automates updates |

**Key insight:** App Store submission involves intricate validation rules, network protocols, and authentication flows. Apple's official tooling (`xcrun altool`, Transporter, App Store Connect API) handles edge cases that custom solutions will miss (e.g., binary format validation, entitlement verification, bundle ID matching, certificate chain validation).

## Common Pitfalls

### Pitfall 1: Version Number Conflicts (Duplicate Binary Error)

**What goes wrong:** Uploading a build with the same `CFBundleVersion` (build number) as a previous upload results in "ERROR ITMS-90062: This bundle is invalid. The value for key CFBundleVersion must be a unique version."

**Why it happens:** App Store Connect requires each build to have a unique `CFBundleVersion` even if `CFBundleShortVersionString` (marketing version) is the same. Many developers forget to increment build number between uploads.

**How to avoid:**
- **Manual approach:** Increment `CFBundleVersion` in Info.plist before each upload (1, 2, 3, ...)
- **Xcode approach:** Use `CURRENT_PROJECT_VERSION` build setting and increment in Xcode before archiving
- **CI/CD approach:** Use GitHub Actions run number or commit count: `$(git rev-list --count HEAD)`

**Warning signs:**
- altool validation returns ITMS-90062 error
- Transporter shows "Invalid Binary" status
- Upload succeeds but build never appears in App Store Connect

**Prior decision reference:** Phase 13-02 established separate `CFBundleShortVersionString` and `CFBundleVersion` to prevent this exact issue.

### Pitfall 2: Missing or Invalid Provisioning Profile

**What goes wrong:** Build succeeds locally but upload fails with "No suitable application records were found. Verify your bundle identifier is correct."

**Why it happens:** App Store provisioning profiles are tied to specific bundle IDs. If bundle ID in Xcode doesn't exactly match bundle ID in App Store Connect app record, upload fails. Also occurs if provisioning profile expired or was revoked.

**How to avoid:**
1. Create app record in App Store Connect FIRST (before archiving)
2. Generate App Store provisioning profile for exact bundle ID
3. Download and install provisioning profile in Xcode
4. Verify Xcode selected correct provisioning profile in build settings
5. Check provisioning profile expiration date (annual renewal required)

**Verification commands:**

```bash
# Check which provisioning profile was used in archive
codesign -d -v --entitlements - dist/PingScope.xcarchive/Products/Applications/PingScope.app 2>&1 | grep "Provisioning Profile"

# Inspect provisioning profile details
security cms -D -i ~/Library/MobileDevice/Provisioning\ Profiles/appstore.provisionprofile | grep -A5 "application-identifier"

# Expected: com.TEAMID.com.hadm.pingscope
```

**Warning signs:**
- "No suitable application records" error during upload
- Xcode shows "Provisioning profile doesn't match bundle identifier"
- Build archives but fails during export step

### Pitfall 3: Build Processing Stuck or Failed

**What goes wrong:** Build uploads successfully to App Store Connect but shows "Processing" status for hours or shows "Invalid Binary" without explanation.

**Why it happens:**
- Missing required icons in asset catalog (especially 1024x1024 App Store icon)
- Invalid entitlements (requesting capabilities not enabled for bundle ID)
- Info.plist missing required keys (LSApplicationCategoryType, NSHumanReadableCopyright)
- Binary architecture issues (missing arm64 slice on Apple Silicon)

**How to avoid:**
- Run `xcrun altool --validate-app` BEFORE uploading (catches most issues)
- Verify asset catalog completeness: all icon sizes present, no transparency
- Check Info.plist against App Store requirements: category, copyright, version format
- Build for "Any Mac (Apple Silicon, Intel)" destination

**Typical processing time:** 5-30 minutes for valid builds. If stuck >1 hour, likely invalid.

**Debugging steps:**

```bash
# Check email for failure notification from App Store Connect
# Subject: "Your app has one or more issues"

# Validate before uploading to catch issues early
xcrun altool --validate-app \
  -f dist/PingScope.pkg \
  -t macos \
  --apiKey YOUR_KEY_ID \
  --apiIssuer YOUR_ISSUER_ID

# Common validation errors:
# - Missing icons: Ensure 1024x1024 icon without alpha channel
# - Invalid entitlements: Remove entitlements not needed for App Store sandbox
# - Info.plist errors: Check LSApplicationCategoryType, CFBundleShortVersionString format
```

**Warning signs:**
- Upload succeeds but no email confirmation after 30 minutes
- Build shows "Processing" in App Store Connect for >1 hour
- Build status changes to "Invalid Binary" without details

### Pitfall 4: TestFlight Build Not Available to Testers

**What goes wrong:** Build shows "Ready to Submit" in App Store Connect but TestFlight testers see "No builds available to test."

**Why it happens:**
- Build not assigned to tester group
- Export compliance not completed (required for all builds, even internal)
- Beta app information missing (description, feedback email)
- Tester invitation not sent or expired

**How to avoid:**
1. Complete export compliance in App Store Connect (set encryption = NO if not using custom encryption)
2. Add beta app description and feedback email
3. Create internal tester group and add testers
4. Assign build to tester group explicitly
5. Verify testers received email invitation

**TestFlight internal testing workflow:**

```
1. Upload build via altool/Transporter
2. Wait for "Ready to Submit" status (processing complete)
3. In App Store Connect → TestFlight → Internal Testing:
   - Complete export compliance (YES/NO questions)
   - Add beta app description
   - Create tester group (e.g., "Internal Team")
   - Add internal testers (must have App Store Connect accounts)
   - Click "Add Build to Group" → Select processed build
4. Testers install TestFlight app from Mac App Store
5. Testers click email invitation link → "Install" in TestFlight
```

**Warning signs:**
- Testers report "No builds available"
- TestFlight app installed but shows empty state
- Build status = "Ready to Submit" but no testers listed

### Pitfall 5: Accidentally Building Wrong Scheme

**What goes wrong:** Build and upload Developer ID build instead of App Store build, resulting in rejection for "Invalid provisioning profile" or "Missing sandbox entitlement."

**Why it happens:** Xcode defaults to last-used scheme. If Developer ID scheme was used recently, xcodebuild might use it unless explicitly specified. Also occurs in CI/CD if scheme name is misspelled.

**How to avoid:**
- **Always specify scheme explicitly:** `xcodebuild -scheme PingScope-AppStore`
- Create separate workflows/scripts for App Store vs Developer ID
- Add verification step after archive to check entitlements:

```bash
# After archiving, verify sandbox entitlement is present
codesign -d --entitlements - dist/PingScope.xcarchive/Products/Applications/PingScope.app 2>&1 | grep "app-sandbox"

# Expected output: <key>com.apple.security.app-sandbox</key><true/>
# If missing: wrong scheme was used, rebuild
```

- Use CI/CD workflow naming to prevent confusion:
  - `appstore-release.yml` → Always uses PingScope-AppStore scheme
  - `production-release.yml` → Always uses PingScope-DeveloperID scheme

**Warning signs:**
- Upload succeeds but build shows "Invalid Binary"
- Rejection email mentions "App Sandbox not enabled"
- codesign verification shows hardened runtime but no sandbox

### Pitfall 6: Forgetting to Update Metadata Before Submission

**What goes wrong:** Submit build for review but App Review rejects because screenshots show outdated features, description doesn't match functionality, or version number is wrong.

**Why it happens:** Metadata (screenshots, description, version) must be updated in App Store Connect UI separately from binary upload. Easy to forget when focused on build automation.

**How to avoid:**
- Create pre-submission checklist:
  - [ ] Screenshots match current build (capture from TestFlight build)
  - [ ] Description mentions all new features in this version
  - [ ] "What's New" text written for this version
  - [ ] Version number matches uploaded build
  - [ ] Review notes explain any unusual behavior (e.g., dual sandbox modes)
- Consider using fastlane deliver to automate metadata updates
- Test metadata changes in a separate "prepare for review" task before clicking Submit

**Warning signs:**
- Rejection reason: "Screenshots do not reflect current app"
- Rejection reason: "App behavior does not match description"
- Forgot to mention breaking changes in "What's New"

## Code Examples

Verified patterns from official sources.

### Complete altool Validation and Upload

```bash
#!/bin/bash
# Source: Apple Developer Documentation - Upload builds
# URL: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/

set -e

PACKAGE_PATH="dist/PingScope.pkg"
APP_STORE_API_KEY="ABCD123456"
APP_STORE_ISSUER_ID="d1234567-e89b-12d3-a456-426614174000"

echo "=== Validating App Store package ==="
xcrun altool --validate-app \
  -f "$PACKAGE_PATH" \
  -t macos \
  --apiKey "$APP_STORE_API_KEY" \
  --apiIssuer "$APP_STORE_ISSUER_ID" \
  --output-format xml

if [ $? -eq 0 ]; then
  echo "✅ Validation passed"
else
  echo "❌ Validation failed - see errors above"
  exit 1
fi

echo ""
echo "=== Uploading to App Store Connect ==="
xcrun altool --upload-app \
  -f "$PACKAGE_PATH" \
  -t macos \
  --apiKey "$APP_STORE_API_KEY" \
  --apiIssuer "$APP_STORE_ISSUER_ID" \
  --output-format xml

if [ $? -eq 0 ]; then
  echo "✅ Upload complete"
  echo "⏳ Build processing will take 5-30 minutes"
  echo "📧 You'll receive email when processing finishes"
else
  echo "❌ Upload failed - see errors above"
  exit 1
fi
```

**Note:** Starting in 2026, use `-assetFile` instead of `-f`:

```bash
# 2026+ syntax
xcrun altool --validate-app \
  -assetFile "$PACKAGE_PATH" \
  -t macos \
  --apiKey "$APP_STORE_API_KEY" \
  --apiIssuer "$APP_STORE_ISSUER_ID"
```

### GitHub Actions App Store Build Workflow

```yaml
# Source: Adapted from GitHub Docs and defn.io Mac App Store distribution guide
# URL: https://defn.io/2023/10/22/distributing-mac-app-store-apps-with-github-actions/

name: App Store Release

on:
  workflow_dispatch:
    inputs:
      marketing_version:
        description: 'Marketing version (1.1.0)'
        required: true
        type: string
      build_number:
        description: 'Build number (must be unique)'
        required: true
        type: string

env:
  SCHEME_NAME: "PingScope-AppStore"
  ARCHIVE_PATH: "dist/PingScope.xcarchive"
  EXPORT_PATH: "dist/"

jobs:
  build-and-upload:
    runs-on: macos-latest
    timeout-minutes: 60

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Set Xcode version
      run: sudo xcode-select -s /Applications/Xcode.app

    - name: Import App Store certificates
      run: |
        security create-keychain -p "build-pass" build.keychain
        security default-keychain -s build.keychain
        security unlock-keychain -p "build-pass" build.keychain
        security set-keychain-settings -t 3600 -u build.keychain

        echo "${{ secrets.APPLE_DISTRIBUTION_P12 }}" | base64 -d > distribution.p12
        security import distribution.p12 \
          -k build.keychain \
          -P "${{ secrets.CERTIFICATE_PASSWORD }}" \
          -A

        security set-key-partition-list \
          -S apple-tool:,apple:,codesign: \
          -s -k "build-pass" build.keychain

    - name: Install provisioning profile
      run: |
        mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
        echo "${{ secrets.APPSTORE_PROVISIONING_PROFILE }}" | \
          base64 -d > ~/Library/MobileDevice/Provisioning\ Profiles/appstore.provisionprofile

    - name: Update version numbers
      run: |
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${{ inputs.marketing_version }}" Configuration/Info.plist
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${{ inputs.build_number }}" Configuration/Info.plist

    - name: Archive app
      run: |
        xcodebuild archive \
          -project PingScope.xcodeproj \
          -scheme "$SCHEME_NAME" \
          -destination 'generic/platform=macOS' \
          -archivePath "$ARCHIVE_PATH"

    - name: Verify archive entitlements
      run: |
        codesign -d --entitlements - "$ARCHIVE_PATH/Products/Applications/PingScope.app" 2>&1 | grep "app-sandbox"
        if [ $? -ne 0 ]; then
          echo "❌ Sandbox entitlement missing - wrong scheme?"
          exit 1
        fi

    - name: Export for App Store
      run: |
        xcodebuild -exportArchive \
          -archivePath "$ARCHIVE_PATH" \
          -exportOptionsPlist Configuration/ExportOptions-AppStore.plist \
          -exportPath "$EXPORT_PATH"

    - name: Validate package
      run: |
        xcrun altool --validate-app \
          -f "$EXPORT_PATH/PingScope.pkg" \
          -t macos \
          --apiKey "${{ secrets.APP_STORE_CONNECT_KEY_ID }}" \
          --apiIssuer "${{ secrets.APP_STORE_CONNECT_ISSUER_ID }}"

    - name: Upload to App Store Connect
      run: |
        xcrun altool --upload-app \
          -f "$EXPORT_PATH/PingScope.pkg" \
          -t macos \
          --apiKey "${{ secrets.APP_STORE_CONNECT_KEY_ID }}" \
          --apiIssuer "${{ secrets.APP_STORE_CONNECT_ISSUER_ID }}"

    - name: Clean up
      if: always()
      run: |
        security delete-keychain build.keychain || true
        rm -f distribution.p12

    - name: Notify completion
      run: |
        echo "✅ Upload complete"
        echo "Marketing Version: ${{ inputs.marketing_version }}"
        echo "Build Number: ${{ inputs.build_number }}"
        echo "Next steps:"
        echo "1. Wait for email confirming build processing (5-30 min)"
        echo "2. Add build to internal TestFlight group"
        echo "3. Test in sandboxed environment"
        echo "4. Submit for App Review in App Store Connect"
```

### TestFlight Internal Testing Verification Script

```bash
#!/bin/bash
# Verify TestFlight build matches expected behavior
# Run after installing TestFlight build on test device

set -e

APP_PATH="/Applications/PingScope.app"

echo "=== TestFlight Build Verification ==="
echo ""

# 1. Verify app is sandboxed
echo "1. Checking sandbox status..."
SANDBOX_CHECK=$(codesign -d --entitlements - "$APP_PATH" 2>&1 | grep -c "app-sandbox" || true)
if [ "$SANDBOX_CHECK" -gt 0 ]; then
  echo "   ✅ Sandbox enabled"
else
  echo "   ❌ Sandbox NOT enabled - this is incorrect for App Store build"
  exit 1
fi

# 2. Verify network client entitlement
echo "2. Checking network entitlements..."
NETWORK_CHECK=$(codesign -d --entitlements - "$APP_PATH" 2>&1 | grep -c "network.client" || true)
if [ "$NETWORK_CHECK" -gt 0 ]; then
  echo "   ✅ Network client entitlement present"
else
  echo "   ❌ Network client entitlement missing"
  exit 1
fi

# 3. Verify code signing
echo "3. Verifying code signature..."
codesign --verify --verbose "$APP_PATH"
if [ $? -eq 0 ]; then
  echo "   ✅ Code signature valid"
else
  echo "   ❌ Code signature invalid"
  exit 1
fi

# 4. Check Info.plist version
echo "4. Checking version numbers..."
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist")
echo "   Version: $VERSION"
echo "   Build: $BUILD"

echo ""
echo "=== Manual Testing Checklist ==="
echo "Launch the app and verify:"
echo "1. [ ] ICMP option is NOT visible in Settings → Hosts → Method dropdown"
echo "2. [ ] TCP ping to port 80 works (e.g., google.com:80)"
echo "3. [ ] UDP ping to port 53 works (e.g., 8.8.8.8:53)"
echo "4. [ ] Menu bar shows latency updates"
echo "5. [ ] No crashes during 5-minute monitoring session"
echo "6. [ ] Console.app shows SandboxDetector log with sandbox=true"
echo ""
echo "If all checks pass, approve for App Review submission."
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Application Loader GUI | Transporter app + xcrun altool CLI | 2019 (Xcode 11) | Application Loader deprecated; Transporter offers modern GUI; altool enables CI/CD automation |
| xcrun altool for notarization | xcrun notarytool | 2021 (Xcode 13) | notarytool is faster (2-5 min vs 15-60 min), has --wait flag, and better error messages; altool notarization deprecated fall 2023 |
| Username/password authentication | App Store Connect API keys (JWT) | 2018 (API launch) | API keys bypass 2FA, work reliably in CI/CD, and are Apple's recommended approach for automation |
| Manual metadata updates in iTunes Connect | fastlane deliver or App Store Connect API | 2015 (fastlane) / 2018 (API) | Automation reduces errors, enables versioned metadata, and supports multi-language updates |
| Single "Release" scheme | Separate App Store and Developer ID schemes | Ongoing best practice | Prevents accidental wrong-distribution uploads; enables dual distribution strategy |

**Deprecated/outdated:**
- **Application Loader** (Xcode 10 and earlier): Removed in Xcode 11; replaced by Transporter
- **altool for notarization** (deprecated fall 2023): Use notarytool instead for Developer ID notarization
- **altool `-f` flag** (deprecating 2026): Use `-assetFile` instead
- **Aspera/Signiant in old Transporter** (2026): Requires newer Transporter version; HTTPS protocol unaffected
- **iTunes Connect** (rebranded 2018): Now called App Store Connect

**Current state (2026):**
- Xcode 26+ mandatory for App Store uploads (enforced April 28, 2026)
- macOS 26 SDK required (bundled with Xcode 26)
- App Store Connect API v1 stable and recommended
- TestFlight supports macOS since Xcode 13 (2021)
- notarytool is the only supported notarization tool (altool deprecated for notarization)

## Open Questions

### 1. TestFlight External Testing Scope

**What we know:** TestFlight supports up to 10,000 external testers; first build requires App Review.

**What's unclear:** Whether external TestFlight testing provides value for PingScope v1.1 launch or should be deferred to v1.2 for broader beta feedback.

**Recommendation:** Defer external TestFlight to v1.2 (post-launch). Internal testing with 5-10 trusted testers sufficient for first submission. External testing adds review time and complexity without significant benefit for network utility app with clear functionality.

**Confidence:** MEDIUM - Based on common practice for utility apps, but specific to PingScope's risk profile.

### 2. Fastlane Integration Timing

**What we know:** fastlane deliver automates metadata updates; fastlane pilot automates TestFlight tester management.

**What's unclear:** Whether to integrate fastlane in Phase 16 (first submission) or defer to future releases after manual workflow is proven.

**Recommendation:** Manual workflow first, fastlane later. Rationale:
- First submission benefits from manual steps (learning App Store Connect UI, understanding validation errors)
- fastlane adds complexity and debugging overhead
- Manual documentation is more valuable than premature automation
- Consider fastlane in v1.2+ when updating metadata frequently

**Confidence:** HIGH - Based on common practice of manual-first, automate-later approach.

### 3. GitHub-Hosted vs Self-Hosted Runner

**What we know:** Current `production-release.yml` uses `runs-on: self-hosted` for Developer ID builds.

**What's unclear:** Whether App Store builds should use GitHub-hosted macOS runners (simpler, no maintenance) or self-hosted runners (consistent with existing workflow).

**Recommendation:** Use GitHub-hosted `macos-latest` for App Store builds. Rationale:
- GitHub-hosted runners include Xcode 26 and clean environment
- App Store builds happen infrequently (monthly or less)
- Self-hosted runners require macOS 26 upgrade and maintenance
- Separate workflows (Developer ID = self-hosted, App Store = GitHub-hosted) is acceptable

**Confidence:** MEDIUM - Depends on self-hosted runner availability and maintenance preferences.

### 4. Build Number Automation Strategy

**What we know:** `CFBundleVersion` must be unique for each upload; can be integer or semantic version.

**What's unclear:** Best automation strategy for PingScope:
- Option A: Manual input in workflow_dispatch (user specifies build number)
- Option B: GitHub Actions run number (auto-incrementing)
- Option C: Git commit count (deterministic but may conflict with previous uploads)

**Recommendation:** Manual input (Option A) for Phase 16 first submission. Document expected format (integers starting at 1, increment for each upload). Revisit automation in future phases after establishing pattern.

**Confidence:** MEDIUM - Manual approach is safest for first submission; automation patterns emerge from experience.

## Sources

### Primary (HIGH confidence)

- [Upload builds - App Store Connect Help](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/) - Official upload methods and requirements
- [TestFlight overview - App Store Connect Help](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/) - Official TestFlight workflow for macOS
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) - Official review guidelines (verified 2026-02-16)
- [Installing an Apple certificate on macOS runners - GitHub Docs](https://docs.github.com/en/actions/deployment/deploying-xcode-applications/installing-an-apple-certificate-on-macos-runners-for-xcode-development) - Official GitHub Actions certificate management
- [Triggering a workflow - GitHub Docs](https://docs.github.com/actions/using-workflows/triggering-a-workflow) - Official workflow_dispatch documentation
- [Generating Tokens for API Requests - Apple Developer Documentation](https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests) - Official JWT token generation
- [CFBundleShortVersionString - Apple Developer Documentation](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring) - Official version format
- [CFBundleVersion - Apple Developer Documentation](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion) - Official build number format

### Secondary (MEDIUM confidence)

- [Distributing Mac Apps With GitHub Actions - defn.io](https://defn.io/2023/10/22/distributing-mac-app-store-apps-with-github-actions/) - Practical App Store automation guide (2023)
- [Live App Store and TestFlight review times - Runway](https://www.runway.team/appreviewtimes) - Real-time review time data
- [App Store Screenshot Sizes & Requirements 2026 - aso.dev](https://aso.dev/app-store-connect/screenshots/) - Screenshot specifications reference
- [fastlane deliver documentation](https://docs.fastlane.tools/actions/deliver/) - Metadata automation documentation
- [fastlane pilot documentation](https://docs.fastlane.tools/actions/pilot/) - TestFlight automation documentation
- [Versioning for iOS & macOS - MacPaw](https://macpaw.com/news/versioning-for-ios-and-macos) - Version numbering best practices

### Tertiary (LOW confidence - for awareness)

- Medium articles on App Store submission (multiple authors, various dates) - General workflow guidance
- GitHub discussions on altool deprecation - Community-reported issues
- Developer forum posts on build processing issues - Anecdotal evidence

## Metadata

**Confidence breakdown:**
- Upload workflow: HIGH - Official Apple documentation verified
- TestFlight process: HIGH - Official Apple documentation verified
- GitHub Actions patterns: HIGH - Official GitHub documentation + verified community guides
- Review timeline: MEDIUM - Real-time data from Runway, not official Apple SLA
- fastlane integration: MEDIUM - Official docs exist but PingScope-specific benefits unclear

**Research date:** 2026-02-16
**Valid until:** 2026-04-28 (Xcode 26 mandate enforcement date - revalidate requirements after)

**Research notes:**
- Xcode 26 requirement is firm deadline (April 28, 2026)
- altool `-assetFile` migration in 2026 may affect existing scripts
- TestFlight macOS support stable since Xcode 13 (no recent changes)
- App Review Guidelines reviewed but no macOS-specific network tool restrictions found
- GitHub Actions self-hosted vs hosted runner decision deferred to planning phase
