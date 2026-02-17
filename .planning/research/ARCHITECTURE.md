# Architecture Research: App Store Distribution Integration

**Domain:** macOS App Store distribution for existing SPM-based menu bar app
**Researched:** 2026-02-16
**Confidence:** MEDIUM-HIGH

## Executive Summary

Adding App Store distribution to an existing SPM-only architecture requires a **hybrid SPM + Xcode project** approach. The SPM Package.swift remains the source of truth for code organization and dependencies, while a wrapper Xcode project provides App Store-specific capabilities (entitlements, sandboxing, provisioning profiles). Both Developer ID and App Store builds share the same codebase, using build schemes and entitlement files to differentiate distribution channels.

**Key architectural insight:** Xcode projects can reference local SPM packages, allowing the Swift Package to remain independent while the Xcode project handles platform-specific build configurations and code signing requirements that Apple's App Store mandates.

## Current Architecture (Developer ID Only)

### System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                   GitHub Actions (CI)                        │
│  ┌────────────┐   ┌────────────┐   ┌──────────────┐        │
│  │ swift build│ → │ manual .app│ → │ codesign +   │        │
│  │ -c release │   │ assembly   │   │ notarization │        │
│  └────────────┘   └────────────┘   └──────────────┘        │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                   Source Organization                        │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Package.swift (SPM Definition)                      │   │
│  │    • Executable target: PingScope                    │   │
│  │    • Test target: PingScopeTests                     │   │
│  │    • Resources: AppIcon.icns, PrivacyInfo.xcprivacy  │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Sources/PingScope/ (MVVM Structure)                 │   │
│  │    ├── App/           - App lifecycle, delegates     │   │
│  │    ├── Services/      - Business logic               │   │
│  │    ├── ViewModels/    - State management             │   │
│  │    ├── Views/         - SwiftUI components           │   │
│  │    ├── MenuBar/       - Menu bar coordination        │   │
│  │    ├── Models/        - Data types                   │   │
│  │    ├── Utilities/     - Helpers (ICMPPacket)         │   │
│  │    └── Resources/     - Assets, Privacy manifest     │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                   Build Artifacts                            │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  PingScope.app (manually assembled)                  │   │
│  │    ├── Contents/MacOS/PingScope (SPM binary)         │   │
│  │    ├── Contents/Info.plist (static file)             │   │
│  │    └── Contents/Resources/ (icns, privacy, bundles)  │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  Signed with: Developer ID Application certificate          │
│  Notarized with: notarytool                                  │
│  Distributed via: DMG + PKG on GitHub Releases               │
└─────────────────────────────────────────────────────────────┘
```

### Key Characteristics

- **Pure SPM:** No Xcode project file exists
- **Manual bundle creation:** `scripts/build-app-bundle.sh` assembles `.app` structure
- **Static Info.plist:** Version management requires manual editing
- **No entitlements:** Developer ID with hardened runtime, no sandbox
- **CI-driven signing:** GitHub Actions imports certificates, signs, notarizes
- **Runtime feature detection:** `SandboxDetector.isRunningInSandbox` gates ICMP availability

## Target Architecture (Dual Distribution)

### System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                   Source of Truth (Unchanged)                │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Package.swift                                        │   │
│  │    • Executable target: PingScope                    │   │
│  │    • Test target: PingScopeTests                     │   │
│  │    • Resources: AppIcon.icns, PrivacyInfo.xcprivacy  │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Sources/PingScope/ (MVVM - No Changes)              │   │
│  │    All existing code remains in SPM package          │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            ↑ (local path dependency)
┌─────────────────────────────────────────────────────────────┐
│            NEW: Xcode Wrapper Project                        │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  PingScope.xcodeproj                                  │   │
│  │    ├── Target: PingScope (App)                       │   │
│  │    │   ├── Depends on: local SPM package             │   │
│  │    │   ├── Build Schemes:                            │   │
│  │    │   │   • AppStore (sandbox enabled)              │   │
│  │    │   │   • DeveloperID (sandbox disabled)          │   │
│  │    │   └── Capabilities: Configured via Xcode UI     │   │
│  │    └── Target: PingScopeTests (Optional)             │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  NEW: Entitlement Files                               │   │
│  │    ├── PingScope-AppStore.entitlements               │   │
│  │    │   • com.apple.security.app-sandbox = true       │   │
│  │    │   • com.apple.security.network.client = true    │   │
│  │    │   • (no ICMP-related entitlements)              │   │
│  │    │                                                  │   │
│  │    └── PingScope-DeveloperID.entitlements            │   │
│  │        • com.apple.security.app-sandbox = false      │   │
│  │        • Hardened runtime options                    │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Info.plist (Xcode-managed)                           │   │
│  │    • Version numbers: Pulled from build settings     │   │
│  │    • Bundle ID: Same for both distributions          │   │
│  │    • All existing keys preserved                     │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                   Build Workflows                            │
│  ┌───────────────────────────┐  ┌──────────────────────┐   │
│  │ Developer ID (Existing)   │  │ App Store (New)      │   │
│  ├───────────────────────────┤  ├──────────────────────┤   │
│  │ 1. swift build -c release │  │ 1. xcodebuild        │   │
│  │ 2. Manual .app assembly   │  │    -scheme AppStore  │   │
│  │ 3. Sign with Dev ID cert  │  │ 2. Archive           │   │
│  │ 4. Notarize               │  │ 3. Export for Store  │   │
│  │ 5. Create DMG/PKG         │  │ 4. Upload via Xcode  │   │
│  │ 6. GitHub Release         │  │    or transporter    │   │
│  └───────────────────────────┘  └──────────────────────┘   │
│         (scripts/build-app-bundle.sh + CI)                   │
│         (deploy/sign-notarize.sh)                            │
└─────────────────────────────────────────────────────────────┘
```

