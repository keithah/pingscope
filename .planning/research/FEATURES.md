# Feature Research: App Store Submission

**Domain:** App Store Submission Requirements (macOS)
**Researched:** 2026-02-16
**Confidence:** HIGH

## Context

This is **v2.0 milestone research** — focused exclusively on App Store submission requirements. v1.0 product features are complete and working. This research covers what's needed to prepare PingScope for Mac App Store distribution.

## Feature Landscape

### Table Stakes (Apple Requires These)

Features required by App Store. Missing these = app rejection or submission blocked.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| App Metadata (name, subtitle, description, keywords) | Apple requires for product page | LOW | 30-char subtitle, 170-char promo text, 100-char keywords (comma-separated, no spaces) |
| App Icon (1024x1024 PNG) | Displayed on product page and in search | LOW | Must support Display P3 wide-gamut color, square with no rounded corners |
| Screenshots (1-10 images) | Users need to see the app before downloading | MEDIUM | 16:10 aspect ratio (1280x800 to 2880x1800), .png or .jpeg, max 10MB each |
| Age Rating | Apple requires for all apps | LOW | Complete questionnaire in App Store Connect (4+, 9+, 13+, 16+, 18+) — deadline Jan 31, 2026 |
| App Category | Determines where app appears in store | LOW | Primary category required (e.g., Utilities, Developer Tools) |
| Privacy Manifest (PrivacyInfo.xcprivacy) | Required since May 1, 2024 for all apps | MEDIUM | Document data collection and required reason APIs used |
| Privacy Nutrition Label | Auto-generated from privacy details in App Store Connect | LOW | Declare data practices for app and third-party SDKs |
| App Sandbox Entitlements | Mac App Store requirement | MEDIUM | Enable sandboxing, configure network access entitlements (outgoing connections) |
| Code Signing (App Store certificate) | Validates app authenticity | LOW | Requires active Apple Developer Program membership ($99/year) |
| Export Compliance Declaration | Required if app uses encryption | LOW | Declare encryption use in Info.plist or App Store Connect (HTTPS = exempt) |
| Xcode 26+ Build | Required starting April 28, 2026 | LOW | Build with macOS 26 SDK using Xcode 26 or later |
| App Bundle Validation | App must pass validation checks | LOW | Use Xcode or Application Loader to validate before submission |
| Support URL | Users need way to contact developer | LOW | URL for app support page or contact form |
| Copyright Notice | Legal requirement | LOW | Copyright year and holder name |

**Dependencies on v1.0:**
- Privacy Manifest requires understanding what data v1.0 collects (answer: none — all network monitoring is local)
- App Sandbox requires v1.0 to work without privileged operations (already supported via TCP/UDP ping modes)
- Screenshots require v1.0 UI to be complete (already done)

### Differentiators (Competitive Advantage)

Features that improve discoverability and conversion. Not required, but valuable.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| App Preview Videos (1-3) | Shows app in action, increases conversion 20-30% | MEDIUM | 15-30 seconds, H.264/ProRes, max 500MB, .mov/.m4v/.mp4 |
| Promotional Text (170 chars) | Updateable without new build, highlights current features/sales | LOW | Appears at top of description, doesn't affect search ranking |
| TestFlight Beta Testing | Find bugs before public release, gather feedback | LOW | Up to 100 internal + 10,000 external testers, 90-day build validity |
| Custom Product Pages | A/B test different messaging/screenshots | MEDIUM | Test variations for different user segments (network admins vs. developers) |
| Product Page Optimization | Test icon/screenshot variations | MEDIUM | Built-in A/B testing in App Store Connect |
| Multiple Screenshot Sizes | Provide optimal resolution for all displays | MEDIUM | All 4 sizes: 1280x800, 1440x900, 2560x1600, 2880x1800 |
| Localization | Reach non-English users | HIGH | Translate name, description, keywords, screenshots (40 languages available) |
| Accessibility Information | Highlight VoiceOver, Voice Control support | LOW | Auto-generates Accessibility Nutrition Label on product page |
| Compelling Description | Convert browsers to installers | LOW | Clear value proposition, feature bullets, avoid generic claims ("best", "world's #1") |
| Strategic Keywords | Improve search visibility | LOW | Research competitors, use ASO tools, avoid trademarked terms |
| What's New Text | Communicate updates to existing users | LOW | Required for updates, max 4,000 chars, explain improvements |

