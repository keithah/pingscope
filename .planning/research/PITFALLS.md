# Pitfalls Research

**Domain:** Adding WidgetKit widgets and cross-platform architecture to existing macOS network monitoring app
**Researched:** 2026-02-17
**Confidence:** MEDIUM-HIGH

## Critical Pitfalls

### Pitfall 1: Widget Update Budget Exhaustion

**What goes wrong:**
Attempting to update widgets too frequently (every few minutes) causes the system to stop updating your widget entirely. WidgetKit allocates a daily budget of 40-70 refreshes per widget, corresponding to updates every 15-60 minutes. Exceeding this budget results in widgets showing stale data indefinitely.

**Why it happens:**
Developers assume widgets work like menu bar apps with continuous updates. Network monitoring tools naturally want real-time data, leading to timeline providers that request updates every 1-5 minutes. The system silently refuses these updates once budget is exhausted, with no error surfaced to the user.

**How to avoid:**
- Design widgets for "glanceable summaries" (last known status, trend over time) not real-time monitoring
- Use timeline entries for predictable changes (hourly summaries, daily patterns)
- Provide 5-10 timeline entries at once instead of requesting frequent refreshes
- Space timeline entries at least 5 minutes apart minimum (15+ minutes recommended)
- Main app remains source of truth for real-time monitoring; widgets show summary

**Warning signs:**
- Timeline entry count > 400 (causes widget to stop updating)
- `TimelineReloadPolicy.atEnd` with < 15 minute intervals
- Network calls in `getTimeline()` that fetch every refresh
- Widget shows stale data after first day of use
- Development widgets work fine, production widgets freeze

**Phase to address:**
Phase 1 (Widget Foundation) - Set update budget constraints during initial widget architecture design

---

### Pitfall 2: App Groups Team ID Prefix Mismatch (macOS Sequoia)

**What goes wrong:**
Widget extension cannot access shared data from main app despite App Groups being configured. macOS Sequoia requires App Group identifiers to use Team ID prefix (e.g., `TEAMID.com.hadm.pingscope.shared`) instead of traditional `group.` prefix used on iOS. Using iOS-style `group.` prefix causes silent access failures on macOS.

**Why it happens:**
iOS and macOS use different App Group naming conventions. Multiplatform projects copying iOS App Group configuration to macOS targets fail without clear error messages. Xcode project templates don't warn about this platform difference, and runtime errors are cryptic ("permission denied" or silent nil values).

**How to avoid:**
- macOS: Use `<TEAMID>.com.hadm.pingscope.shared` format
- iOS: Continue using `group.com.hadm.pingscope.shared` format
- Conditional entitlements files per platform if supporting both
- Test shared UserDefaults access immediately after setup
- Verify provisioning profiles contain correct App Group format for target platform

**Warning signs:**
- `UserDefaults(suiteName:)` returns nil in widget but works in main app
- `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` returns nil
- Widget shows default/empty state despite main app writing data
- Works in iOS target but fails on macOS target in multiplatform project

**Phase to address:**
Phase 1 (Widget Foundation) - Configure App Groups correctly before any data sharing implementation

---

### Pitfall 3: Network Calls Blocking Widget Timeline Rendering

**What goes wrong:**
Widgets fail to load or show "Unable to Load Widget" error because `getTimeline()` attempts synchronous or long-running network requests. WidgetKit has strict time limits (10-15 seconds) for timeline generation. Network ping operations to multiple hosts easily exceed this budget, causing the widget extension to be killed by the system.

**Why it happens:**
Timeline providers are called on background threads with strict execution limits. Developers port menu bar app logic directly to widgets, attempting to ping 5-10 hosts per refresh. DNS resolution alone can take 5+ seconds per host on slow networks. Timeouts compound—pinging 10 hosts with 3-second timeouts = 30 seconds minimum, far exceeding widget budget.

**How to avoid:**
- Main app performs network monitoring and writes results to App Group container
- Widget reads pre-computed data from shared storage (UserDefaults or file)
- Widget shows "last known status" not "current status"
- If network calls absolutely required: limit to single host, 2-second total timeout
- Use background URL session with `onBackgroundURLSessionEvents` modifier for async updates
- Gracefully degrade: show cached data if fresh data unavailable

