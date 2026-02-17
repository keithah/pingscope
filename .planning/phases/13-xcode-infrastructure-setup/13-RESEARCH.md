# Phase 13: Xcode Infrastructure Setup - Research

**Researched:** 2026-02-16
**Domain:** Xcode project infrastructure for dual App Store/Developer ID distribution
**Confidence:** HIGH

## Summary

Phase 13 establishes the Xcode project wrapper that enables App Store distribution while preserving the existing Developer ID build workflow. The key technical challenge is creating a hybrid SPM+Xcode architecture where Package.swift remains the source of truth for code, while an Xcode project provides App Store-specific capabilities (asset catalogs, entitlements, provisioning profiles, and automated version management).

PingScope already has most prerequisites in place: an asset catalog with all required icon sizes (including 1024x1024 for App Store), existing entitlements file for sandboxing, and runtime sandbox detection. The infrastructure phase focuses on wrapping these existing assets in an Xcode project structure that supports two distinct build schemes for two distribution channels.

**Primary recommendation:** Use Xcode's "Add Local Package" feature to reference Package.swift, create separate entitlement files for each distribution method, and establish build schemes that differentiate App Store (sandboxed) from Developer ID (hardened runtime only) without duplicating source code.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| INFRA-01 | Xcode project wrapper created referencing Package.swift as local dependency | Local SPM package integration via File → Add Package Dependencies → Add Local (Xcode 26 workflow) |
| INFRA-02 | Asset catalog created with 1024x1024 opaque PNG app icon | Already exists: Assets.xcassets/AppIcon.appiconset/ with icon_512x512@2x.png (1024x1024 RGBA) - requires verification of opacity |
| INFRA-03 | AppStore build scheme configured with App Store distribution certificate | Build schemes pattern: separate schemes select different entitlements + signing identities |
| INFRA-04 | DeveloperID build scheme configured with Developer ID certificate | Existing workflow preserved: Developer ID Application certificate already in GitHub secrets |
| INFRA-05 | PingScope-AppStore.entitlements file created with sandbox enabled | Pattern: com.apple.security.app-sandbox=true + com.apple.security.network.client=true (existing entitlements-appstore.plist as template) |
| INFRA-06 | PingScope-DeveloperID.entitlements file created with hardened runtime only | Pattern: com.apple.security.app-sandbox=false + hardened runtime exceptions if needed |
| INFRA-07 | Info.plist migrated to Xcode management with version automation | Move from static root Info.plist to Xcode build settings using MARKETING_VERSION and CURRENT_PROJECT_VERSION |
| INFRA-08 | Both build schemes produce functional apps (sandbox detection works) | Verification via SandboxDetector.isRunningInSandbox - runtime feature gating already implemented |
</phase_requirements>

## Standard Stack

### Core Infrastructure

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Xcode | 26+ | IDE and build system | Mandatory starting April 28, 2026 for App Store submissions |
| macOS SDK | 15+ (Sequoia) | Platform SDK | Required by Xcode 26 mandate |
| Swift Package Manager | 5.9+ | Source organization | Already in use, remains source of truth |
| Asset Catalog (.xcassets) | N/A | Icon and resource management | Mac App Store requirement for app icons |

**Critical constraint:** Xcode 26+ with macOS SDK 15+ is mandatory for App Store submissions starting April 28, 2026. This is an official Apple requirement, not a recommendation.

### Build Components

| Component | Purpose | When to Use | Source |
|-----------|---------|-------------|--------|
| .xcodeproj wrapper | App Store distribution capability | Always for App Store builds | File → New → Project → macOS App |
| Build Schemes | Differentiate distribution channels | Separate AppStore vs DeveloperID | Product → Scheme → Manage Schemes |
| Entitlement files (.entitlements) | Security capabilities per distribution | One per distribution channel | Signing & Capabilities tab |
| Provisioning Profiles | App Store bundle authorization | App Store builds only | Apple Developer portal |

**Installation:**

