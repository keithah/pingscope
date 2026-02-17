# Pitfalls Research: Mac App Store Submission

**Domain:** Adding Mac App Store distribution to existing menu bar app
**Researched:** 2026-02-16
**Confidence:** MEDIUM

## Critical Pitfalls

### Pitfall 1: Raw Socket ICMP Incompatibility with App Sandbox

**What goes wrong:**
The app's core ping functionality fails completely in sandboxed builds. Raw sockets (required for ICMP) are blocked by the App Sandbox, resulting in "Operation not permitted" errors. No entitlement exists to permit raw socket access in sandboxed apps.

**Why it happens:**
Raw sockets require root privileges, and sandboxed apps cannot escalate privileges. Developers assume network entitlements (`com.apple.security.network.client`) will allow ping operations, but these only cover standard TCP/UDP connections, not raw ICMP sockets.

**How to avoid:**
- Implement network reachability fallback (TCP-based connection testing)
- Use `ping` command-line tool via Process (if `com.apple.security.temporary-exception.apple-events` allows)
- Document in app description that sandbox limitations affect ICMP functionality
- Consider maintaining separate Developer ID and App Store builds with different feature sets

**Warning signs:**
- Ping operations work in dev builds but fail in archived/sandboxed builds
- Runtime sandbox detection shows sandboxed environment but ping still attempted
- Console logs show "Operation not permitted" for socket creation

**Phase to address:**
Phase 1 (Sandbox Verification) - Test actual ping functionality in sandboxed environment, not just sandbox detection.

---

### Pitfall 2: Privacy Manifest Missing or Incomplete

**What goes wrong:**
App rejection with error: "Missing or incomplete privacy manifest." Starting May 1, 2024, apps that don't describe their use of required reason APIs in their privacy manifest file aren't accepted by App Store Connect.

**Why it happens:**
Developers assume privacy manifests are only for iOS, or only for apps that track users. In reality, any app using "required reason APIs" (file timestamps, disk space, system boot time, active keyboard layouts, user defaults) must declare why they use these APIs.

**How to avoid:**
- Create `PrivacyInfo.xcprivacy` file in app bundle
- Declare all required reason API usage with approved reason codes
- Include `NSPrivacyAccessedAPITypes` array even if not tracking
- Document network domains if using `NSPrivacyTrackingDomains`
- Test validation with `xcrun altool --validate-app` before submission

**Warning signs:**
- App uses UserDefaults, file system APIs, or system info calls
- Third-party dependencies (even via SPM) may use required APIs
- Asset validation passes but App Store Connect upload fails

**Phase to address:**
Phase 2 (Privacy Compliance) - Audit all API usage and create complete privacy manifest.

---

### Pitfall 3: Entitlement Configuration Discrepancy Between Build Systems

**What goes wrong:**
App builds successfully with Developer ID but fails App Store validation with "invalid entitlements" or "missing App Sandbox entitlement." Hybrid SPM/Xcode projects may have entitlements configured in one place but not propagated to the App Store build.

**Why it happens:**
Developer ID builds don't require App Sandbox (`com.apple.security.app-sandbox = true`), but App Store builds do. Developers test with Developer ID configuration and assume App Store build will work identically. Entitlements may be set in Xcode project but not in SPM package targets, or vice versa.

**How to avoid:**
- Create separate entitlement files: `App.entitlements` (Dev ID) and `AppStore.entitlements` (App Store)
- Use build configurations to switch entitlement files
- Always enable `com.apple.security.app-sandbox = true` for App Store builds
- Test archive builds, not just run-from-Xcode builds
- Verify entitlements with: `codesign -d --entitlements - /path/to/app`

**Warning signs:**
- App runs fine from Xcode but fails when archived
- Validation shows "app must be sandboxed for App Store"
- Different behavior between "Product > Run" and "Product > Archive"

**Phase to address:**
Phase 1 (Sandbox Verification) - Establish separate build configurations with proper entitlement files.

---

### Pitfall 4: LSUIElement Without Proper App Presence

**What goes wrong:**
App rejected for "insufficient functionality" or "looks incomplete." Menu bar apps using `LSUIElement = true` (no Dock icon) are perceived as unfinished if they lack standard UI elements like preferences windows or About panels.

**Why it happens:**
App reviewers evaluate completeness in 5-10 minutes. Menu bar-only apps appear skeletal without visible UI. Reviewers don't realize menu bar is intentional design, thinking Dock icon removal indicates incomplete development.

**How to avoid:**
- Include Preferences window (even if minimal)
- Provide About panel with app info
- Add keyboard shortcuts (signals "finished app")
- Include Help menu item with documentation
- In app description, explicitly state "menu bar utility" and "does not appear in Dock"
- Add screenshot showing menu bar dropdown in App Store listing