### Integration Points

| Component | Current State | Modified/New | Purpose |
|-----------|--------------|--------------|---------|
| **Package.swift** | Exists | Unmodified | Source of truth for code organization |
| **Sources/** | Exists | Unmodified | All application code stays in SPM |
| **Xcode project** | None | **NEW** | Wrapper for App Store requirements |
| **Entitlements** | None | **NEW** | Sandbox and capability configuration |
| **Info.plist** | Static file | **MODIFIED** | Move to Xcode, version automation |
| **Build scripts** | SPM-based | **PRESERVED** | Developer ID workflow unchanged |
| **CI workflows** | GitHub Actions | **EXTENDED** | Add App Store build job |
| **SandboxDetector** | Exists | Unmodified | Runtime detection already implemented |

## Component Responsibilities

### Existing Components (Unmodified)

| Component | Responsibility | Why It Stays the Same |
|-----------|----------------|----------------------|
| Package.swift | Define targets, dependencies, resources | SPM remains source of truth |
| Sources/PingScope/ | All application logic (MVVM) | Code is distribution-agnostic |
| Tests/ | Unit and integration tests | Testing logic doesn't change |
| SandboxDetector | Runtime sandbox detection | Already handles both environments |
| PingMethod.availableCases | Feature gating based on sandbox | Already filters ICMP in sandbox |

### New Components (App Store Support)

| Component | Responsibility | Implementation |
|-----------|----------------|----------------|
| **PingScope.xcodeproj** | Xcode project wrapper | References local SPM package at `.` (root) |
| **PingScope-AppStore.entitlements** | App Store sandbox config | XML plist with sandbox + network.client |
| **PingScope-DeveloperID.entitlements** | Developer ID hardened runtime | XML plist with hardened runtime flags |
| **Build Schemes** | Differentiate build types | AppStore scheme vs DeveloperID scheme |
| **Provisioning Profiles** | App Store signing | Managed by Xcode, not in version control |

### Modified Components (Integration Points)

| Component | Current | Change Required | Rationale |
|-----------|---------|-----------------|-----------|
| **Info.plist** | Static file in root | Move to Xcode project, use build settings | Version automation, Xcode management |
| **GitHub Actions** | Single Developer ID job | Add parallel App Store job | Dual distribution from same commit |
| **.gitignore** | SPM build artifacts | Add Xcode artifacts (DerivedData, *.xcworkspace) | Ignore Xcode-generated files |

## Data Flow

### Dependency Flow

```
┌─────────────────────────────────────────────┐
│  Xcode Project (Wrapper)                    │
│    • Target configuration                   │
│    • Entitlements selection                 │
│    • Code signing settings                  │
└────────────┬────────────────────────────────┘
             │ (local package dependency)
             ↓
┌─────────────────────────────────────────────┐
│  Package.swift (SPM)                        │
│    • Source code location                   │
│    • Resource processing                    │
│    • Test targets                           │
└────────────┬────────────────────────────────┘
             │
             ↓
┌─────────────────────────────────────────────┐
│  Sources/PingScope/                         │
│    • Application code (unchanged)           │
│    • SwiftUI views                          │
│    • Services and ViewModels                │
└─────────────────────────────────────────────┘
```

### Build-Time Data Flow

**Developer ID Build (Existing):**
```
SPM → Binary → Manual .app → Sign → Notarize → DMG/PKG → GitHub
```

**App Store Build (New):**
```
Xcode → Archive → Export → Validate → Upload → TestFlight/Review
  ↓
  Uses SPM package as dependency
  ↓
  Applies AppStore.entitlements
  ↓
  Signs with Distribution certificate
```

### Runtime Data Flow (Unchanged)

```
App Launch
    ↓
SandboxDetector.isRunningInSandbox
    ↓
    ├─ true  → PingMethod.availableCases = [TCP, UDP]
    └─ false → PingMethod.availableCases = [TCP, UDP, ICMP]
    ↓
User sees appropriate ping methods in UI
```

## Recommended Project Structure

```
pingscope/
├── Package.swift                          # [UNCHANGED] SPM definition
├── Sources/                               # [UNCHANGED] All app code
│   └── PingScope/
│       ├── App/
│       ├── Services/
│       ├── ViewModels/
│       ├── Views/
│       ├── MenuBar/
│       ├── Models/
│       ├── Utilities/
│       └── Resources/
│           ├── AppIcon.icns
│           └── PrivacyInfo.xcprivacy
├── Tests/                                 # [UNCHANGED] Test code
├── PingScope.xcodeproj/                   # [NEW] Xcode wrapper
│   ├── project.pbxproj                    # Main project file
│   └── xcshareddata/
│       └── xcschemes/
│           ├── AppStore.xcscheme          # App Store build scheme
│           └── DeveloperID.xcscheme       # Developer ID build scheme
├── Configuration/                         # [NEW] Xcode support files
│   ├── Info.plist                         # Moved from root, managed by Xcode
│   ├── PingScope-AppStore.entitlements
│   └── PingScope-DeveloperID.entitlements
├── scripts/                               # [PRESERVED] Developer ID scripts
│   ├── build-app-bundle.sh
│   └── dev-run-app.sh
├── deploy/                                # [PRESERVED] Developer ID signing
│   ├── sign-notarize.sh
│   └── README.md
├── .github/workflows/                     # [MODIFIED] Dual distribution
│   ├── production-release.yml             # Developer ID (existing)
│   └── appstore-release.yml               # [NEW] App Store builds
└── .gitignore                             # [MODIFIED] Add Xcode artifacts
```

### Structure Rationale

- **Package.swift at root:** SPM packages conventionally live at repository root; Xcode can reference it as local dependency
- **Sources/ unchanged:** All code stays in SPM structure; no migration required
- **Configuration/ folder:** Groups Xcode-specific files (entitlements, Info.plist) separate from source code
- **Parallel workflows:** Developer ID and App Store builds coexist without interference
- **Script preservation:** Existing build tooling continues to work for Developer ID

## Architectural Patterns

### Pattern 1: Xcode Project Wrapping Local SPM Package

**What:** Xcode project references the root-level Package.swift as a local package dependency, allowing Xcode to build SPM code without duplicating sources.

**When to use:** When adding Xcode-specific capabilities (App Store, entitlements, provisioning) to existing SPM executable projects.

**Trade-offs:**
- **Pro:** Zero code duplication; SPM remains source of truth
- **Pro:** Existing SPM workflows (tests, command-line builds) unaffected
- **Pro:** Modular architecture preserved
- **Con:** Two build systems to maintain (SPM + Xcode)
- **Con:** Requires Xcode for App Store builds (can't use pure SPM)

**Example:**
```swift
// In Xcode Project Settings → Frameworks, Libraries, and Embedded Content
// Add local package: File → Add Package Dependencies → Add Local...
// Select repository root (where Package.swift lives)
// Xcode automatically discovers the executable target
```

### Pattern 2: Build Scheme Differentiation

**What:** Use Xcode build schemes to configure different entitlements, signing, and settings for the same codebase.

**When to use:** When same app needs to be distributed through multiple channels with different security requirements.

**Trade-offs:**
- **Pro:** Single codebase, multiple distributions
- **Pro:** Compile-time and runtime feature gating possible
- **Pro:** Clear separation of concerns (scheme = distribution method)
- **Con:** Must maintain multiple entitlement files
- **Con:** Risk of building wrong scheme accidentally

**Example:**
```
AppStore Scheme:
  - Entitlements: PingScope-AppStore.entitlements
  - Code Signing: Apple Distribution certificate
  - Archive exports for App Store

DeveloperID Scheme:
  - Entitlements: PingScope-DeveloperID.entitlements
  - Code Signing: Developer ID Application certificate
  - Archive exports for direct distribution
```

### Pattern 3: Runtime Sandbox Detection for Feature Gating

**What:** Detect sandbox environment at runtime and adjust available features accordingly (already implemented in PingScope).

**When to use:** When app has features unavailable in sandboxed environments (e.g., raw ICMP sockets).

**Trade-offs:**
- **Pro:** Single binary adapts to environment
- **Pro:** No compile-time branching required
- **Pro:** User sees consistent UI, just with filtered options
- **Con:** Must ship code for features that may never be available
- **Con:** Could confuse users if feature disappears after changing distribution

**Example:**
```swift
// Already implemented in PingScope
enum PingMethod {
    case tcp, udp, icmp

    static var availableCases: [PingMethod] {
        if SandboxDetector.isRunningInSandbox {
            return [.tcp, .udp]  // ICMP unavailable in sandbox
        }
        return allCases
    }
}
```

### Pattern 4: Entitlement File Per Distribution Channel

**What:** Maintain separate `.entitlements` files for each distribution method, selected by build scheme.

**When to use:** Always, when supporting multiple distribution channels for macOS apps.

**Trade-offs:**
- **Pro:** Explicit, reviewable security configuration
- **Pro:** Compiler/Xcode validates entitlement correctness
- **Pro:** Easy to see differences between distributions
- **Con:** Must remember to update both files when adding capabilities

**Example:**
```xml
<!-- PingScope-AppStore.entitlements -->
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>

<!-- PingScope-DeveloperID.entitlements -->
<key>com.apple.security.app-sandbox</key>
<false/>
<key>com.apple.security.cs.allow-unsigned-executable-memory</key>
<true/>
```

## Anti-Patterns

### Anti-Pattern 1: Migrating Code Out of SPM Package

**What people do:** Move source code from `Sources/PingScope/` into the Xcode project's target directly.

**Why it's wrong:**
- Breaks existing SPM workflows (tests, command-line builds)
- Duplicates source management
- Loses modular architecture benefits
- Forces all developers to use Xcode

**Do this instead:** Keep all code in SPM package; Xcode project is just a wrapper that references the package.

### Anti-Pattern 2: Single Entitlements File with Preprocessor Directives

**What people do:** Try to use `#if DEBUG` or build settings to conditionally enable sandboxing in one entitlements file.

**Why it's wrong:**
- Entitlements files are XML plists, not compiled code—preprocessor doesn't work
- Distribution type (App Store vs Developer ID) isn't about Debug vs Release
- Increases risk of shipping wrong entitlements

**Do this instead:** Use separate entitlement files, one per distribution channel, selected by build scheme.

### Anti-Pattern 3: Duplicating Info.plist Between Builds

**What people do:** Maintain separate Info.plist files for SPM builds and Xcode builds with manual version syncing.

**Why it's wrong:**
- Version number drift between distributions
- Double maintenance burden
- Easy to forget updating one

**Do this instead:**
- Move Info.plist to Xcode management
- Use Xcode build settings for version numbers
- SPM-only builds can read version from git tags or environment variables

### Anti-Pattern 4: Abandoning Developer ID Distribution

**What people do:** Once App Store distribution works, stop supporting Developer ID builds.

**Why it's wrong:**
- Loses fast-track notarization workflow for testing
- Loses direct distribution channel (some users prefer DMG)
- Loses ability to ship features unavailable in sandbox (ICMP)
- Reduces distribution flexibility

**Do this instead:** Maintain both workflows in parallel; they complement each other.

## Integration Sequence (Migration Path)

### Phase 1: Create Xcode Project (No Build Changes)

1. **Create wrapper project:**
   ```bash
   # From repository root
   open -a Xcode
   # File → New → Project → macOS → App
   # Save as "PingScope.xcodeproj" in repository root
   # Delete auto-generated source files (keep project only)
   ```

2. **Add local SPM package dependency:**
   - File → Add Package Dependencies → Add Local
   - Select repository root (where Package.swift lives)
   - Xcode discovers executable target automatically

3. **Configure target:**
   - Set Bundle Identifier: `com.hadm.pingscope` (matches existing)
   - Set Deployment Target: macOS 13.0
   - Set Display Name: PingScope
   - Verify executable links to SPM target

4. **Verify build:**
   ```bash
   xcodebuild -scheme PingScope -configuration Debug
   # Should produce same app as SPM build
   ```

**Verification:** Xcode build produces functional .app, existing `swift build` still works.

### Phase 2: Add Entitlements (Still No Sandbox)

1. **Create DeveloperID entitlements:**
   - Xcode → Target → Signing & Capabilities → + Capability → Hardened Runtime
   - Save generated entitlements as `Configuration/PingScope-DeveloperID.entitlements`
   - Edit to disable sandbox explicitly

2. **Create DeveloperID scheme:**
   - Product → Scheme → Manage Schemes → Duplicate
   - Name: "DeveloperID"
   - Edit Scheme → Build Configuration → Release
   - Edit Scheme → Archive → set entitlements file

3. **Test DeveloperID archive:**
   ```bash
   xcodebuild -scheme DeveloperID archive -archivePath build/DeveloperID.xcarchive
   xcodebuild -exportArchive -archivePath build/DeveloperID.xcarchive \
     -exportPath build/export -exportOptionsPlist export-developerid.plist
   ```

**Verification:** Xcode-built Developer ID archive works identically to SPM-built version, ICMP available.

### Phase 3: Add App Store Support

1. **Create AppStore entitlements:**
   - Create `Configuration/PingScope-AppStore.entitlements`
   - Enable: App Sandbox, Outgoing Connections (Client)
   - Disable: All others (minimalist approach)

2. **Create AppStore scheme:**
   - Product → Scheme → Manage Schemes → Duplicate DeveloperID
   - Name: "AppStore"
   - Edit Scheme → set AppStore entitlements file

3. **Configure provisioning:**
   - Xcode → Target → Signing & Capabilities
   - AppStore scheme: Use "Apple Distribution" certificate
   - Enable automatic signing or use manual provisioning profile

4. **Test App Store archive:**
   ```bash
   xcodebuild -scheme AppStore archive -archivePath build/AppStore.xcarchive
   xcodebuild -exportArchive -archivePath build/AppStore.xcarchive \
     -exportPath build/export -exportOptionsPlist export-appstore.plist
   ```

5. **Verify runtime behavior:**
   ```bash
   # Extract and run sandboxed build
   # Check: PingMethod.availableCases should return [TCP, UDP] only
   # Check: UI shows only TCP/UDP options
   ```

**Verification:** App Store archive validates in Xcode, sandbox detection works, ICMP correctly hidden.

### Phase 4: CI/CD Integration

1. **Preserve existing Developer ID workflow:**
   - Keep `.github/workflows/production-release.yml` unchanged
   - Existing DMG/PKG generation continues to work

2. **Add App Store workflow:**
   - Create `.github/workflows/appstore-release.yml`
   - Trigger: Manual or on specific tags (e.g., `v*-appstore`)
   - Steps: xcodebuild archive → exportArchive → upload via `xcrun altool`

3. **Environment secrets:**
   - Add App Store Connect API key to GitHub Secrets
   - Add App Distribution certificate and provisioning profile

**Verification:** Both workflows run independently, produce correct artifacts.

### Phase 5: Validation and Testing

1. **Developer ID testing:**
   - Build with DeveloperID scheme
   - Verify ICMP available
   - Test notarization

2. **App Store testing:**
   - Build with AppStore scheme
   - Verify ICMP hidden
   - Upload to TestFlight
   - Test in sandboxed environment

3. **Feature parity check:**
   - All features work in both distributions (except ICMP)
   - UI responds correctly to sandbox detection
   - No crashes or permission errors

**Verification:** Both distributions functionally identical except for documented sandbox limitations.

## Build Order Dependencies

```
1. SPM Package (Package.swift + Sources/)
   ↓
2. Xcode Project Creation
   ↓
3. Local Package Reference in Xcode
   ↓
4. Entitlements Files (DeveloperID, AppStore)
   ↓
5. Build Schemes (DeveloperID, AppStore)
   ↓
6. Code Signing Configuration
   ↓
7. Archive and Export
   ↓
8. CI/CD Workflow Integration
```

**Critical path:** Must have working SPM build before Xcode integration. Entitlements must be finalized before CI/CD automation.

## Confidence Assessment

| Topic | Confidence | Rationale |
|-------|-----------|-----------|
| Xcode wrapper pattern | HIGH | Well-documented Apple pattern, confirmed by recent 2025-2026 articles on modularization |
| Entitlements configuration | HIGH | Official Apple documentation on sandbox and network.client entitlement |
| Build scheme differentiation | HIGH | Standard Xcode feature, widely used for multi-environment apps |
| SPM local package reference | MEDIUM-HIGH | Confirmed by Swift forums and 2026 articles, but less documentation than other topics |
| Migration path | MEDIUM | Based on common patterns, but project-specific details may vary |
| CI/CD automation | MEDIUM | Xcode command-line tools well-documented, but workflow-specific testing needed |

## Sources

- [Modern iOS Architecture: Build Modular Apps with Swift Package Manager (2025 Guide)](https://ravi6997.medium.com/modern-ios-architecture-building-a-modular-project-with-swift-package-manager-033d8de9799f)
- [macOS App Entitlements Guide: Part 1 — Foundation & Network Access (Jan 2026)](https://medium.com/@info_4533/macos-app-entitlements-guide-b563287c07e1)
- [Configuring the macOS App Sandbox | Apple Developer Documentation](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
- [Managing different Environments using XCode Build Schemes and Configurations](https://ali-akhtar.medium.com/managing-different-environments-using-xcode-build-schemes-and-configurations-af7c43f5be19)
- [Entitlements | Apple Developer Documentation](https://developer.apple.com/documentation/bundleresources/entitlements)
- [How to add local Swift Packages to an iOS project](https://tanaschita.com/spm-add-local-packages/)
- [Xcode project with SPM dependencies - Swift Forums](https://forums.swift.org/t/xcode-project-with-spm-dependencies/18157)
- [Local SPM (Part 2) — Mastering Modularization with Swift Package Manager (Xcode 26)](https://medium.com/@guycohendev/local-spm-part-2-mastering-modularization-with-swift-package-manager-xcode-15-16-d5a11ddd166c)
- [com.apple.security.network.client | Apple Developer Documentation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client)
- [Signing Mac Software with Developer ID - Apple Developer](https://developer.apple.com/developer-id/)

---
*Architecture research for: App Store distribution integration with existing SPM-based macOS menu bar app*
*Researched: 2026-02-16*