Xcode project creation is GUI-driven:
```bash
# 1. Open Xcode 26+
open -a Xcode

# 2. File → New → Project → macOS → App
# 3. Save as "PingScope.xcodeproj" in repository root
# 4. File → Add Package Dependencies → Add Local
# 5. Select repository root (where Package.swift lives)
```

Asset catalog already exists at `Assets.xcassets/` with complete icon set.

## Architecture Patterns

### Recommended Project Structure

```
pingscope/
├── Package.swift                          # [UNCHANGED] SPM source of truth
├── Sources/PingScope/                     # [UNCHANGED] All app code
├── Tests/                                 # [UNCHANGED] Test code
├── PingScope.xcodeproj/                   # [NEW] Xcode wrapper
│   ├── project.pbxproj
│   └── xcshareddata/xcschemes/
│       ├── AppStore.xcscheme              # App Store build
│       └── DeveloperID.xcscheme           # Developer ID build
├── Configuration/                         # [NEW] Xcode-specific files
│   ├── PingScope-AppStore.entitlements
│   ├── PingScope-DeveloperID.entitlements
│   └── Info.plist                         # Migrated from root
├── Assets.xcassets/                       # [EXISTING] Asset catalog
│   └── AppIcon.appiconset/                # Complete icon set
├── scripts/build-app-bundle.sh            # [PRESERVED] Developer ID
├── .github/workflows/
│   └── production-release.yml             # [PRESERVED] Developer ID
└── .gitignore                             # [MODIFIED] Add Xcode artifacts
```

**Key principle:** Source code stays in SPM structure. Xcode project references it via local package dependency.

### Pattern 1: Xcode Project Wrapping Local SPM Package

**What:** Xcode project references root-level Package.swift as local package dependency, allowing Xcode to build SPM code without duplicating sources.

**When to use:** When adding App Store distribution to existing SPM executable projects.

**Implementation:**
```
1. Create Xcode project: File → New → Project → macOS → App
2. Delete auto-generated source files (keep project only)
3. Add local package: File → Add Package Dependencies → Add Local
4. Select repository root (where Package.swift lives)
5. Xcode discovers executable target automatically
6. Link executable to app target in Build Phases
```

**Verified in:** Xcode 26 supports this workflow explicitly. Prior versions (15-16) also support it.

### Pattern 2: Build Scheme Differentiation

**What:** Use Xcode build schemes to configure different entitlements, signing, and capabilities for the same codebase.

**Configuration:**

```
AppStore Scheme:
├── Entitlements: Configuration/PingScope-AppStore.entitlements
├── Code Signing: Apple Distribution (App Store certificate)
├── Provisioning Profile: Mac App Store profile
└── Export destination: App Store Connect

DeveloperID Scheme:
├── Entitlements: Configuration/PingScope-DeveloperID.entitlements
├── Code Signing: Developer ID Application certificate
├── Provisioning Profile: None (direct distribution)
└── Export destination: DMG/PKG for GitHub releases
```

**Warning:** Risk of building wrong scheme accidentally. Document which scheme for which purpose. Consider CI/CD automation to enforce correct scheme usage.

### Pattern 3: Info.plist Version Automation

**What:** Replace static Info.plist with Xcode-managed version using build settings variables.

**Current state:** Static Info.plist in root with hardcoded version "1.0.1"

**Migration approach:**

1. Move Info.plist to `Configuration/Info.plist`
2. Set Xcode build settings:
   - `MARKETING_VERSION` = "1.1.0" (user-facing version)
   - `CURRENT_PROJECT_VERSION` = "1" (build number, increment on each upload)
3. Update Info.plist:
   - `CFBundleShortVersionString` → `$(MARKETING_VERSION)`
   - `CFBundleVersion` → `$(CURRENT_PROJECT_VERSION)`
4. For SPM builds: Read version from git tags or environment variable

**Automation options:**
- **agvtool:** Apple's official version management tool (requires Apple Generic versioning system)
- **Build settings:** Manual version management via Xcode UI
- **Pre-build script:** Auto-increment CFBundleVersion using date/time or git commit count