**Warning signs:**
- App has no UI beyond menu bar dropdown
- No visual indication of what app does when launched
- Reviewers unable to find app after installation

**Phase to address:**
Phase 3 (App Store Polish) - Add standard UI affordances even if minimal.

---

### Pitfall 5: Asset Validation Failures

**What goes wrong:**
Upload to App Store Connect fails with "Asset validation failed" errors related to app icons, missing files, or corrupted binaries.

**Why it happens:**
- App Store icon (1024x1024) contains transparency or alpha channel (rejected)
- Icon not in Asset Catalog or wrong format (must be PNG, not JPEG)
- Missing `PrivacyInfo.xcprivacy` interpreted as corrupt asset
- Archive built with wrong SDK version (pre-iOS 26 SDK after April 28, 2026)

**How to avoid:**
- Ensure 1024x1024 app icon is opaque PNG in Asset Catalog
- Use RGB color space, no alpha channel
- Build with current SDK (iOS 26+ after April 2026)
- Validate before upload: `xcrun altool --validate-app -f app.pkg -t macos`
- If validation fails, try Apple's Transporter app instead of Xcode
- Increment build number, not just version, if resubmitting

**Warning signs:**
- Icons work in development but fail validation
- Error message mentions "corrupted binaries" without specifics
- Upload succeeds but processing fails in App Store Connect

**Phase to address:**
Phase 4 (Submission Preparation) - Final asset validation before first upload.

---

### Pitfall 6: Duplicate Binary / Version Number Confusion

**What goes wrong:**
Resubmission after rejection fails with "Redundant Binary Upload" or "bundle version already exists." Developers cannot upload new binary with same version number even if previous build was rejected.

**Why it happens:**
Confusion between CFBundleVersion (build number) and CFBundleShortVersionString (version). Both must be unique per upload. Incrementing only one causes rejection.

**How to avoid:**
- Use semantic versioning for CFBundleShortVersionString (1.0.0, 1.0.1)
- Use incrementing integers for CFBundleVersion (1, 2, 3...)
- After rejection, increment CFBundleVersion (not CFBundleShortVersionString unless new features)
- Document build number policy in project README
- Automate version bumping in CI/CD

**Warning signs:**
- Second upload attempt with "same" version fails
- Error mentions duplicate build number
- Cannot figure out which number to increment

**Phase to address:**
Phase 4 (Submission Preparation) - Establish version numbering strategy before first submission.

---

### Pitfall 7: Helper Tools / Privileged Operations Not Allowed

**What goes wrong:**
App using SMJobBless or privileged helper tools rejected. App Store apps cannot install helper tools requiring elevated privileges.

**Why it happens:**
Developers port existing Developer ID app that uses helper tool for privileged operations (like monitoring network interfaces at low level). App Store sandboxing prohibits privileged helper tool installation.

**How to avoid:**
- Remove SMJobBless / helper tool code from App Store build
- Use sandbox-compatible alternatives: `SMAppService` (macOS 13+) for unprivileged launch agents
- Request only permissions available via entitlements
- Document in app description if App Store version has reduced functionality
- Consider maintaining two codebases: full-featured Developer ID, limited App Store

**Warning signs:**
- Code references `SMJobBless`, `AuthorizationCreate`, or privileged helper
- App requests admin password
- Functionality requires reading system logs or monitoring other apps

**Phase to address:**
Phase 1 (Sandbox Verification) - Identify all privileged operations and remove/replace.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Single entitlements file for both Dev ID and App Store | Faster initial setup | Build failures, wrong entitlements in wrong build | Never - separate from start |
| Skip privacy manifest for "simple" app | Faster submission prep | Guaranteed rejection if using required APIs | Never after May 1, 2024 |
| Assume sandbox detection = sandbox compatibility | Tests pass, code ships | Runtime failures in production sandbox | Never - test in actual sandbox |
| Reuse same version number after rejection | Avoid updating docs/changelog | Upload fails, confusion | Never - always increment build |
| Copy entitlements from template without audit | Fast configuration | Missing or excessive entitlements trigger rejection | Only if template verified for your use case |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| SPM + Xcode hybrid | Entitlements only in Xcode project, not in SPM package | Define entitlements in build settings, reference from both |
| Developer ID + App Store | Using same signing identity | Separate certificates: "Developer ID Application" vs "Mac App Distribution" |
| Notarization + App Store | Assuming notarization = App Store ready | Notarization validates non-App Store. App Store has different validation |
| Third-party dependencies | Assuming SPM packages include privacy manifests | Audit all dependencies for required API usage, add to your manifest |
| Network monitoring | Using raw sockets / packet capture | Use Network Extension framework (requires separate entitlement request from Apple) |

