# Feature Research

**Domain:** WidgetKit ping monitoring widgets & cross-platform architecture
**Researched:** 2026-02-17
**Confidence:** HIGH

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Widget size variants (Small/Medium/Large) | WidgetKit standard, users expect all 3 sizes | MEDIUM | Each size needs layout adaptation. Small = single host, Medium = 3 hosts horizontal, Large = all hosts list |
| Real-time status display | Widgets exist to show current state at a glance | LOW | Already have data pipeline from main app, just need timeline updates |
| Visual status indicators | Color-coded dots are universal in network monitoring | LOW | Reuse existing status evaluation logic (green/yellow/red/gray) |
| Ping time display | Core value proposition of ping monitoring | LOW | Format existing ping time data for widget display |
| Update timestamps | Users need to trust data freshness | LOW | Standard WidgetKit timeline entry date display |
| Tap to open main app | Standard widget interaction pattern | LOW | Deep link using widgetURL modifier for small, Link views for medium/large |
| Shared data pipeline | Widget must show same data as main app | MEDIUM | App Group container already documented, needs implementation |
| Widget configuration name/description | Users see these in widget gallery | LOW | Static metadata in widget configuration |

### Differentiators (Competitive Advantage)

Features that set the product apart. Not required, but valuable.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Multi-host summary view | Glanceable network health across all monitored endpoints | MEDIUM | Most network monitors show single host. We can show Google + Cloudflare + Gateway in medium widget |
| Mini latency graph | Visual trend data in widget without opening app | HIGH | Small sparkline chart in medium/large widgets. Requires historical data aggregation and chart rendering |
| Intelligent refresh timing | Respect system widget budget while staying current | MEDIUM | Timeline provider with multiple entries vs single entry with refresh policy. 40-70 updates/day budget |
| Host-specific deep links | Tap widget to open app to specific host | MEDIUM | Use Link views with URL parameters to navigate to selected host |
| Graceful degradation | Widget shows useful info even when app isn't running | LOW | Use last-known-good data from shared container with staleness indicator |
| Platform-aware UI | Widget adapts to desktop vs Notification Center context | MEDIUM | Use widgetRenderingMode environment to detect full-color vs accented display |
| Statistics summary | Show min/avg/max ping in large widget | LOW | Reuse existing statistics calculation, format for widget display |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Real-time continuous updates | "I want to see every ping result" | Widget refresh budget is 40-70/day. Continuous updates = battery drain and budget exhaustion | Timeline with 5-minute intervals + app writes to shared container on every ping. Widget shows latest data within budget |
| Interactive controls in widget | "Let me start/stop pinging from widget" | Widgets are glanceable displays, not control panels. No button support in small widgets | Tap widget to open app settings. Keep widget read-only |
| Per-widget host selection | "Let me configure which host each widget shows" | Widget intents add significant complexity for marginal benefit | Small widget shows primary host, medium shows top 3, large shows all. User controls host priority in main app |
| Live Activities | "Show notifications as Live Activities" | Live Activities are for time-sensitive events (timers, sports, delivery). Ping monitoring is ambient awareness | Use standard widgets + existing notification system |
| Custom widget refresh interval | "Let me choose 1 second updates" | System controls widget budget. App can't override. Users misunderstand widget limitations | Document actual refresh behavior (timeline + shared data) in widget description |

## Feature Dependencies

```
WidgetKit Extension
    └──requires──> App Group Container Configuration
                       └──requires──> Shared Data Models

WidgetKit Extension
    └──requires──> Timeline Provider Implementation
                       └──requires──> Placeholder Data

Widget Deep Links
    └──requires──> Main App URL Handling
                       └──requires──> NavigationStack in Main App

Cross-Platform Architecture
    └──requires──> Platform UI Separation
                       └──requires──> Shared ViewModels

Cross-Platform Architecture
    └──enhances──> Future iOS/iPadOS Support

Mini Latency Graph
    └──requires──> Historical Data Aggregation
                       └──requires──> Shared Data Models with History

Host-Specific Deep Links
    └──requires──> Widget Deep Links (base feature)
```

### Dependency Notes