**Recommended for Phase 13:** Manual build settings approach. Automation can be added in Phase 16 (CI/CD).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| App icon generation | Custom icon resizing scripts | Asset Catalog in Xcode | Automatic generation, App Store requirement |
| Entitlements management | Shell scripts modifying plists | Xcode Signing & Capabilities UI | Validation, provisioning profile sync |
| Code signing configuration | Manual codesign commands in CI | Xcode Archive → Export workflow | Handles provisioning, entitlements, notarization prep |
| Version number management | Manual Info.plist editing | Xcode build settings (MARKETING_VERSION) | Consistency, automation-friendly |
| .app bundle creation for App Store | Manual directory assembly (build-app-bundle.sh) | Xcode Archive | Proper bundle structure, validation |

**Critical finding:** For App Store distribution, manual .app assembly (current scripts/build-app-bundle.sh approach) is insufficient. App Store requires Xcode-generated bundles with proper code signing infrastructure and asset catalog integration. Developer ID workflow can continue using manual assembly.

## Common Pitfalls

### Pitfall 1: Asset Catalog Icon Contains Alpha Channel

**What goes wrong:** Upload to App Store Connect fails with "Asset validation failed - icon contains transparency"

**Why it happens:** The existing icon_512x512@2x.png (1024x1024) is RGBA format. App Store requires opaque RGB PNG with no alpha channel.

**How to avoid:**
1. Verify icon opacity: `sips -g hasAlpha Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png`
2. If alpha channel exists, remove it:
   ```bash
   sips -s format png --setProperty formatOptions best \
     --deleteColorManagementProperties \
     Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png
   ```
3. Re-verify: Should show "hasAlpha: no"

**Warning signs:**
- `file` command shows "RGBA" instead of "RGB"
- Asset validation shows icon errors
- App Store Connect processing fails after successful upload

**Phase to address:** Phase 13 (this phase) - verify and fix icon during asset catalog integration.

### Pitfall 2: Entitlement File Extension Mismatch

**What goes wrong:** Xcode doesn't recognize entitlements file, or build uses wrong entitlements.

**Why it happens:** Existing file is `entitlements-appstore.plist` (plist extension). Xcode expects `.entitlements` extension for entitlement files.

**How to avoid:**
- Use `.entitlements` extension: `PingScope-AppStore.entitlements`
- Set in Xcode: Target → Build Settings → Code Signing Entitlements
- Verify: `codesign -d --entitlements - /path/to/PingScope.app` shows expected entitlements

**Warning signs:**
- Xcode shows entitlements file in gray (not recognized)
- Build succeeds but app lacks expected capabilities
- Sandbox detection returns wrong result

**Phase to address:** Phase 13 - create properly named entitlement files during project setup.

### Pitfall 3: Info.plist Keys Missing for App Store

**What goes wrong:** App Store Connect validation fails with "Missing required Info.plist key"

**Why it happens:** Current Info.plist has most keys, but App Store requires additional validation:
- `LSApplicationCategoryType` - PRESENT (public.app-category.utilities)
- `LSMinimumSystemVersion` - PRESENT ("13.0")
- `CFBundleShortVersionString` - PRESENT ("1.0.1")
- `CFBundleVersion` - PRESENT ("1.0.1")

**Critical issue:** CFBundleVersion and CFBundleShortVersionString are identical. App Store requires CFBundleVersion to increment on each upload, even for same CFBundleShortVersionString.

**How to avoid:**
1. Separate version (1.1.0) from build number (1, 2, 3...)
2. After rejection, increment build number only
3. Document: "Version 1.1.0, Build 5" means 5th attempt at version 1.1.0

**Warning signs:**
- Second upload fails with "duplicate binary"
- Confusion about which number to increment after rejection

**Phase to address:** Phase 13 - establish version numbering strategy in Info.plist migration.

### Pitfall 4: Build Scheme Selection Error

**What goes wrong:** Developer builds App Store scheme and uploads to GitHub releases, or builds Developer ID scheme and uploads to App Store. Scheme mismatch causes signing errors or runtime failures.