## Performance Traps

Not applicable - App Store submission process has no performance-related pitfalls distinct from general macOS development.

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Excessive entitlements "just in case" | Rejection for requesting unnecessary permissions | Request only entitlements actually used, justify each in review notes |
| Hardcoding credentials/API keys | Rejection for embedded secrets, security vulnerability | Use Keychain, exclude from repository, use obfuscation |
| Skipping sandbox testing | App fails at runtime for users, negative reviews | Test archived builds in sandbox, use clean VM or test user account |
| Privacy manifest with wrong reason codes | Rejection for privacy violation | Use only approved reason codes from Apple's TN3183 documentation |
| Temporary exception entitlements in production | Apple likely to reject, flags "trying to circumvent sandbox" | Use only for development, remove before submission |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Menu bar app with no visible UI | Users can't find app after install, think it didn't work | Show welcome window on first launch, include Preferences |
| No indication app is running | Users reinstall thinking it crashed | Status icon in menu bar, notification on launch |
| Different features in App Store vs Developer ID | Confusion, negative reviews "feature missing" | Clearly document version differences, explain sandbox limitations |
| Automatic updates removed (App Store handles it) | Update code runs but does nothing, confusing logs | Disable update checks in App Store build via build flag |
| Screenshots don't show menu bar interaction | Users don't understand what app does | Use menu bar screenshot guide, show dropdown in context |

## "Looks Done But Isn't" Checklist

- [ ] **Privacy Manifest:** Often missing network domain declarations — verify `NSPrivacyTrackingDomains` populated if tracking
- [ ] **Entitlements:** Often missing sandbox entitlement — verify `com.apple.security.app-sandbox = true` in archive
- [ ] **Icons:** Often contain alpha channel — verify 1024x1024 icon is opaque RGB PNG
- [ ] **Sandbox testing:** Often only tested in dev builds — verify archived build runs correctly on clean system
- [ ] **App description:** Often generic/incomplete — verify mentions "menu bar utility" and feature limitations
- [ ] **Helper tools:** Often left in from Dev ID build — verify no SMJobBless or privileged operations
- [ ] **Third-party dependencies:** Often not audited for privacy APIs — verify all SPM packages checked for required reason APIs
- [ ] **Build configuration:** Often only one configuration — verify separate Dev ID and App Store configs exist
- [ ] **Screenshots:** Often desktop screenshots — verify menu bar app shown in context per Apple guidelines
- [ ] **Version numbers:** Often confuse version vs build — verify both increment on resubmission

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Raw socket sandbox violation | MEDIUM | Implement TCP-based fallback, update app description, resubmit with reduced functionality |
| Missing privacy manifest | LOW | Create PrivacyInfo.xcprivacy, declare API usage, increment build number, reupload |
| Wrong entitlements | LOW | Create correct .entitlements file, update build settings, re-archive, validate, reupload |
| Insufficient functionality rejection | MEDIUM | Add Preferences window, About panel, Help documentation, update screenshots, resubmit |
| Asset validation failure | LOW | Fix icon transparency, ensure PNG format, increment build number, reupload |
| Duplicate binary error | LOW | Increment CFBundleVersion, re-archive, upload new build |
| Privileged helper rejection | HIGH | Remove helper tool, refactor to sandbox-compatible approach, extensive testing, resubmit |
| Metadata rejection | LOW | Update app description per guidelines, remove placeholder text, resubmit metadata |
| Privacy manifest wrong reason codes | LOW | Correct reason codes per TN3183, increment build, reupload |
| SDK version too old (post-April 2026) | LOW | Update Xcode to version 26+, rebuild with new SDK, reupload |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Raw socket sandbox violation | Phase 1: Sandbox Verification | Run archived build in sandboxed test account, verify ping works or falls back gracefully |
| Privacy manifest missing | Phase 2: Privacy Compliance | Validate with `xcrun altool`, verify PrivacyInfo.xcprivacy in bundle |
| Entitlement configuration discrepancy | Phase 1: Sandbox Verification | `codesign -d --entitlements -` on archive shows correct entitlements |
| LSUIElement perceived as incomplete | Phase 3: App Store Polish | Include Preferences/About in screenshots, test reviewer first-launch experience |
| Asset validation failures | Phase 4: Submission Preparation | `xcrun altool --validate-app` passes before upload |
| Duplicate binary version numbers | Phase 4: Submission Preparation | Version/build numbering strategy documented and automated |
| Helper tools not allowed | Phase 1: Sandbox Verification | No SMJobBless references, no privilege escalation in code |
| Metadata rejection | Phase 4: Submission Preparation | Review app description against Apple guidelines checklist |
| Third-party dependency privacy issues | Phase 2: Privacy Compliance | Audit all SPM packages, include their API usage in manifest |
| Separate build for App Store vs Dev ID | Phase 1: Sandbox Verification | Build configurations tested, feature flags work correctly |