- **WidgetKit Extension requires App Group Container:** Widgets run in separate process. App Groups are the standard inter-process data sharing mechanism. Must configure entitlements and shared container ID.
- **Timeline Provider requires Placeholder Data:** WidgetKit calls placeholder(in:) synchronously for widget gallery. Must return immediately with sample data.
- **Widget Deep Links require Main App URL Handling:** Widget taps deliver URLs to app. App needs onOpenURL handler and navigation logic to route to specific views.
- **Cross-Platform Architecture requires Platform UI Separation:** macOS uses AppKit menu bar, iOS uses different navigation patterns. Need platform-specific UI wrappers around shared ViewModels.
- **Mini Latency Graph requires Historical Data Aggregation:** Current app stores full ping history. Widget needs summarized/bucketed data (last 20 pings?) to render mini sparkline efficiently.

## MVP Definition

### Launch With (v2.0)

Minimum viable WidgetKit + cross-platform support.

- [x] Small widget (single host, status dot, ping time) — Core value, simplest implementation
- [x] Medium widget (3 hosts horizontal) — Multi-host differentiator without complexity of graphs
- [x] Large widget (all hosts list) — Complete data, expected widget size
- [x] App Group container with shared data models — Required for widget to show live data
- [x] Timeline provider with reasonable refresh (5-15 min) — Balance freshness with budget
- [x] Basic deep links (widget tap opens app) — Expected interaction
- [x] Placeholder data for widget gallery — WidgetKit requirement
- [x] Platform UI separation (macOS-specific + shared layer) — Foundation for future cross-platform
- [x] Shared ViewModels extracted from macOS-specific code — Enables code reuse across platforms

### Add After Validation (v2.x)

Features to add once core widgets are working.

- [ ] Mini latency graph in medium/large widgets — Validates user interest in trend visualization
- [ ] Host-specific deep links — Add after confirming users tap widgets regularly
- [ ] Platform-aware rendering (widgetRenderingMode) — Polish after core functionality works
- [ ] Statistics summary in large widget — Nice-to-have enhancement
- [ ] Staleness indicators (show if data > 5 min old) — Adds trust after users adopt widgets

### Future Consideration (v3+)

Features to defer until product-market fit is established.

- [ ] iOS/iPadOS support — Requires App Store iOS build, testing across iPhone/iPad sizes
- [ ] Widget intents (user-configurable widgets) — Significant complexity, unclear demand
- [ ] Interactive widgets (iOS 17+) — Button support in widgets, limited use cases for ping monitoring
- [ ] Multiple widget types (separate widgets per host) — Adds clutter to widget gallery

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Small widget with status | HIGH | LOW | P1 |
| Medium widget with 3 hosts | HIGH | LOW | P1 |
| Large widget with all hosts | MEDIUM | LOW | P1 |
| App Group container setup | HIGH | LOW | P1 |
| Timeline provider implementation | HIGH | MEDIUM | P1 |
| Basic widget deep links | MEDIUM | LOW | P1 |
| Platform UI separation | HIGH | MEDIUM | P1 |
| Shared ViewModels | HIGH | MEDIUM | P1 |
| Mini latency graph | MEDIUM | HIGH | P2 |
| Host-specific deep links | LOW | MEDIUM | P2 |
| Platform-aware rendering | LOW | LOW | P2 |
| Statistics summary | LOW | LOW | P2 |
| Staleness indicators | MEDIUM | LOW | P2 |
| iOS/iPadOS support | HIGH | HIGH | P3 |
| Widget intents | LOW | HIGH | P3 |
| Interactive widgets | LOW | MEDIUM | P3 |

**Priority key:**
- P1: Must have for v2.0 launch (WidgetKit MVP)
- P2: Should have for v2.x (enhances core widgets)
- P3: Nice to have for v3+ (future platforms)

## Competitor Feature Analysis

| Feature | Network Utility Apps | System Monitor Widgets | Our Approach |
|---------|---------------------|------------------------|--------------|
| Widget sizes | Usually only 1-2 sizes | All 3 sizes standard | Support all 3 (small/medium/large) — table stakes |
| Multi-host display | Rare, usually single target | N/A (CPU/memory focus) | Medium widget shows 3 hosts — differentiator |
| Visual trends | Sometimes in large widget | Common (CPU graphs) | Defer mini graph to v2.x — validate demand first |
| Refresh frequency | Often unclear/inconsistent | 1-5 min common | Timeline with 5 min + shared data — balance freshness and budget |
| Deep links | Basic (open app) | Often to specific tab | Start basic, add host-specific in v2.x |
| Cross-platform | iOS-only or macOS-only | macOS-focused | Foundation for future iOS — strategic advantage |