**Dependencies on v1.0:**
- App Preview Video requires v1.0 UI to be visually complete (done)
- Strategic Keywords require understanding v1.0's unique value (multi-host monitoring, ICMP support, visualization)
- Compelling Description requires knowing v1.0 differentiators (7 notification types, dual sandbox modes, etc.)

### Anti-Features (Common Rejection Reasons)

Features that seem good but create problems or cause rejection.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Keyword Stuffing in Description | Trying to improve search ranking | Description doesn't affect search; looks spammy; violates guidelines | Use dedicated 100-char keyword field strategically; focus on readability |
| Mentioning Competitors | Trying to capture competitor searches | Violates trademark guidelines, causes rejection | Focus on unique value proposition ("multi-host monitoring", not "better than SimplePing") |
| Generic Superlatives ("Best", "World's #1") | Trying to sound impressive | Prohibited by App Review Guidelines 2.3.8 | Use specific, measurable claims ("monitor up to 10 hosts simultaneously") |
| Repeating App Name in Keywords | Trying to boost ranking | Wastes character limit; name already indexed automatically | Use keywords for features, use cases, alternatives ("ping monitor", "latency tracker", "network status") |
| Including iOS in macOS Metadata | Copy-paste from iOS app | Causes rejection (cross-platform references prohibited) | Write platform-specific metadata for macOS only |
| Excessive Permissions/Entitlements | "Might need it later" approach | Privacy concerns, increases review scrutiny, delays approval | Request only what's needed (outgoing network for PingScope); add more later if required |
| Using Non-Exempt Encryption Without Declaration | Avoiding paperwork | Causes export compliance rejection | Declare encryption use in Info.plist: ITSAppUsesNonExemptEncryption = NO (HTTPS is exempt) |
| White-Label/Clone Apps | Trying to reach more users with similar apps | Violates Guideline 4.3 (Spam), instant rejection | Build unique value, differentiate from similar apps (PingScope's differentiators: multi-host, ICMP modes, 7 notification types) |
| Incomplete Test Info | Rushing submission | Delays review or causes rejection | Provide detailed review notes explaining dual sandbox modes, how to test ICMP vs. TCP/UDP |
| Placeholder Content | Submitting before ready | Guideline 2.1 rejection (incomplete app) | Wait until fully functional (v1.0 is ready — no placeholders) |
| App Store/TestFlight Confusion | Submitting TestFlight build to App Store | Different certificates, different configs | Use separate build schemes: "App Store" vs. "TestFlight" vs. "Developer ID" |

**Risks specific to PingScope:**
- Dual sandbox modes (App Store sandboxed vs. Developer ID non-sandboxed) might confuse reviewers — provide clear review notes
- Network monitoring might raise privacy concerns — Privacy Manifest must clearly state "no data collection, local monitoring only"
- ICMP might seem like privileged operation — explain TCP/UDP fallback, no root required

## Feature Dependencies

```
App Store Submission
    ├──requires──> App Metadata (name, subtitle, description, keywords)
    ├──requires──> App Icon (1024x1024)
    ├──requires──> Screenshots (1-10)
    ├──requires──> Privacy Manifest
    ├──requires──> Age Rating
    ├──requires──> App Category
    ├──requires──> Support URL
    ├──requires──> Copyright Notice
    ├──requires──> Export Compliance Declaration
    ├──requires──> App Sandbox Entitlements
    ├──requires──> Code Signing Certificate
    ├──requires──> Xcode 26+ Build
    └──requires──> App Bundle Validation

TestFlight Beta Testing
    ├──requires──> Code Signing Certificate (separate from App Store cert)
    ├──requires──> Export Compliance Declaration
    └──optional──> App Review (first build for external testers only)

App Preview Videos
    ├──enhances──> Screenshots
    ├──requires──> Same localization as screenshots
    └──depends-on──> v1.0 UI being visually complete ✓

Localization
    ├──requires──> Translated App Metadata
    ├──optional──> Localized Screenshots
    └──optional──> Localized App Preview Videos

Privacy Manifest
    ├──requires──> Privacy Nutrition Label entries in App Store Connect
    ├──auto-generates──> Privacy Nutrition Label on product page
    └──depends-on──> Understanding v1.0 data collection (none)

App Sandbox Entitlements
    ├──requires──> com.apple.security.app-sandbox = true
    ├──requires──> com.apple.security.network.client = true
    └──depends-on──> v1.0 working in sandbox mode ✓
```

### Dependency Notes

- **App Store Submission requires all table stakes features:** Apple's validation process checks for completeness. Missing any required item blocks submission.
- **TestFlight requires App Review for first external build:** Internal testing (up to 100 users with App Store Connect access) doesn't require review. External testing (up to 10,000) requires review for first build only; subsequent builds may skip review.
- **App Preview Videos enhance Screenshots:** Videos show the app in action; screenshots are still required. Videos appear before screenshots on product page.
- **Privacy Manifest generates Privacy Nutrition Label:** Create PrivacyInfo.xcprivacy file → complete privacy questionnaire in App Store Connect → Apple auto-generates nutrition label.
- **Localization requires translated metadata:** If adding a language, provide translated name, description, keywords, and optionally screenshots. Screenshots default to primary language if not provided.
- **v1.0 completeness gates v2.0:** All App Store submission assets (screenshots, videos, descriptions) require v1.0 UI to be final. **Status: v1.0 shipped 2026-02-17 — gate satisfied.**

## MVP Definition

### Launch With (v2.0 - App Store Submission)

Minimum required to get PingScope approved and listed.

- [ ] **App Metadata** — Name: "PingScope", Subtitle (≤30 chars): "Network Latency Monitor", Description (≤4000 chars), Keywords (≤100 chars): "ping,latency,network,monitor,icmp,uptime,status,connection"
- [ ] **App Icon** — 1024x1024 PNG with Display P3 color support, export from existing app icon asset
- [ ] **Screenshots** — 3-5 screenshots at 2880x1800 (16:10 ratio) showing: (1) menu bar + full interface, (2) multi-host tabs + graph, (3) settings panel, (4) ping history, (5) compact mode
- [ ] **Privacy Manifest** — PrivacyInfo.xcprivacy declaring network access (com.apple.security.network.client), no user data collection
- [ ] **Privacy Nutrition Label** — Declare "Data Not Collected" in App Store Connect (PingScope monitors locally, no telemetry)
- [ ] **Age Rating** — 4+ (no objectionable content, no in-app purchases, no user-generated content)
- [ ] **App Category** — "Utilities" (primary), no secondary category
- [ ] **Support URL** — GitHub repo (https://github.com/keithah/pingscope) or dedicated support page
- [ ] **Copyright Notice** — "© 2026 Keith Harris" (or appropriate entity)
- [ ] **Export Compliance** — Declare HTTPS exempt encryption in Info.plist: ITSAppUsesNonExemptEncryption = NO
- [ ] **App Sandbox Entitlements** — Enable sandbox (com.apple.security.app-sandbox = YES), outgoing network connections (com.apple.security.network.client = YES)
- [ ] **Code Signing** — App Store distribution certificate and provisioning profile (requires Apple Developer Program membership)
- [ ] **Xcode 26+ Build** — Build with macOS 26 SDK (required April 28, 2026)
- [ ] **App Bundle Validation** — Pass Xcode validation: Product > Archive > Validate App
- [ ] **Review Notes** — Explain dual-mode ICMP support: "App Store build uses TCP/UDP ping (sandboxed). Developer ID build supports true ICMP (non-sandboxed). Test using Settings > Ping Method."

### Add After Approval (v2.1)

Features to improve conversion and discoverability after initial approval.

- [ ] **Promotional Text** — Highlight key features (170 chars): "Monitor multiple hosts with real-time graphs. 7 notification types. Supports ICMP, TCP, and UDP ping. Free on the App Store."
- [ ] **App Preview Video** — 20-30 second demo showing: (1) menu bar status, (2) clicking to open popover, (3) switching host tabs, (4) real-time graph updating, (5) opening settings
- [ ] **TestFlight Beta** — Invite 10-20 external testers to test updates before public release
- [ ] **Strategic Keyword Optimization** — Research ASO tools (AppTweak, Asolytics), test keyword variations, monitor App Store search rankings
- [ ] **What's New Updates** — Write compelling update notes for each version: focus on user benefits, not technical details

### Future Consideration (v3+)

Features to defer until App Store presence is established.

- [ ] **Localization** — Translate to top 5-10 languages (Spanish, French, German, Japanese, Chinese Simplified)
- [ ] **Custom Product Pages** — A/B test messaging for different user segments (network admins: "Monitor uptime and latency" vs. developers: "Debug network issues")
- [ ] **Product Page Optimization** — Test icon variations (different colors, styles) and screenshot variations (light vs. dark mode)
- [ ] **Accessibility Documentation** — Highlight VoiceOver support if implemented (current status unknown — requires v1.0 accessibility audit)
- [ ] **In-App Events** — Promote new features or seasonal campaigns (if applicable)
- [ ] **Multiple Screenshot Sizes** — Provide all 4 resolutions (1280x800, 1440x900, 2560x1600, 2880x1800) instead of just highest

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| App Metadata | HIGH (blocks submission) | LOW (2 hours writing) | P1 |
| App Icon | HIGH (blocks submission) | LOW (export from Xcode) | P1 |
| Screenshots | HIGH (blocks submission) | MEDIUM (4-6 hours design) | P1 |
| Privacy Manifest | HIGH (blocks submission) | MEDIUM (2-3 hours research + implementation) | P1 |
| Age Rating | HIGH (blocks submission) | LOW (15 min questionnaire) | P1 |
| App Category | HIGH (blocks submission) | LOW (select from dropdown) | P1 |
| Support URL | HIGH (blocks submission) | LOW (use GitHub repo) | P1 |
| Copyright | HIGH (blocks submission) | LOW (enter in App Store Connect) | P1 |
| Export Compliance | HIGH (blocks submission) | LOW (add Info.plist key) | P1 |
| Sandbox Entitlements | HIGH (blocks submission) | MEDIUM (configure Xcode, test thoroughly) | P1 |
| Code Signing | HIGH (blocks submission) | LOW (enroll in Developer Program, create cert) | P1 |
| Xcode 26 Build | HIGH (blocks submission after Apr 28) | LOW (update Xcode) | P1 |
| Bundle Validation | HIGH (blocks submission) | LOW (run validator) | P1 |
| Review Notes | HIGH (prevents rejection) | LOW (1 hour writing) | P1 |
| Promotional Text | MEDIUM (improves conversion) | LOW (30 min writing) | P2 |
| App Preview Video | MEDIUM (improves conversion 20-30%) | MEDIUM (4-8 hours production) | P2 |
| TestFlight Beta | MEDIUM (reduces bugs in production) | LOW (1 hour setup) | P2 |
| Keyword Optimization | MEDIUM (improves discoverability) | LOW (2-3 hours research) | P2 |
| What's New Text | MEDIUM (keeps users engaged) | LOW (15 min per update) | P2 |
| Multiple Screenshot Sizes | LOW (minor quality improvement) | MEDIUM (2x work for screenshots) | P3 |
| Localization | LOW (expands market) | HIGH (translation + maintenance) | P3 |
| Custom Product Pages | LOW (A/B testing) | MEDIUM (create variations) | P3 |
| Product Page Optimization | LOW (conversion optimization) | MEDIUM (test multiple variants) | P3 |

**Priority key:**
- **P1:** Must have for initial submission (table stakes) — blocks App Store listing if missing
- **P2:** Should have to improve conversion (add immediately after approval or in v2.1) — improves downloads and user satisfaction
- **P3:** Nice to have for expansion (defer to v3+) — diminishing returns, high cost

## App Store Category Analysis

### Primary Category Candidates for PingScope

| Category | Fit | Pros | Cons | Recommendation |
|----------|-----|------|------|----------------|
| Utilities | HIGH | Most accurate — system monitoring tool | Competitive, many utility apps | **Use this** |
| Developer Tools | MEDIUM | Network monitoring useful for developers | Might limit audience perception (not just for developers) | Defer to v3 if "Utilities" doesn't work |
| Business | LOW | Could fit for IT/network admin use | Not primary target audience; too broad | Avoid |

**Recommendation:** Use **Utilities** as primary category. It accurately describes PingScope as a system monitoring tool for general macOS users (network admins, developers, power users, anyone troubleshooting connectivity).

**Rationale:**
- PingScope is a utility first, developer tool second
- "Utilities" aligns with competitors (SimplePing, iStat Menus network module)
- Broader audience than "Developer Tools"
- Easier to find via browse/filter

## Screenshot Strategy

### Recommended Screenshot Set (5 images, 2880x1800)

1. **Menu Bar Status + Full Interface** — Show colored dot, ping time in menu bar, and full dropdown with graph. Overlay text: "Real-time network monitoring in your menu bar"
2. **Multi-Host Tabs + Live Graph** — Demonstrate multiple hosts (Google DNS, Cloudflare, Default Gateway) with live graph updating. Overlay text: "Monitor multiple hosts simultaneously"
3. **Settings Panel + Host Management** — Show host management interface, add/edit/remove capabilities. Overlay text: "Flexible host configuration with ICMP, TCP, and UDP support"
4. **Ping History Table** — Display detailed history with timestamps, color-coded status (green/yellow/red). Overlay text: "Complete ping history for debugging and analysis"
5. **Compact Mode** — Show space-efficient compact view option. Overlay text: "Compact mode for minimal menu bar footprint"

**Design Guidelines:**
- Use 2880x1800 resolution (16:10 ratio) — highest quality, Apple scales down automatically
- Add subtle text overlays highlighting key features (white text with shadow for readability)
- Show realistic data (not Lorem ipsum) — use actual ping times (10-50ms range looks healthy)
- Maintain consistent visual style across all screenshots
- Use macOS light mode for consistency (App Store screenshots traditionally use light mode; can provide dark mode screenshots later)
- Include menu bar in screenshots 1, 2, and 5 (shows app in context)
- Use clean, uncluttered desktop background (solid color or subtle gradient)

### Screenshot Production Workflow

1. Launch PingScope v1.0
2. Configure 3-4 hosts (Google DNS, Cloudflare, Default Gateway, custom)
3. Let app run for 5-10 minutes to generate realistic graph data
4. Capture screenshots at 2880x1800 using macOS Screenshot tool (Cmd+Shift+4, then Space to capture window)
5. Add text overlays using Sketch, Figma, or Pixelmator Pro
6. Export as PNG at 100% quality
7. Validate file size < 10MB per screenshot

## Metadata Copywriting

### App Name (30 chars max)
**"PingScope"** (9 chars) — Short, memorable, descriptive

### Subtitle (30 chars max)
**"Network Latency Monitor"** (24 chars)

Alternatives:
- "Multi-Host Ping Monitor" (23 chars)
- "Real-time Ping Monitor" (22 chars)

### Description (4000 chars max, ~600 words)

**Structure:**
1. **Hook** (1-2 sentences) — What is it, who is it for
2. **Key Features** (bullet list) — 7-10 differentiators from v1.0
3. **Use Cases** (1 paragraph) — When to use it
4. **Technical Details** (1 paragraph) — ICMP/TCP/UDP, sandbox modes
5. **Call to Action** (1 sentence) — Download now, it's free

**Draft:**

```
PingScope is a professional network monitoring tool for macOS that displays real-time ping latency in your menu bar. Monitor multiple hosts simultaneously with beautiful graphs, detailed history, and intelligent notifications.

KEY FEATURES:

• Multi-Host Monitoring — Track Google DNS, Cloudflare, your router, or any custom IP/hostname
• Real-time Visualization — Live latency graphs with smooth animations
• Intelligent Notifications — 7 notification types: connection loss, high latency, recovery, degradation, intermittent issues, network changes, and internet outages
• Detailed History — Complete ping history table with timestamps and color-coded status
• Flexible Display Modes — Full interface (450x500) or compact mode (280x220) to save menu bar space
• Stay-on-Top Option — Floating window for monitoring while you work
• Data Export — Export ping history to CSV, JSON, or plain text for analysis
• Dual Ping Modes — ICMP for accuracy (Developer ID builds) or TCP/UDP for sandboxed environments (App Store)
• Privacy-Focused — All monitoring is local; no external servers, no telemetry, no data collection

PERFECT FOR:

Network administrators troubleshooting connectivity issues. Developers debugging API latency. Remote workers monitoring VPN stability. Gamers checking ping before matches. Anyone who needs reliable, accurate network monitoring.

TECHNICAL DETAILS:

PingScope supports true ICMP ping (when run outside the sandbox) and TCP/UDP simulation (when sandboxed for App Store distribution). All network monitoring is performed locally using macOS native frameworks — no external servers required. Configure ping intervals from 1 to 60 seconds. Supports both IPv4 and IPv6 hosts.

Download PingScope now and take control of your network monitoring.
```

**Character count:** ~1,450 / 4,000 (room to expand with testimonials, awards, or additional features)

### Keywords (100 chars max, comma-separated, no spaces)

**"ping,latency,network,monitor,icmp,uptime,status,connection,tcp,udp,menubar,utility,graph,statistics"** (97 chars)

**Keyword Strategy:**
- **Primary keywords:** ping, latency, network, monitor (high traffic, high relevance)
- **Technical keywords:** icmp, tcp, udp (low traffic, high intent — users who search these know what they want)
- **Use case keywords:** uptime, status, connection (medium traffic, broad appeal)
- **Feature keywords:** menubar, utility, graph, statistics (differentiate from generic network tools)

**Avoid:**
- Competitor names (SimplePing, iStat, etc.) — trademark violation
- Generic terms (app, mac, macos) — waste of space, already indexed
- Repeated words from app name (PingScope) — already indexed automatically

### Promotional Text (170 chars max)

**"Monitor multiple hosts with real-time graphs and 7 notification types. Supports ICMP, TCP, and UDP ping. Privacy-focused with local monitoring. Free on the App Store."** (169 chars)

**Strategy:**
- Highlight key differentiators (multi-host, 7 notifications, ICMP/TCP/UDP)
- Emphasize privacy (no data collection)
- Call out free pricing
- Update seasonally or for new features (this field is editable without new build)

## Export Compliance Determination

### Encryption Use Analysis

**Does PingScope use encryption?**
- YES — Uses HTTPS for checking internet connectivity (optional feature)
- YES — Uses TLS for secure connections (standard macOS frameworks)

**Is this encryption exempt?**
- YES — HTTPS/TLS via URLSession is standard encryption built into the OS
- YES — No proprietary or non-standard encryption algorithms
- YES — Qualifies for exemption under U.S. Export Administration Regulations

**Required Declaration:**

Add to Info.plist:
```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

**Rationale:** PingScope uses only standard encryption provided by macOS (HTTPS via URLSession). This is explicitly exempt from export compliance documentation upload requirements per Apple's guidelines.

**Export Compliance Documentation:** None required (exempt)

## Privacy Manifest Requirements

### PrivacyInfo.xcprivacy Content

**Data Collection:** NONE

**Network Access:**
- **Purpose:** Ping monitoring (ICMP, TCP, UDP)
- **Destination:** User-configured hosts (e.g., 8.8.8.8, 1.1.1.1, custom IPs)
- **Data Sent:** ICMP echo requests or TCP/UDP packets (no user data)
- **Data Received:** ICMP echo replies or TCP/UDP responses (latency only)

**Required Reason APIs Used:** NONE
- No access to user data
- No access to device identifiers
- No file timestamp APIs
- No system boot time APIs

**Third-Party SDKs:** NONE
- PingScope uses only Apple frameworks (SwiftUI, AppKit, Network.framework, SystemConfiguration)

**PrivacyInfo.xcprivacy Template:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyAccessedAPITypes</key>
    <array/>
</dict>
</plist>
```

**Privacy Nutrition Label (App Store Connect):**
- **Data Used to Track You:** None
- **Data Linked to You:** None
- **Data Not Linked to You:** None
- **Summary:** "PingScope does not collect any user data. All network monitoring is performed locally on your device."

## Sources

### Official Apple Documentation (HIGH Confidence)
- [Submitting to App Store](https://developer.apple.com/app-store/submitting/)
- [Screenshot Specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [Privacy Manifest Files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
- [Complying with Encryption Export Regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)
- [Age Ratings Values and Definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/)
- [App Store Categories and Discoverability](https://developer.apple.com/app-store/categories/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [App Store Search Optimization](https://developer.apple.com/app-store/search/)
- [TestFlight Overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

### Recent Updates (MEDIUM Confidence)
- [Apple App Store Submission Changes — April 2026](https://medium.com/@thakurneeshu280/apple-app-store-submission-changes-april-2026-5fa8bc265bbe) — Xcode 26 requirement starting April 28, 2026
- [Age Rating Updates (Jan 2026)](https://developer.apple.com/news/upcoming-requirements/?id=07242025a) — New age rating questionnaire deadline Jan 31, 2026
- [macOS App Entitlements Guide (Medium, Jan 2026)](https://medium.com/@info_4533/macos-app-entitlements-guide-b563287c07e1) — Network access entitlements for sandboxed apps

### Third-Party Resources (MEDIUM Confidence)
- [App Store Screenshot Guidelines 2026](https://theapplaunchpad.com/blog/app-store-screenshots-guidelines-in-2026)
- [14 Common Apple App Store Rejections](https://onemobile.ai/common-app-store-rejections-and-how-to-avoid-them/)
- [App Store Promotional Text Guide](https://www.shyftup.com/blog/a-complete-guide-app-store-promotional-text/)
- [App Store Descriptions Best Practices 2026](https://adapty.io/blog/app-store-description/)
- [App Store Keyword Optimization 2026](https://splitmetrics.com/blog/app-store-keyword-optimization/)

---
*Feature research for: App Store Submission (macOS)*
*Researched: 2026-02-16*
*Context: v2.0 milestone — v1.0 product features complete, focusing exclusively on App Store submission requirements*
