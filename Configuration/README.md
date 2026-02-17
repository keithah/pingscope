# Configuration Directory

This directory holds Xcode-specific project configuration files for PingScope's dual-distribution strategy.

## Purpose

Separates Xcode infrastructure from Swift Package Manager source code, enabling both App Store and Developer ID distributions from a single codebase.

## Contents

### Entitlements Files

- **PingScope-AppStore.entitlements** (created in Plan 02)
  - Sandbox enabled (`com.apple.security.app-sandbox=true`)
  - Network client access for HTTP ping monitoring
  - Used by App Store build scheme

- **PingScope-DeveloperID.entitlements** (created in Plan 02)
  - Sandbox disabled (`com.apple.security.app-sandbox=false`)
  - Hardened runtime only
  - Enables ICMP raw socket access
  - Used by Developer ID build scheme

### Info.plist

- **Info.plist** (migrated from root in Plan 02)
  - Application metadata and capabilities
  - Version automation via Xcode build settings:
    - `CFBundleShortVersionString` → `$(MARKETING_VERSION)`
    - `CFBundleVersion` → `$(CURRENT_PROJECT_VERSION)`
  - Managed by Xcode project, not manually edited

## Source of Truth

- **Code:** Package.swift and Sources/ remain the source of truth
- **Assets:** Assets.xcassets/ for icons and resources
- **Configuration:** This directory for Xcode-specific files only

Xcode project wrapper references Package.swift as local dependency, avoiding code duplication.

## Related Files

- `Package.swift` - Swift Package Manager source of truth
- `PingScope.xcodeproj/` - Xcode wrapper project (created in Plan 02)
- `Assets.xcassets/` - Asset catalog for icons
- `scripts/build-app-bundle.sh` - Developer ID build script (preserved)