**Warning signs:**
- "Unable to Load Widget" shown instead of widget content
- Timeline provider takes > 5 seconds in local testing
- Widget works on fast Wi-Fi but fails on cellular/VPN
- Logs show widget extension terminated by system
- Network calls using `await` directly in `getTimeline()` method

**Phase to address:**
Phase 1 (Widget Foundation) - Design data sharing architecture with main app doing network work

---

### Pitfall 4: Premature Cross-Platform Abstraction (macOS/iOS)

**What goes wrong:**
Codebase becomes littered with `#if os(macOS)` conditionals throughout view models, services, and views. Shared abstractions force platform-specific features into lowest common denominator. macOS-specific capabilities (MenuBarExtra, ICMP ping) and iOS-specific features (StandBy mode, Lock Screen widgets) become awkward to express. Maintenance burden increases as every feature requires platform branching.

**Why it happens:**
Developers assume "cross-platform" means "share all code." Early decisions to share ViewModels between macOS and iOS lead to conditional logic creep. SwiftUI's "learn once, apply anywhere" promise is misinterpreted as "write once, run everywhere." Platform differences (window management on macOS, navigation on iOS) create pressure to abstract, leading to overly generic code that serves neither platform well.

**How to avoid:**
- Share models and business logic (services, network layer, data types)
- Keep ViewModels platform-specific (MenuBarViewModel for macOS, AppViewModel for iOS)
- Share leaf views where design is naturally identical (HostRowView, latency graphs)
- Accept that root views (MenuBarExtra vs NavigationStack) will be different
- Use file organization: `Views/macOS/`, `Views/iOS/`, `Views/Shared/`
- Prefer runtime checks over compile-time conditionals for feature availability

**Warning signs:**
- More than 3 `#if os()` checks in a single file
- ViewModels with `#if os()` in method implementations
- Services with platform-specific initialization logic
- Shared view with platform-specific modifier chains
- "Platform" parameter passed through multiple layers
- Comments explaining "this is for macOS but not iOS"

**Phase to address:**
Phase 2 (Cross-Platform Architecture) - Establish platform separation boundaries before iOS implementation

---

### Pitfall 5: Widget Process Isolation State Synchronization

**What goes wrong:**
Main app and widget show conflicting data. Widget displays "All Hosts Up" while menu bar shows "3 Hosts Down." User changes settings in main app but widget doesn't reflect changes until device restart. State drift occurs because widget extension and main app are separate processes with independent memory spaces.

**Why it happens:**
Widgets run in separate processes and don't receive automatic updates when main app modifies shared data. `WidgetCenter.shared.reloadTimelines(ofKind:)` must be explicitly called after every data change, but developers forget or call it too frequently. UserDefaults writes don't trigger widget refreshes. No built-in pub/sub mechanism exists between processes.

**How to avoid:**
- Call `WidgetCenter.shared.reloadTimelines(ofKind: "PingWidget")` after every UserDefaults write affecting widget data
- Wrap UserDefaults updates in helper that automatically triggers widget reload
- Don't reload on every ping result (would exhaust budget); reload on state changes only
- Widget shows "last update time" to signal data freshness
- Design tolerance: "Widget may be up to 15 minutes stale" is acceptable

**Warning signs:**
- Widget shows old host list after adding host in main app
- Threshold changes in settings don't appear in widget
- Widget "freezes" on specific value until device reboot
- Manual reload (long-press widget) shows correct data
- Widget and menu bar never agree on status

**Phase to address:**
Phase 1 (Widget Foundation) - Implement reload triggers from the start

---

### Pitfall 6: @Observable Minimum OS Version Lock-In

**What goes wrong:**
Adopting `@Observable` for shared ViewModels forces minimum macOS 14.0 and iOS 17.0, cutting off macOS Ventura (13.x) users who represent significant user base for menu bar utilities. If PingScope v1.0 supports macOS 13.0 but v2.0 requires 14.0, App Store update alienates existing users. Cross-platform ViewModels can't be shared if iOS target needs to support iOS 16 for wider device compatibility.

**Why it happens:**
`@Observable` is only available in macOS 14+, iOS 17+. Developers see it as "modern SwiftUI best practice" and adopt it immediately for new code. Cross-platform tutorials use `@Observable` without mentioning version constraints. Once adopted throughout ViewModels, reverting to `ObservableObject` is high-friction refactor.