**Why it happens:** Xcode defaults to first scheme alphabetically. "AppStore" comes before "DeveloperID", making it easy to accidentally select wrong scheme.

**How to avoid:**
- Name schemes clearly: `PingScope-AppStore` and `PingScope-DeveloperID` (product name prefix)
- Set DeveloperID as default scheme (Product → Scheme → Manage Schemes → check "Show" for DeveloperID)
- Add pre-build script to verify scheme matches build type
- In CI/CD, explicitly specify scheme: `xcodebuild -scheme PingScope-AppStore`

**Warning signs:**
- Sandbox detection shows unexpected result
- Signing identity mismatch errors
- Archive exports to wrong destination

**Phase to address:** Phase 13 - configure schemes with clear naming and defaults during project creation.

### Pitfall 5: Local Package Dependency Not Found

**What goes wrong:** Xcode project doesn't see Package.swift, or shows "missing package product"

**Why it happens:** Xcode 26 beta had issues finding module dependencies for local packages on macOS. May be resolved in stable release.

**How to avoid:**
1. Verify Package.swift is at repository root (not in subfolder)
2. Use "Add Local" not "Add Package" (different workflows)
3. Clean build folder: Product → Clean Build Folder
4. Reset package cache: File → Packages → Reset Package Caches
5. If persistent, check Swift tools version: `swift-tools-version: 5.9` (not 6.2 unless using Swift 6 features)

**Warning signs:**
- Xcode shows package in File Navigator but build fails
- "No such module 'PingScope'" error
- Package appears in gray in Dependencies section

**Phase to address:** Phase 13 - verify local package integration during Xcode project creation.

## Code Examples

### Entitlements: App Store (Sandbox Enabled)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Required for App Store -->
    <key>com.apple.security.app-sandbox</key>
    <true/>

    <!-- Network access for ping operations -->
    <key>com.apple.security.network.client</key>
    <true/>

    <!-- File access (if export feature added) -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
```

**Source:** Existing entitlements-appstore.plist, verified against [App Sandbox documentation](https://developer.apple.com/documentation/security/app_sandbox_entitlements)

### Entitlements: Developer ID (Hardened Runtime Only)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Hardened runtime enabled, sandbox disabled -->
    <key>com.apple.security.app-sandbox</key>
    <false/>

    <!-- Hardened runtime exceptions (if needed) -->
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <false/>

    <key>com.apple.security.cs.allow-dyld-environment-variables</key>
    <false/>
</dict>
</plist>
```