## Widget-Specific Patterns & Best Practices

### Timeline Management

**Pattern:** Provide multiple timeline entries vs single entry with refresh policy

**Our Approach:**
- Single timeline entry with `.after(nextUpdateDate)` policy
- 5-minute refresh interval (well under 40-70/day budget)
- Main app writes to shared container on every ping result
- Widget reads latest data on each timeline refresh

**Rationale:** Ping data changes unpredictably. Can't pre-generate meaningful timeline. Single entry + frequent app writes = fresh data without complex timeline logic.

### Data Sharing Strategy

**Pattern:** App Group containers are standard for widget data sharing

**Our Approach:**
- App Group ID: `group.com.hadm.pingmonitor.shared` (already documented)
- JSON file: `pingdata.json` with array of host status objects
- Main app writes on every ping result (already updating for existing widget spec)
- Widget reads synchronously in timeline provider

**Rationale:** Simple, proven pattern. JSON serialization is straightforward. No complex database needed for small dataset (3-10 hosts).

### Glanceable Information Design

**Pattern:** Widgets show status, not controls. Color coding + minimal text.

**Our Approach:**
- Small: Single host, large status dot (16x16), ping time, host name
- Medium: 3 hosts side-by-side, smaller dots (12x12), abbreviated names
- Large: List of all hosts, tiny dots (8x8), full names, ping times right-aligned

**Color scheme:** Green (good <50ms), Yellow (slow 50-150ms), Red (poor >150ms), Gray (timeout)

**Rationale:** Users should understand status in <1 second glance. Color is fastest signal. Text is secondary.

### Widget Size Interaction Patterns

**Pattern:** Small widgets = single tap target. Medium/Large = multiple tap targets.

**Our Approach:**
- Small: `widgetURL` modifier, opens main app (no specific host)
- Medium: `Link` views per host, opens to specific host detail
- Large: `Link` views per host row, opens to specific host detail

**Rationale:** Small widget limited to single URL. Medium/Large can have multiple interactive zones using Link.

### Placeholder Data Requirements

**Pattern:** WidgetKit requires synchronous placeholder(in:) for widget gallery

**Our Approach:**
- Static sample data: Google (12.3ms, good), Cloudflare (8.7ms, good), Gateway (2.1ms, good)
- Representative of typical good network state
- No disk I/O, returns immediately

**Rationale:** Placeholder shows in widget gallery before user adds widget. Must be instant and look realistic.

### Platform-Aware Rendering

**Pattern:** Widgets adapt to desktop vs Notification Center context via environment

**Our Approach:**
- Check `widgetRenderingMode` environment variable
- `.fullColor`: Use full color palette (desktop widgets)
- `.accented`: Adapt to system accent color (Notification Center)

**Implementation:** Defer to P2. Both modes work without this, but accented mode integration is polish.

### Refresh Budget Management

**Pattern:** System limits widget updates to 40-70/day budget per widget

**Our Approach:**
- 5-minute timeline refresh = 288 potential updates/day
- System throttles to ~40-70 actual updates based on widget visibility and user interaction
- App writes to shared container on every ping (5-15 sec) = data always fresh
- Widget shows latest data within budget constraints

**Rationale:** We can't control budget, but we can ensure data is fresh whenever widget does refresh.

## Cross-Platform Architecture Patterns

### Platform UI Separation

**Pattern:** Platform-specific UI wrappers around shared business logic

**Our Approach:**
```
Sources/
  PingScope/              # Shared code (models, services, view models)
  PingScope-macOS/        # macOS-specific (AppDelegate, MenuBar)
  PingScope-iOS/          # Future: iOS-specific (scenes, tab bar)
  PingScope-Shared/       # Shared SwiftUI views
  PingMonitorWidget/      # Widget extension
```

**Rationale:** SwiftUI views can be shared. Platform integration (menu bar, navigation) cannot. Separate targets for each platform.

### Shared ViewModels Pattern