**How to avoid:**
- PingScope v1.0 uses `ObservableObject` → v2.0 should continue using it for consistency
- If adopting `@Observable`, clearly document minimum version bump
- Use Point-Free's Perception library to backport `@Observable` to older OS versions if needed
- Delay `@Observable` adoption until minimum iOS 17/macOS 14 is acceptable
- Keep existing `ObservableObject` code for v2.0 cross-platform work

**Warning signs:**
- Xcode shows "requires macOS 14.0 or newer" in Package.swift
- App Store Connect rejects build for increasing minimum version
- User reviews complain "update not available on my Mac"
- iOS target must support iOS 16 but macOS uses `@Observable`
- Shared ViewModels mix `@Observable` and `ObservableObject`

**Phase to address:**
Phase 0 (Research/Planning) - Decide minimum OS versions before any cross-platform implementation starts

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Sharing single ViewModel across menu bar and widget | Less code duplication | ViewModel bloated with conditionals for each UI context, widget-specific logic pollutes menu bar code | Never - create `MenuBarViewModel` and `WidgetDataProvider` |
| Using `group.` prefix for macOS App Groups | Works on iOS, seems consistent | Silent failures on macOS Sequoia, cryptic debugging | Never on macOS - use Team ID prefix |
| Network calls in widget `getTimeline()` | Direct access to fresh data | Widget fails to load, battery drain, budget exhaustion | Only for single-host, < 2 second total timeout |
| Frequent `WidgetCenter.reloadTimelines()` calls | Widget feels responsive | Update budget exhausted, widget stops updating after hours | Only on user-initiated state changes (add host, change settings) |
| `#if os()` conditionals in ViewModels | Quick fix for platform differences | Unmaintainable conditional sprawl, hard to test | Only in leaf views for minor UI tweaks |
| Copying entire menu bar view hierarchy to iOS | Fast path to "working" iOS app | Awkward iOS UX, doesn't leverage platform strengths | Never - redesign for platform idioms |
| StaticConfiguration for all widgets | Simpler implementation | No user customization (can't select which host to show) | Acceptable for MVP, plan IntentConfiguration for v2.1 |

## Integration Gotchas

Common mistakes when connecting widget extension to main app.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| App Groups setup | Assuming `group.` prefix works on macOS | Use Team ID prefix on macOS: `<TEAMID>.com.hadm.pingscope` |
| UserDefaults initialization | Using `UserDefaults.standard` in widget | Use `UserDefaults(suiteName: "group-id")` in both app and widget |
| Shared data format | Writing Swift types directly to UserDefaults | Use Codable JSON or plist-compatible types for reliability |
| Widget reload triggering | Hoping widgets auto-update when data changes | Explicitly call `WidgetCenter.shared.reloadTimelines()` after writes |
| Timeline entry limits | Providing hundreds of timeline entries | Limit to 10-20 entries, use `TimelineReloadPolicy.after(date)` |
| Resource bundle access | Assuming app's asset catalog available in widget | Add assets to widget extension target or use shared asset catalog |

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Timeline entry per ping result | Widget updates every 30 seconds initially | Widget shows summary entries (hourly status, not per-ping) | After 40-70 updates daily (budget exhausted) |
| Encoding full ping history in UserDefaults | Recent results load instantly | Limit to last 100 results or 24 hours, use file storage for archives | When UserDefaults > 1 MB (widget load slow) |
| Pinging all hosts in widget timeline provider | Works fine with 2-3 hosts | Widget reads pre-computed status from app, never pings | With 5+ hosts or slow DNS (widget fails to load) |
| Separate timeline per widget instance | Each widget shows different host | Single timeline with multiple entries, use IntentConfiguration | With 3+ widgets (3x budget consumption) |
| Detailed graphs in small widget | Looks impressive in previews | Use simple status indicators (color, single number) in small size | Widget too small to read details, visual clutter |

## Security Mistakes

Domain-specific security issues beyond general web security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Storing network credentials in shared UserDefaults | Widget has same sandbox, credentials exposed to extension | Don't implement authentication for v2.0; if needed, use Keychain with access groups |
| Logging ping results to file without size limits | Widget can write unbounded data to shared container | Implement log rotation, 10 MB max file size, 7-day retention |
| Exposing internal host addresses in widget | Lock screen widgets visible without device unlock | Widget shows host name only, not IP/address (optional privacy setting) |
| No rate limiting on widget reload calls | Malicious actor could trigger unlimited reloads | Rate limit: max 1 reload per 60 seconds, debounce rapid calls |

## UX Pitfalls

Common user experience mistakes in this domain.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Widget shows "N/A" without explanation | User thinks widget is broken | "Updated 5m ago" timestamp, "Tap to open app" hint |
| Identical small/medium/large widgets | User adds large widget but sees same content as small | Small = worst host, Medium = worst 3 hosts, Large = graph + summary |
| Widget updates every 15 minutes but shows live timestamp | "Updated 2s ago" but actually stale data | Show last refresh time, not current time |
| No visual difference between "monitoring paused" and "all hosts up" | User can't tell if monitoring is working | Distinct icon/color for paused state vs healthy state |
| Widget configuration requires app open | Extra friction to customize widget | Use IntentConfiguration for in-widget host selection |
| Menu bar shows "ICMP" option on Mac but widget says "Unavailable" | Confusing capability mismatch | Widget shows only TCP/UDP (sandbox-safe methods) with footnote |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Widget data sharing:** Often missing explicit `WidgetCenter.reloadTimelines()` calls — verify widget updates when app changes data
- [ ] **Timeline provider timeouts:** Often missing timeout handling for network calls — verify `getTimeline()` completes < 5 seconds even on slow network
- [ ] **App Groups on macOS:** Often using iOS `group.` prefix — verify Team ID prefix used in macOS target entitlements
- [ ] **Widget budget tracking:** Often missing monitoring of update frequency — verify widget continues updating after 24+ hours in production
- [ ] **Cross-platform ViewModels:** Often sharing ViewModels that shouldn't be shared — verify platform-specific ViewModels for menu bar vs iOS navigation
- [ ] **Sandbox detection in widget:** Often assuming widget runs in same sandbox as app — verify widget code handles sandbox restrictions independently
- [ ] **Widget placeholder/snapshot:** Often using live data in placeholder/snapshot — verify static, fast-loading placeholder UI
- [ ] **Small widget readability:** Often cramming too much info — verify legible at actual widget size on device (not Xcode canvas)
- [ ] **Background URL session configuration:** Often missing `onBackgroundURLSessionEvents` handler — verify async network updates work when app backgrounded

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Widget update budget exhausted | LOW | Change timeline policy to `.after(Date() + 20 minutes)`, remove frequent reload calls, submit update |
| App Groups misconfigured | LOW | Fix Team ID prefix in entitlements, regenerate provisioning profile, reinstall app |
| Network calls blocking timeline | MEDIUM | Refactor to read from UserDefaults, add background data sync in main app, submit update |
| Premature abstraction sprawl | HIGH | Create platform-specific ViewModels, move shared code to services layer, gradual refactor over multiple releases |
| Widget/app state drift | LOW | Implement reload wrapper around UserDefaults writes, audit all state-changing code paths |
| @Observable version lock-in | HIGH | Revert to ObservableObject (breaking change) or accept minimum version increase and document in release notes |
| Timeline entry limit exceeded | LOW | Reduce entry count to 10-20, use scheduled refreshes instead of upfront entries |
| Widget shows stale data | LOW-MEDIUM | Add "last updated" timestamp to UI, implement user-initiated refresh (iOS 17+ interactive widgets) |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Widget update budget exhaustion | Phase 1: Widget Foundation | Monitor widget updates over 48-hour period, verify update frequency stays within budget |
| App Groups Team ID mismatch | Phase 1: Widget Foundation | Widget reads shared UserDefaults successfully on first launch, no nil values |
| Network calls blocking timeline | Phase 1: Widget Foundation | Timeline provider completes in < 2 seconds with simulated slow network |
| Premature cross-platform abstraction | Phase 2: Cross-Platform Architecture | `#if os()` count < 10 in entire codebase, platform ViewModels cleanly separated |
| Widget/app state drift | Phase 1: Widget Foundation | Add host in app → widget reflects change within 30 seconds |
| @Observable version lock-in | Phase 0: Planning | Minimum version decision documented, existing ObservableObject retained |
| Timeline entry limit exceeded | Phase 1: Widget Foundation | Timeline provides max 20 entries, verify widget loads successfully |
| macOS vs iOS widget differences | Phase 1: Widget Foundation | macOS desktop widgets tested separately from iOS home screen widgets |
| Background URLSession misconfiguration | Phase 1: Widget Foundation (if async needed) | Background session completion handler called, delegate methods fire |
| Shared ViewModel pollution | Phase 2: Cross-Platform Architecture | MenuBarViewModel has zero iOS-specific code, iOS ViewModel has zero macOS code |
| IntentConfiguration complexity | Phase 3: Widget Enhancement (future) | Start with StaticConfiguration, validate user need before adding configurability |

## Widget-Specific Development Workflow Gotchas

| Issue | Impact | Solution |
|-------|--------|----------|
| Widget previews don't show App Group data | Previews always show placeholder, can't test real data flow | Test on device/simulator, use `.previewContext(WidgetPreviewContext(family: .systemMedium))` |
| Widget extension doesn't rebuild when app code changes | Stale widget after modifying shared code | Clean build folder, or manually rebuild widget scheme |
| Xcode "Unable to Install" widget | Widget installs to simulator but not device | Verify provisioning profile includes widget bundle ID, rebuild widget target |
| Widget shows old timeline after code change | WidgetKit caches timeline entries aggressively | Remove widget from desktop, re-add, or restart device |
| Timeline provider called excessively during development | Xcode debugger triggers extra timeline requests | Normal; production uses system-controlled schedule |
| Widget won't launch in debugger | "Waiting to attach" hangs indefinitely | Select widget scheme, choose widget process from Debug > Attach to Process after adding to desktop |

## Cross-Platform Architecture-Specific Pitfalls

| Pitfall | Symptom | Prevention |
|---------|---------|------------|
| AppKit/UIKit type conflicts | `NSView` vs `UIView` compile errors in shared code | Use `typealias PlatformView = NSView / UIView`, or keep UI code unshared |
| Conditional import sprawl | `#if canImport(AppKit)` throughout files | Limit to platform abstraction layer, not scattered in features |
| SwiftUI modifier availability | `.navigationBarTitle()` doesn't exist on macOS | Check API availability, use `#available(iOS 13, *)` or platform-specific views |
| Build scheme confusion | Building iOS scheme includes macOS code, linker errors | Separate schemes per platform, verify target membership |
| Asset catalog platform variants | Icon works on macOS but missing on iOS | Create platform-specific asset catalogs or use universal assets |
| Different navigation paradigms | iOS NavigationStack vs macOS window-based navigation | Accept platform differences, don't force macOS into NavigationStack |

## Sources

### Official Apple Documentation
- [Keeping a widget up to date | Apple Developer Documentation](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
- [Making network requests in a widget extension | Apple Developer Documentation](https://developer.apple.com/documentation/widgetkit/making-network-requests-in-a-widget-extension)
- [Developing a WidgetKit strategy | Apple Developer Documentation](https://developer.apple.com/documentation/WidgetKit/Developing-a-WidgetKit-strategy)
- [Making a configurable widget | Apple Developer Documentation](https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget)
- [App Groups Entitlement | Apple Developer Documentation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups)

### Apple Developer Forums (HIGH Confidence)
- [WidgetKit refresh policy | Apple Developer Forums](https://developer.apple.com/forums/thread/657518)
- [Sharing UserDefaults with widgets | Apple Developer Forums](https://developer.apple.com/forums/thread/651799)
- [macOS Widgets won't launch with app group set](https://developer.apple.com/forums/thread/758478)
- [Invalid code signing entitlements with app group on macOS](https://developer.apple.com/forums/thread/775022)

### Community Articles (MEDIUM Confidence)
- [WidgetKit. Some pitfalls I found. | by Alex Moiseenko | techpro.studio | Medium](https://medium.com/techpro-studio/widgetkit-some-pitfalls-i-found-55a404b2d8df)
- [Understanding the Limitations of Widgets Runtime in iOS App Development | by Tela Wittig | Medium](https://medium.com/@telawittig/understanding-the-limitations-of-widgets-runtime-in-ios-app-development-and-strategies-for-managing-a3bb018b9f5a)
- [How to Update or Refresh a Widget? - Swift Senpai](https://swiftsenpai.com/development/refreshing-widget/)
- [Sharing data with a Widget](https://useyourloaf.com/blog/sharing-data-with-a-widget/)
- [Improving multiplatform SwiftUI code · Jesse Squires](https://www.jessesquires.com/blog/2023/03/23/improve-multiplatform-swiftui-code/)
- [Cross-platform SwiftUI | Bekk Christmas](https://www.bekk.christmas/post/2023/20/cross-platform-swiftui)
- [Building Cross-Platform macOS and iOS Image Filter SwiftUI App | Xcoding with Alfian](https://www.alfianlosari.com/posts/building-cross-platform-swiftui-ios-macos-app/)
- [Using compiler directives in Swift | Swift by Sundell](https://www.swiftbysundell.com/articles/using-compiler-directives-in-swift/)
- [@Observable in SwiftUI for iOS, macOS and watchOS](https://swiftprogramming.com/observable-swiftui/)
- [Perception: A back-port of @Observable](https://www.pointfree.co/blog/posts/129-perception-a-back-port-of-observable)
- [WidgetKit: Get started making widgets for macOS](https://appleinsider.com/inside/xcode/tips/getting-started-with-widgetkit-making-your-first-macos-widget)

### Technical References (MEDIUM Confidence)
- [Do Widgets Take Up Battery? | TheBatteryTips.com](https://thebatterytips.com/battery-specifications/do-widgets-take-up-battery/)
- [How to Fetch and Show Remote Data on a Widget? - Swift Senpai](https://swiftsenpai.com/development/widget-load-remote-data/)
- [Optimizing iOS Widget network calls with temporary caching | by Jaeho Yoo | Medium](https://medium.com/@Jager-yoo/optimizing-ios-widget-network-calls-with-temporary-caching-e32c01570a5c)

---

## Confidence Assessment

| Area | Level | Rationale |
|------|-------|-----------|
| Widget update budget limits | HIGH | Multiple official Apple sources and developer forum confirmation of 40-70 daily budget |
| App Groups Team ID requirement (macOS Sequoia) | HIGH | Official Apple Developer Forums thread confirming Team ID prefix requirement |
| Network call limitations in widgets | HIGH | Official Apple documentation on timeline provider constraints |
| Cross-platform abstraction patterns | MEDIUM-HIGH | Strong community consensus, multiple architecture articles agree on principles |
| @Observable platform availability | HIGH | Official Apple documentation clearly states macOS 14+, iOS 17+ requirement |
| Timeline entry limits | MEDIUM | Community reported "400 entry limit," not in official docs but widely confirmed |
| Widget budget exhaustion recovery | HIGH | Official WidgetKit documentation covers reload policies and timeline management |
| macOS vs iOS widget behavioral differences | MEDIUM | Community observations and Apple Insider article, less official documentation |

---

## Open Questions for Implementation

1. **Widget family prioritization:** Which sizes to implement first (small, medium, large)? Recommendation: Start with medium (most common), then small, defer large to later phase.

2. **IntentConfiguration timing:** Should v2.0 MVP use StaticConfiguration (simpler) or IntentConfiguration (user can pick host)? Recommendation: StaticConfiguration for MVP showing "worst host," add IntentConfiguration in v2.1.

3. **iOS timeline differences:** Do iOS Lock Screen widgets have different budget constraints than Home Screen widgets? Requires investigation during iOS implementation phase.

4. **Background URL session necessity:** Can main app's background refresh handle all data updates, or do widgets need independent background sessions? Recommendation: Start with main app handling all updates, add background sessions only if needed.

5. **Minimum version trade-off:** Accept macOS 13 limitation (keep `ObservableObject`) or bump to macOS 14 (use `@Observable`)? Recommendation: Keep macOS 13 support for v2.0, defer `@Observable` to v3.0.

6. **Widget refresh on host addition:** Should adding a host trigger immediate widget reload, or wait for next scheduled update? Recommendation: Immediate reload on user-initiated changes (add/remove host, change settings), not on ping results.

7. **Shared container size monitoring:** How to detect when App Group container approaches size limits? Recommendation: Log file size on write, warn if > 5 MB, implement cleanup if > 10 MB.

---

*Pitfalls research for: WidgetKit widgets and cross-platform architecture for macOS network monitoring app*
*Researched: 2026-02-17*