**Source:** [Hardened Runtime documentation](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime), [Developer ID signing](https://developer.apple.com/developer-id/)

**Note:** Developer ID builds for notarization require hardened runtime but NOT sandbox. This enables ICMP functionality via raw sockets.

### Info.plist with Version Automation

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Automated version management -->
    <key>CFBundleShortVersionString</key>
    <string>$(MARKETING_VERSION)</string>

    <key>CFBundleVersion</key>
    <string>$(CURRENT_PROJECT_VERSION)</string>

    <!-- Existing keys preserved -->
    <key>CFBundleExecutable</key>
    <string>PingScope</string>

    <key>CFBundleIdentifier</key>
    <string>com.hadm.pingscope</string>

    <key>CFBundleIconFile</key>
    <string>AppIcon</string>

    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>

    <key>LSUIElement</key>
    <true/>

    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>

    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2024 Keith Herrington. All rights reserved.</string>
</dict>
</plist>
```

**Set in Xcode Build Settings:**
- MARKETING_VERSION = 1.1.0
- CURRENT_PROJECT_VERSION = 1

**Source:** [Xcode Automatic Bundle Versioning](https://medium.com/ios-os-x-development/xcode-automatic-bundle-versioning-1179b08a9b37), [Apple's agvtool documentation](https://developer.apple.com/library/archive/qa/qa1827/_index.html)

### Verification Script: Check Built Archive

```bash
#!/usr/bin/env bash
# Verify archived app has correct entitlements and assets

APP_PATH="$1"

echo "=== Verifying App Bundle ==="
echo "Path: $APP_PATH"

# Check entitlements
echo -e "\n=== Entitlements ==="
codesign -d --entitlements - "$APP_PATH"

# Check sandbox status
if codesign -d --entitlements - "$APP_PATH" 2>&1 | grep -q "com.apple.security.app-sandbox.*true"; then
    echo "✅ Sandbox: ENABLED (App Store build)"
else
    echo "✅ Sandbox: DISABLED (Developer ID build)"
fi

# Check icon
echo -e "\n=== Icon Assets ==="
if [ -f "$APP_PATH/Contents/Resources/AppIcon.icns" ]; then
    echo "✅ AppIcon.icns present"
else
    echo "❌ AppIcon.icns missing"
fi

# Check privacy manifest
echo -e "\n=== Privacy Manifest ==="
if [ -f "$APP_PATH/Contents/Resources/PrivacyInfo.xcprivacy" ]; then
    echo "✅ PrivacyInfo.xcprivacy present"
else
    echo "⚠️  PrivacyInfo.xcprivacy missing (required for App Store)"
fi

# Check Info.plist version
echo -e "\n=== Version Info ==="
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP_PATH/Contents/Info.plist")
echo "Version: $VERSION"
echo "Build: $BUILD"

if [ "$VERSION" == "$BUILD" ]; then
    echo "⚠️  Version and build are identical - increment build number for resubmission"
fi
```

**Usage:**
```bash
# After Xcode Archive
./verify-archive.sh ~/Library/Developer/Xcode/Archives/*/PingScope.xcarchive/Products/Applications/PingScope.app
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Pure SPM for App Store | Xcode wrapper + SPM | April 2026 Xcode 26 mandate | App Store requires Xcode-built bundles |
| Manual Info.plist editing | Build settings variables (MARKETING_VERSION) | Xcode 13+ (2021) | Automated version management |
| Single entitlements file | Separate per distribution | App Sandbox requirement (2012) | Explicit security posture per channel |
| Manual asset creation (.icns) | Asset Catalog (.xcassets) | macOS 11+ (2020) | App Store requirement for icons |
| Xcode 15 submission | Xcode 26 minimum | April 28, 2026 | Mandatory for all submissions |

**Deprecated/outdated:**

- **Pure SPM distribution to App Store:** No longer possible. SPM cannot produce App Store-compliant bundles with proper asset catalogs and provisioning.
- **Manual .icns files for App Store:** Asset catalogs are mandatory for macOS 11+ App Store submissions.
- **Generic entitlements for all builds:** App Store now requires explicit sandbox enablement, Developer ID can use hardened runtime only.
- **Xcode versions older than 26:** Starting April 28, 2026, Apple rejects all submissions not built with Xcode 26+ and corresponding SDKs.

## Open Questions

1. **Icon alpha channel verification**
   - What we know: icon_512x512@2x.png exists at 1024x1024, file shows RGBA format
   - What's unclear: Does it contain actual transparency (alpha < 255) or just RGBA container?
   - Recommendation: Run `sips -g hasAlpha` during Phase 13 setup, convert to RGB if needed

2. **Build number automation strategy**
   - What we know: Manual increment is safest, automation options exist (agvtool, git commit count)
   - What's unclear: User preference for manual vs automated, CI/CD integration requirements
   - Recommendation: Start with manual CURRENT_PROJECT_VERSION, automate in Phase 16 if desired

3. **Xcode project location**
   - What we know: Project should reference Package.swift as local dependency
   - What's unclear: Should .xcodeproj be in root alongside Package.swift, or in separate folder?
   - Recommendation: Root location (alongside Package.swift) matches standard Xcode+SPM integration pattern

4. **Developer ID workflow preservation**
   - What we know: Existing scripts/build-app-bundle.sh works for Developer ID
   - What's unclear: Should Developer ID builds switch to Xcode Archive, or keep current SPM workflow?
   - Recommendation: Keep current SPM workflow for Developer ID (DeveloperID scheme as backup, not primary)

5. **Asset catalog vs .icns for Developer ID**
   - What we know: Asset catalog required for App Store, .icns works for Developer ID
   - What's unclear: Should both builds use asset catalog, or keep .icns for Developer ID?
   - Recommendation: Asset catalog for both (single source of truth), update build-app-bundle.sh to copy from .xcassets if needed

## Sources

### Primary (HIGH confidence)

- [Xcode 26 Local SPM Integration](https://medium.com/@guycohendev/local-spm-part-2-mastering-modularization-with-swift-package-manager-xcode-15-16-d5a11ddd166c) - Local package workflow
- [Adding package dependencies to your app | Apple Developer Documentation](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app) - Official Apple guidance
- [Upcoming Requirements - Apple Developer](https://developer.apple.com/news/upcoming-requirements/) - April 28, 2026 Xcode 26 mandate
- [Entitlements | Apple Developer Documentation](https://developer.apple.com/documentation/bundleresources/entitlements) - Official entitlements reference
- [App Sandbox | Apple Developer Documentation](https://developer.apple.com/documentation/security/app_sandbox_entitlements) - Sandbox entitlements
- [Configuring the hardened runtime | Apple Developer Documentation](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime) - Hardened runtime setup
- [Signing Mac Software with Developer ID - Apple Developer](https://developer.apple.com/developer-id/) - Developer ID signing
- [Configuring your app icon | Apple Developer Documentation](https://developer.apple.com/documentation/xcode/configuring-your-app-icon) - Asset catalog icons

### Secondary (MEDIUM confidence)

- [Xcode Automatic Bundle Versioning](https://medium.com/ios-os-x-development/xcode-automatic-bundle-versioning-1179b08a9b37) - Version automation patterns
- [Technical Q&A QA1827: Automating Version and Build Numbers Using agvtool](https://developer.apple.com/library/archive/qa/qa1827/_index.html) - Apple's agvtool documentation
- [Hardened Runtime and Sandboxing](https://lapcatsoftware.com/articles/hardened-runtime-sandboxing.html) - Difference between hardened runtime and sandbox
- [How to add a local Swift Package in Xcode](https://www.delasign.com/blog/xcode-swift-package-manager-local/) - Local package integration
- [A 1024 x 1024 pixel app icon for App Store | Apple Developer Forums](https://developer.apple.com/forums/thread/654407) - Icon requirements discussion
- [Xcode 26: Unable to find module dependency - Swift Forums](https://forums.swift.org/t/xcode-26-unable-to-find-module-dependency/80516) - Known Xcode 26 beta issue

### Tertiary (LOW confidence - requires validation)

- [Best practice for setting CFBundleVersion automatically - Apple Developer Forums](https://developer.apple.com/forums/thread/4590) - Community version automation approaches
- [App icon guide 2026 | MobileAction](https://www.mobileaction.co/guide/app-icon-guide/) - Multi-platform icon requirements

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Official Apple requirements, Xcode 26 mandate verified
- Architecture patterns: HIGH - Local SPM integration documented by Apple and recent articles
- Entitlements configuration: HIGH - Official Apple documentation, existing entitlements-appstore.plist as reference
- Asset catalog requirements: HIGH - Official Apple documentation, verified via existing Assets.xcassets
- Version automation: MEDIUM - Multiple approaches exist, user preference needed
- Pitfalls: MEDIUM-HIGH - Based on official docs (icon requirements, entitlements) and community experience (scheme confusion)

**Research date:** 2026-02-16
**Valid until:** 2026-03-16 (30 days - stable domain with official Apple requirements)

**Prerequisites verified:**
- ✅ Asset catalog exists with complete icon set
- ✅ Entitlements template exists (entitlements-appstore.plist)
- ✅ Info.plist exists with required keys
- ✅ Privacy manifest exists (PrivacyInfo.xcprivacy)
- ✅ Sandbox detection implemented (SandboxDetector)
- ✅ Developer ID workflow functional (production-release.yml)
- ⚠️ Icon alpha channel status unknown (requires verification)
- ⚠️ Xcode project does not exist (this phase creates it)
