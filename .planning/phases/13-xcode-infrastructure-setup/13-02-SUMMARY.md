---
phase: 13-xcode-infrastructure-setup
plan: 02
subsystem: build-infrastructure
tags: [entitlements, info-plist, version-automation, dual-distribution]
dependency_graph:
  requires:
    - 13-01 (Asset catalog and project structure)
  provides:
    - Dual entitlements configuration for App Store and Developer ID
    - Xcode-managed Info.plist with version automation
  affects:
    - 13-03 (Xcode project wrapper will reference these files)
    - 14-01 (Sandbox testing will use AppStore entitlements)
    - 16-01 (App Store submission will use automated versioning)
tech_stack:
  added:
    - PingScope-AppStore.entitlements (sandbox enabled)
    - PingScope-DeveloperID.entitlements (sandbox disabled)
    - Configuration/Info.plist (Xcode version variables)
  patterns:
    - Dual entitlement files for different distribution channels
    - Version automation via MARKETING_VERSION and CURRENT_PROJECT_VERSION
    - SPM/Xcode hybrid configuration (root + Configuration/ Info.plist)
key_files:
  created:
    - Configuration/PingScope-AppStore.entitlements
    - Configuration/PingScope-DeveloperID.entitlements
    - Configuration/Info.plist
  modified: []
decisions:
  - name: Use .entitlements extension
    rationale: Xcode expects .entitlements not .plist for entitlement files
    impact: Fixes "Pitfall 2: Entitlement File Extension Mismatch" from research
  - name: Separate CFBundleShortVersionString and CFBundleVersion
    rationale: App Store requires incrementing build number on each upload attempt
    impact: Prevents "duplicate binary" errors on resubmission with same version
  - name: Preserve root Info.plist
    rationale: SPM build workflow still needs it
    impact: Dual Info.plist setup - root for SPM, Configuration/ for Xcode
metrics:
  duration_minutes: 2
  tasks_completed: 3
  files_created: 3
  commits: 3
  deviations: 0
  completed_at: 2026-02-17T03:47:42Z
---

# Phase 13 Plan 02: Entitlements and Info.plist Configuration Summary

Dual entitlements files created with correct sandbox settings for App Store and Developer ID distributions, Info.plist migrated with Xcode version automation variables.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create App Store entitlements file | aac51b7 | Configuration/PingScope-AppStore.entitlements |
| 2 | Create Developer ID entitlements file | 12e60cf | Configuration/PingScope-DeveloperID.entitlements |
| 3 | Migrate Info.plist with version automation | 2fc6765 | Configuration/Info.plist |

## What Changed

### App Store Entitlements (Sandbox Enabled)
- Created `Configuration/PingScope-AppStore.entitlements` with `.entitlements` extension
- Enabled `com.apple.security.app-sandbox` for App Store compliance
- Configured network client access for ping operations
- Configured file access for future export features
- Based on existing `entitlements-appstore.plist` but with correct extension

### Developer ID Entitlements (Sandbox Disabled)
- Created `Configuration/PingScope-DeveloperID.entitlements` for notarized distribution
- Disabled `com.apple.security.app-sandbox` to enable raw socket ICMP access
- Enabled hardened runtime with security restrictions for notarization
- Ensures `SandboxDetector.isRunningInSandbox` returns false in Developer ID builds
- Shows ICMP option in PingMethod picker for Developer ID distribution

### Info.plist Version Automation
- Copied root `Info.plist` to `Configuration/Info.plist`
- Replaced `CFBundleShortVersionString: "1.0.1"` with `$(MARKETING_VERSION)`
- Replaced `CFBundleVersion: "1.0.1"` with `$(CURRENT_PROJECT_VERSION)`
- Preserved root `Info.plist` for existing SPM build workflow
- Enables Xcode to manage versions through build settings

### Version Scheme for v1.1
- `MARKETING_VERSION = "1.1.0"` (user-facing version)
- `CURRENT_PROJECT_VERSION = "1"` (build number, increments per upload)
- Prevents "duplicate binary" errors on App Store resubmission with same version

## Deviations from Plan

None - plan executed exactly as written.

## Success Criteria Met

- [x] Two entitlements files exist with correct sandbox settings (enabled for AppStore, disabled for DeveloperID)
- [x] Info.plist migrated to Configuration/ with Xcode version automation variables
- [x] Root Info.plist preserved for existing SPM build workflow
- [x] All files ready for Xcode project integration in Plan 03

## Verification Results

```bash
# App Store entitlements with sandbox enabled
$ cat Configuration/PingScope-AppStore.entitlements | grep "com.apple.security.app-sandbox"
	<key>com.apple.security.app-sandbox</key>
	<true/>

# Developer ID entitlements with sandbox disabled
$ cat Configuration/PingScope-DeveloperID.entitlements | grep "com.apple.security.app-sandbox"
	<key>com.apple.security.app-sandbox</key>
	<false/>

# Info.plist with version variables
$ grep '$(MARKETING_VERSION)' Configuration/Info.plist
	<string>$(MARKETING_VERSION)</string>

# Configuration directory structure
$ ls -la Configuration/
total 32
drwxr-xr-x   6 keith  staff   192 Feb 16 19:47 .
drwxr-xr-x  30 keith  staff   960 Feb 16 19:42 ..
-rw-r--r--   1 keith  staff  1726 Feb 16 19:47 Info.plist
-rw-r--r--   1 keith  staff   495 Feb 16 19:46 PingScope-AppStore.entitlements
-rw-r--r--   1 keith  staff   580 Feb 16 19:46 PingScope-DeveloperID.entitlements
-rw-r--r--   1 keith  staff  1661 Feb 16 19:43 README.md

# Root Info.plist still exists for SPM
$ ls -la Info.plist
-rw-r--r--  1 keith  staff  1690 Feb 15 18:27 Info.plist
```

## Next Steps

Plan 03 will create the Xcode project wrapper that references these files:
- Set Code Signing Entitlements build setting to appropriate entitlements file per configuration
- Set MARKETING_VERSION and CURRENT_PROJECT_VERSION in project settings
- Configure Info.plist File build setting to Configuration/Info.plist

## Self-Check: PASSED

**Created files exist:**
- FOUND: Configuration/PingScope-AppStore.entitlements
- FOUND: Configuration/PingScope-DeveloperID.entitlements
- FOUND: Configuration/Info.plist

**Commits exist:**
- FOUND: aac51b7 (App Store entitlements)
- FOUND: 12e60cf (Developer ID entitlements)
- FOUND: 2fc6765 (Info.plist migration)