**Pattern:** MVVM with platform-agnostic ViewModels

**Our Approach:**
- Extract `PingViewModel` to shared code (already exists)
- Extract `HostListViewModel` to shared code (already exists)
- Create `StatusPopoverViewModel` for shared display logic
- macOS wraps in menu bar popover, iOS wraps in sheet/tab

**Rationale:** Business logic and state management is identical across platforms. Only presentation differs.

### Conditional Compilation

**Pattern:** Use `#if os(macOS)` / `#if os(iOS)` sparingly for platform differences

**Our Approach:**
- Prefer separate files per platform over #if blocks
- Use #if only for small API differences (NSImage vs UIImage)
- Keep shared code truly shared (no platform checks)

**Rationale:** Separate files are easier to maintain and test than scattered #if blocks.

### Platform-Specific Features

**Pattern:** Features available on one platform but not others

**Our Approach:**
- Menu bar integration: macOS only
- ICMP ping: macOS non-sandboxed only
- Today widget: iOS only (if we add iOS support)
- Desktop widgets: macOS only

**Rationale:** Embrace platform differences. Don't force UI patterns across platforms.

## Complexity Assessment

### Simple (1-2 days)

- Widget size variants layout (3 SwiftUI views)
- Real-time status display (reuse existing data models)
- Visual status indicators (reuse existing color logic)
- Ping time display (format existing data)
- Update timestamps (TimelineEntry.date)
- Basic widget deep links (widgetURL modifier)
- Widget configuration metadata (static strings)
- Placeholder data (static sample data)

### Moderate (3-5 days)

- App Group container setup (entitlements, shared container access)
- Timeline provider implementation (load data, create timeline, refresh policy)
- Shared data pipeline (write from app, read from widget)
- Platform UI separation (restructure Xcode project, separate targets)
- Shared ViewModels extraction (refactor existing VMs to be platform-agnostic)
- Host-specific deep links (URL parameters, navigation routing)
- Platform-aware rendering (environment detection, color adaptation)

### Complex (5+ days)

- Mini latency graph (data aggregation, chart rendering, layout in widget constraints)
- Full iOS/iPadOS support (new target, testing, App Store submission)
- Widget intents (intent definition, configuration UI, dynamic widget)

## Sources

- [WidgetKit | Apple Developer Documentation](https://developer.apple.com/documentation/widgetkit)
- [Developing a WidgetKit strategy | Apple Developer Documentation](https://developer.apple.com/documentation/widgetkit/developing-a-widgetkit-strategy)
- [Keeping a widget up to date | Apple Developer Documentation](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
- [TimelineProvider | Apple Developer Documentation](https://developer.apple.com/documentation/widgetkit/timelineprovider)
- [Supporting additional widget sizes | Apple Developer Documentation](https://developer.apple.com/documentation/widgetkit/supporting-additional-widget-sizes)
- [Linking to specific app scenes from your widget | Apple Developer Documentation](https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity)
- [Building a Unified Multiplatform Architecture with SwiftUI](https://medium.com/@mrhotfix/building-a-unified-multiplatform-architecture-with-swiftui-ios-macos-and-visionos-6214b307466a)
- [Improving multiplatform SwiftUI code · Jesse Squires](https://www.jessesquires.com/blog/2023/03/23/improve-multiplatform-swiftui-code/)
- [Setting up a multi-platform SwiftUI project](https://blog.scottlogic.com/2021/03/04/Multiplatform-SwiftUI.html)
- [Add and customize widgets on Mac - Apple Support](https://support.apple.com/guide/mac-help/add-and-customize-widgets-mchl52be5da5/mac)
- [How to Update or Refresh a Widget? - Swift Senpai](https://swiftsenpai.com/development/refreshing-widget/)
- [Understanding the Limitations of Widgets Runtime in iOS App Development](https://medium.com/@telawittig/understanding-the-limitations-of-widgets-runtime-in-ios-app-development-and-strategies-for-managing-a3bb018b9f5a)
- [WidgetKit refresh rate limitations discussion - Apple Developer Forums](https://developer.apple.com/forums/thread/654331)

---
*Feature research for: WidgetKit ping monitoring widgets & cross-platform architecture*
*Researched: 2026-02-17*