## Sources

**Critical Requirements (HIGH confidence):**
- [macOS App Entitlements Guide: Part 1 — Foundation & Network Access](https://medium.com/@info_4533/macos-app-entitlements-guide-b563287c07e1) - Network entitlements and raw socket limitations
- [Raw Socket: Operation not permitted - Apple Developer Forums](https://developer.apple.com/forums/thread/660179) - Raw socket sandbox blocking
- [Privacy manifest files - Apple Developer Documentation](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) - Official privacy manifest requirements
- [TN3183: Adding required reason API entries - Apple Developer Documentation](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest) - Required reason API codes
- [Privacy updates for App Store submissions - Apple Developer](https://developer.apple.com/news/?id=3d8a9yyh) - May 1, 2024 enforcement date
- [Reminder: Privacy requirement starts May 1 - Apple Developer](https://developer.apple.com/news/?id=pvszzano) - Mandatory privacy manifest
- [Configuring the macOS App Sandbox - Apple Developer Documentation](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox) - Sandbox configuration

**Submission Issues (MEDIUM confidence):**
- [What I Learned Building a Native macOS Menu Bar App](https://medium.com/@p_anhphong/what-i-learned-building-a-native-macos-menu-bar-app-eacbc16c2e14) - Menu bar app best practices, LSUIElement, insufficient functionality issues
- [Apple App Store Submission Changes — April 2026](https://medium.com/@thakurneeshu280/apple-app-store-submission-changes-april-2026-5fa8bc265bbe) - April 28, 2026 SDK requirement
- [App Review Guidelines - Apple Developer](https://developer.apple.com/app-store/review/guidelines/) - Official review guidelines
- [App Store Review Guidelines 2026: Updated Checklist](https://adapty.io/blog/how-to-pass-app-store-review/) - Common rejection reasons
- [The ultimate guide to App Store rejections - RevenueCat](https://www.revenuecat.com/blog/growth/the-ultimate-guide-to-app-store-rejections/) - Metadata rejection patterns

**Asset and Build Issues (MEDIUM confidence):**
- [Build Error: Asset Validation Failed - Adalo](https://help.adalo.com/testing-your-app/publishing-to-the-apple-app-store/submit-your-build-to-the-app-store/build-error-asset-validation-failed-invalid-app-store-icon) - Icon transparency issues
- [Screenshot specifications - Apple Developer](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/) - Official screenshot requirements
- [How to Assemble Menu Bar App Screenshots for Mac App Store](https://christiantietze.de/posts/2022/04/menu-bar-screenshots/) - Menu bar screenshot guide
- [When uploading a new version - Apple Developer Forums](https://developer.apple.com/forums/thread/61099) - Duplicate binary issues
- [App Store Connect shows wrong build number - Apple Developer Forums](https://developer.apple.com/forums/thread/690481) - Version vs build number confusion

**Privileged Operations (HIGH confidence):**
- [Do we need to have a privileged helper - Apple Developer Forums](https://developer.apple.com/forums/thread/744930) - Helper tool restrictions
- [Elevating Privileges Safely - Apple Developer Archive](https://developer.apple.com/library/archive/documentation/Security/Conceptual/SecureCodingGuide/Articles/AccessControl.html) - SMJobBless and alternatives
- [Sandboxing on macOS - Mark Rowe](https://bdash.net.nz/posts/sandboxing-on-macos/) - Sandbox limitations

**Sandbox and Distribution (MEDIUM confidence):**
- [Distributing macOS applications - AugmentedMind](https://www.augmentedmind.de/2021/06/13/distributing-macos-applications/) - App Store vs Developer ID
- [Updating Mac Software - Apple Developer Documentation](https://developer.apple.com/documentation/security/updating-mac-software) - Update mechanisms
- [Discovering and diagnosing App Sandbox violations - Apple Developer Documentation](https://developer.apple.com/documentation/security/discovering-and-diagnosing-app-sandbox-violations) - Sandbox debugging
- [A Well-formed macOS Menu Bar Application in Sandbox](https://zhaoxin.pro/technology/15788123971580.html) - Sandbox constraints for menu bar apps

---
*Pitfalls research for: PingScope App Store submission*
*Researched: 2026-02-16*
*Confidence: MEDIUM - Based on official Apple documentation (HIGH confidence), developer forums and recent blog posts (MEDIUM confidence), and web search findings (requires validation during execution)*
