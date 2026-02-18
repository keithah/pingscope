# Architecture Research: WidgetKit & Cross-Platform Integration

**Domain:** macOS menu bar app with WidgetKit widgets and cross-platform preparation
**Researched:** 2026-02-17
**Confidence:** HIGH

## Current Architecture Analysis

### Existing System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Presentation Layer                      │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │   AppKit     │  │   SwiftUI    │  │  Settings    │       │
│  │  Integration │  │    Views     │  │   Window     │       │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘       │
│         │                 │                  │               │
├─────────┴─────────────────┴──────────────────┴───────────────┤
│                      ViewModel Layer                         │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │  MenuBarVM   │  │  DisplayVM   │  │ HostListVM   │       │
│  │ @MainActor   │  │ @MainActor   │  │ @MainActor   │       │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘       │
│         │                 │                  │               │
├─────────┴─────────────────┴──────────────────┴───────────────┤
│                      Coordination Layer                      │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐    │
│  │              AppDelegate (@MainActor)                │    │
│  │  - Owns services, view models, runtime               │    │
│  │  - Coordinates lifecycle and data flow               │    │
│  └─────────────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────────┤
│                      Service Layer                           │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐     │
│  │HostStore │  │PingService│ │PingScheduler│ │NotificationSvc│
│  │  (actor) │  │  (actor)  │ │  (actor)   │ │  (@MainActor) │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘     │
├─────────────────────────────────────────────────────────────┤
│                      Data Layer                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │              UserDefaults (Standard)                  │    │
│  │  - Host configurations                                │    │
│  │  - Display preferences                                │    │
│  │  - Notification preferences                           │    │
│  └──────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### Current Component Responsibilities

| Component | Responsibility | Implementation |
|-----------|---------------|----------------|
| AppDelegate | Lifecycle coordination, owns all services and view models | @MainActor singleton |
| MenuBarViewModel | Menu bar state, latency display, status evaluation | @MainActor ObservableObject |
| DisplayViewModel | Popover content, host selection, graph/history visibility | @MainActor ObservableObject |
| HostListViewModel | Host list, add/edit/delete host operations | @MainActor ObservableObject |
| HostStore | Persist and load hosts, default host management | actor with UserDefaults |
| PingService | Execute pings (TCP/UDP/ICMP), measure latency | actor with Network.framework |
| PingScheduler | Schedule pings across hosts, manage concurrency | actor coordinating PingService |
| NotificationService | Evaluate alerts, send system notifications | @MainActor with UserNotifications |

### Current File Structure

```
Sources/PingScope/
├── App/
│   ├── PingMonitorApp.swift          # SwiftUI app entry point
│   ├── AppDelegate.swift             # Main coordinator
│   └── DisplayContentFactory.swift   # Popover content factory
├── ViewModels/
│   ├── MenuBarViewModel.swift        # @MainActor, menu bar state
│   ├── DisplayViewModel.swift        # @MainActor, display state
│   ├── HostListViewModel.swift       # @MainActor, host list state
│   ├── StatusPopoverViewModel.swift  # @MainActor, popover state
│   └── AddHostViewModel.swift        # @MainActor, add host form
├── Views/
│   ├── StatusPopoverView.swift       # SwiftUI popover view
│   ├── HostListView.swift            # SwiftUI host list
│   ├── DisplayGraphView.swift        # SwiftUI latency graph
│   └── Settings/                     # Settings views
├── MenuBar/
│   ├── StatusItemController.swift    # NSStatusItem/AppKit integration
│   ├── MenuBarRuntime.swift          # Menu bar state coordination
│   ├── DisplayModeCoordinator.swift  # Popover/window coordination
│   └── [Stores].swift                # Preference stores (UserDefaults)
├── Services/
│   ├── PingService.swift             # actor, Network.framework
│   ├── PingScheduler.swift           # actor, scheduling
│   ├── HostStore.swift               # actor, persistence
│   ├── NotificationService.swift     # @MainActor, alerts
│   └── [Other services]
├── Models/
│   ├── Host.swift                    # Sendable, Codable
│   ├── PingResult.swift              # Sendable, Equatable
│   ├── GlobalDefaults.swift          # Configuration
│   └── [Other models]
└── Utilities/
    └── ICMPPacket.swift              # ICMP packet construction
```

## WidgetKit Integration Architecture

### Widget Extension Overview

```
┌──────────────────────────────────────────────────────────────┐
│                        Main App Target                        │
│  ┌────────────────┐         ┌────────────────┐               │
│  │   AppDelegate  │ ─────── │  Widget Center │               │
│  │                │  reload │                │               │
│  └────────────────┘  calls  └────────────────┘               │
│           │                                                   │
│           │ writes                                            │
│           ↓                                                   │
│  ┌────────────────────────────────────────────────────┐      │
│  │      App Group Shared Container                    │      │
│  │  ┌──────────────────────────────────────────┐      │      │
│  │  │ UserDefaults(suiteName: "group.*.app")   │      │      │
│  │  │  - Latest ping results                   │      │      │
│  │  │  - Host configurations                   │      │      │
│  │  │  - Display preferences                   │      │      │
│  │  └──────────────────────────────────────────┘      │      │
│  └────────────────────────────────────────────────────┘      │
│           ↑                                                   │
│           │ reads                                             │
└───────────┼───────────────────────────────────────────────────┘
            │
┌───────────┼───────────────────────────────────────────────────┐
│           │           Widget Extension Target                 │
│           │                                                   │
│  ┌────────┴──────────────────────────────────────┐            │
│  │        WidgetKit Timeline Provider            │            │
│  │  ┌──────────────────────────────────────┐    │            │
│  │  │ PingScopeWidgetProvider              │    │            │
│  │  │  : TimelineProvider                  │    │            │
│  │  │                                      │    │            │
│  │  │  - snapshot(in:)                     │    │            │
│  │  │  - timeline(in:)                     │    │            │
│  │  │  - placeholder(in:)                  │    │            │
│  │  └──────────────────────────────────────┘    │            │
│  └───────────────────────────────────────────────┘            │
│           │                                                   │
│           ↓                                                   │
│  ┌────────────────────────────────────────────────────┐      │
│  │              Widget Views                          │      │
│  │  ┌──────────────┐  ┌──────────────┐               │      │
│  │  │ SmallWidget  │  │ MediumWidget │               │      │
│  │  │    View      │  │     View     │               │      │
│  │  └──────────────┘  └──────────────┘               │      │
│  │  ┌──────────────┐                                 │      │
│  │  │ LargeWidget  │                                 │      │
│  │  │    View      │                                 │      │
│  │  └──────────────┘                                 │      │
│  └────────────────────────────────────────────────────┘      │
└──────────────────────────────────────────────────────────────┘
```

### New Components for WidgetKit

| Component | Responsibility | Location |
|-----------|---------------|----------|
| Widget Extension Target | Separate build target containing widget code | New Xcode target |
| PingScopeWidget | Widget configuration (StaticConfiguration) | WidgetExtension/ |
| PingScopeWidgetProvider | TimelineProvider implementation | WidgetExtension/ |
| WidgetTimelineEntry | Snapshot of data at point in time | WidgetExtension/ |
| Widget Views | SwiftUI views for each widget size | WidgetExtension/ |
| WidgetDataStore | Read-only access to shared UserDefaults | Shared/ |
| WidgetModels | Lightweight data models for widget display | Shared/ |

### Modified Components for WidgetKit

| Component | Modification | Reason |
|-----------|--------------|--------|
| HostStore | Add shared UserDefaults suite support | Enable widget access to host data |
| PingResult | Move to shared framework/target | Widget needs to display results |
| Host | Move to shared framework/target | Widget needs host configurations |
| AppDelegate | Call WidgetCenter.shared.reloadAllTimelines() | Trigger widget updates on data changes |
| NotificationPreferencesStore | Add shared UserDefaults suite support | Widget may need display preferences |

## Cross-Platform Architecture Preparation

### Platform Abstraction Strategy

```
┌──────────────────────────────────────────────────────────────┐
│                    Application Layer                          │
│                  (Platform-Specific)                          │
├──────────────────────────────────────────────────────────────┤
│  macOS Target              │         iOS Target (Future)     │
│  ┌──────────────────┐      │      ┌──────────────────┐       │
│  │   AppDelegate    │      │      │   AppDelegate    │       │
│  │   (AppKit)       │      │      │   (UIKit)        │       │
│  └──────────────────┘      │      └──────────────────┘       │
│  ┌──────────────────┐      │      ┌──────────────────┐       │
│  │ StatusItemCtrl   │      │      │   Not Applicable │       │
│  │ (NSStatusItem)   │      │      │                  │       │
│  └──────────────────┘      │      └──────────────────┘       │
├──────────────────────────────────────────────────────────────┤
│                    Presentation Layer                         │
│             (Mostly Shared, Some Conditionals)                │
├──────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────┐      │
│  │            SwiftUI Views (Shared)                   │      │
│  │  ┌──────────────┐  ┌──────────────┐                │      │
│  │  │ HostListView │  │ DisplayGraph │                │      │
│  │  │  (Shared)    │  │ View (Shared)│                │      │
│  │  └──────────────┘  └──────────────┘                │      │
│  └────────────────────────────────────────────────────┘      │
│  ┌────────────────────────────────────────────────────┐      │
│  │    Platform-Specific UI Adaptations                │      │
│  │  #if os(macOS)          │   #if os(iOS)            │      │
│  │  - Popover presentation │   - Sheet presentation   │      │
│  │  - Window management    │   - Navigation stack     │      │
│  └────────────────────────────────────────────────────┘      │
├──────────────────────────────────────────────────────────────┤
│                    ViewModel Layer                            │
│                    (Fully Shared)                             │
├──────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │  DisplayVM   │  │ HostListVM   │  │ SettingsVM   │        │
│  │(@MainActor)  │  │(@MainActor)  │  │(@MainActor)  │        │
│  └──────────────┘  └──────────────┘  └──────────────┘        │
│                                                               │
│  Note: MenuBarViewModel may need iOS-specific adaptation      │
│        or replacement with a platform-agnostic StatusVM       │
├──────────────────────────────────────────────────────────────┤
│                    Service Layer                              │
│                    (Fully Shared)                             │
├──────────────────────────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐      │
│  │HostStore │  │PingService│ │Scheduler │  │NotifSvc  │      │
│  │  (actor) │  │  (actor)  │ │  (actor) │  │(@MainActor)│    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘      │
├──────────────────────────────────────────────────────────────┤
│                    Model/Data Layer                           │
│                    (Fully Shared)                             │
│  ┌────────────────────────────────────────────────────┐      │
│  │  Host, PingResult, GlobalDefaults (all Sendable)   │      │
│  └────────────────────────────────────────────────────┘      │
└──────────────────────────────────────────────────────────────┘
```

### Shareable vs Platform-Specific Code

#### Fully Shared (100% reuse)

- **Models**: Host, PingResult, PingError, GlobalDefaults, AlertType
- **Services**: PingService, PingScheduler, HostStore, HostHealthTracker
- **ViewModels**: DisplayViewModel, HostListViewModel, AddHostViewModel
- **Utilities**: ICMPPacket, Duration extensions

**Rationale**: These components have no platform-specific dependencies and use only Foundation/Network frameworks.

#### Shared with Conditionals (80-95% reuse)

- **Views**: HostListView, DisplayGraphView, HostRowView, RecentResultsListView
- **NotificationService**: UNUserNotificationCenter is cross-platform but may need different strategies

**Conditionals needed**:
```swift
#if os(macOS)
    // macOS-specific presentation (popover, window level)
#elseif os(iOS)
    // iOS-specific presentation (sheet, navigation)
#endif
```

#### Platform-Specific (0% reuse, needs iOS equivalents)

- **AppDelegate**: Different lifecycle, different menu bar/status bar patterns
- **StatusItemController**: macOS NSStatusItem has no iOS equivalent
- **DisplayModeCoordinator**: Popover/window management is AppKit-specific
- **MenuBarRuntime**: Menu bar concept doesn't exist on iOS

**iOS replacements**:
- AppDelegate → Scene-based lifecycle with background refresh
- StatusItemController → Not applicable (no menu bar on iOS)
- DisplayModeCoordinator → NavigationStack coordinator or TabView
- MenuBarRuntime → App-level state coordinator (no menu bar UI)

### Recommended Cross-Platform Project Structure

```
PingScope.xcodeproj/
├── Shared/                         # Shared across macOS, iOS, Widget
│   ├── Models/
│   │   ├── Host.swift              # Sendable, Codable
│   │   ├── PingResult.swift        # Sendable
│   │   ├── GlobalDefaults.swift
│   │   └── [Other models]
│   ├── Services/
│   │   ├── PingService.swift       # actor, Network.framework
│   │   ├── PingScheduler.swift
│   │   ├── HostStore.swift         # With app group support
│   │   └── [Other services]
│   ├── ViewModels/
│   │   ├── DisplayViewModel.swift  # @MainActor
│   │   ├── HostListViewModel.swift
│   │   └── [Other view models]
│   └── Views/
│       ├── HostListView.swift      # Mostly shared, minor conditionals
│       ├── DisplayGraphView.swift
│       └── [Shared views]
├── macOS/                          # macOS-only code
│   ├── App/
│   │   ├── PingScopeApp.swift
│   │   └── AppDelegate.swift       # macOS lifecycle
│   ├── MenuBar/
│   │   ├── StatusItemController.swift  # NSStatusItem
│   │   ├── MenuBarRuntime.swift
│   │   └── DisplayModeCoordinator.swift
│   └── Views/
│       └── [macOS-specific view adaptations]
├── iOS/ (Future)                   # iOS-only code
│   ├── App/
│   │   ├── PingScopeApp.swift
│   │   └── AppDelegate.swift       # iOS/Scene lifecycle
│   ├── Navigation/
│   │   └── AppCoordinator.swift    # iOS navigation
│   └── Views/
│       └── [iOS-specific view adaptations]
├── WidgetExtension/                # Widget target
│   ├── PingScopeWidget.swift       # Widget configuration
│   ├── Provider.swift              # TimelineProvider
│   ├── Views/
│   │   ├── SmallWidgetView.swift
│   │   ├── MediumWidgetView.swift
│   │   └── LargeWidgetView.swift
│   └── Models/
│       └── WidgetTimelineEntry.swift
└── Tests/
    ├── SharedTests/                # Test shared components
    ├── macOSTests/
    └── WidgetTests/
```

## Data Flow Changes for WidgetKit

### Current Data Flow (Main App Only)

```
User Action (Host Selection)
    ↓
MenuBarRuntime.syncSelection()
    ↓
HostStore.allHosts (actor)
    ↓
PingScheduler.updateHosts() (actor)
    ↓
PingService.ping() (actor)
    ↓
PingResult → AppDelegate.ingestSchedulerResult()
    ↓
MenuBarViewModel.ingest(result) (@MainActor)
    ↓
DisplayViewModel.ingest(result, for:) (@MainActor)
    ↓
SwiftUI Views (automatic updates via @Published)
```

### New Data Flow (App + Widget)

```
User Action (Host Selection)
    ↓
MenuBarRuntime.syncSelection()
    ↓
HostStore.allHosts (actor)
    ↓
PingScheduler.updateHosts() (actor)
    ↓
PingService.ping() (actor)
    ↓
PingResult → AppDelegate.ingestSchedulerResult()
    ↓
┌─────────────────────┬──────────────────────┐
│                     │                      │
│  Main App Updates   │  Widget Updates      │
│                     │                      │
MenuBarViewModel      WidgetDataStore
DisplayViewModel      .saveLatestResult()
HostListViewModel         │
    ↓                     ↓
SwiftUI Views      UserDefaults(appGroup)
    │                     │
    │                     │
    └─────────┬───────────┘
              ↓
      WidgetCenter.shared
      .reloadAllTimelines()
              ↓
    Widget Timeline Provider
    reads UserDefaults(appGroup)
              ↓
    Widget View Updates
```

### Key Data Sharing Patterns

#### Pattern 1: Shared UserDefaults with App Groups

**What**: Use UserDefaults with a shared suite name to persist data accessible by both main app and widget.

**When to use**: For sharing configuration, latest ping results, and host list.

**Trade-offs**:
- Pro: Simple, built-in iOS/macOS support
- Pro: Automatic synchronization
- Con: Limited to simple data types (need Codable serialization)
- Con: macOS Sequoia requires team ID prefix instead of "group." prefix

**Example**:
```swift
// Shared constant
let appGroupID = "GROUP_ID_PREFIX.dev.pingscope.app"

// Main app writes
let sharedDefaults = UserDefaults(suiteName: appGroupID)
let encoder = JSONEncoder()
if let data = try? encoder.encode(pingResults) {
    sharedDefaults?.set(data, forKey: "latestResults")
}
WidgetCenter.shared.reloadAllTimelines()

// Widget reads
let sharedDefaults = UserDefaults(suiteName: appGroupID)
if let data = sharedDefaults?.data(forKey: "latestResults"),
   let results = try? JSONDecoder().decode([PingResult].self, from: data) {
    // Use results in widget
}
```

#### Pattern 2: TimelineProvider for Widget Updates

**What**: Implement TimelineProvider protocol to supply timeline entries to WidgetKit.

**When to use**: Required for all widgets to define when and what to display.

**Trade-offs**:
- Pro: Efficient, system-managed updates
- Pro: Supports future predictions (timeline of entries)
- Con: Limited update budget (background refresh limits)
- Con: Updates may be delayed if called from main app

**Example**:
```swift
struct PingScopeWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), status: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        let entry = loadLatestData()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let currentEntry = loadLatestData()
        let timeline = Timeline(entries: [currentEntry], policy: .never)
        completion(timeline)
    }

    private func loadLatestData() -> WidgetEntry {
        let sharedDefaults = UserDefaults(suiteName: appGroupID)
        // Read shared data and construct entry
    }
}
```

#### Pattern 3: WidgetCenter Reload Coordination

**What**: Call WidgetCenter.shared.reloadAllTimelines() from main app when data changes.

**When to use**: After any ping result update, host configuration change, or user preference modification.

**Trade-offs**:
- Pro: Explicit control over when widgets update
- Pro: Simple API
- Con: Updates may be delayed/batched by system
- Con: May not update immediately if app is foreground (known iOS bug)
- Con: Subject to system budget limits

**Example**:
```swift
// In AppDelegate after ingesting result
func ingestSchedulerResult(_ result: PingResult, isHostUp: Bool) {
    // Update view models
    runtime.ingestSchedulerResult(result, isHostUp: isHostUp, matchedHostID: hostID)

    // Save to shared storage
    widgetDataStore.saveLatestResult(result)

    // Trigger widget reload
    WidgetCenter.shared.reloadAllTimelines()
}
```

## Integration Points

### App to Widget Communication

| Integration Point | Implementation | Notes |
|------------------|----------------|-------|
| Latest Ping Results | UserDefaults(appGroup) with Codable | Encode array of recent PingResult |
| Host Configuration | UserDefaults(appGroup) with Codable | Share current selected host or all hosts |
| Display Preferences | UserDefaults(appGroup) | Widget may respect color thresholds |
| Widget Reload Trigger | WidgetCenter.reloadAllTimelines() | Called after data updates |

### Widget to System

| Integration Point | Implementation | Notes |
|------------------|----------------|-------|
| Timeline Updates | TimelineProvider protocol | System manages refresh schedule |
| Configuration | StaticConfiguration | No user-configurable options needed initially |
| Size Variants | WidgetFamily (small, medium, large) | Different layouts per size |
| Notification Center | Automatic (macOS) | Widget appears in Notification Center |
| Desktop Widget | Automatic (macOS 14+) | Widget can be placed on desktop |

### Cross-Platform Boundaries

| Boundary | macOS Implementation | iOS Implementation | Communication |
|----------|---------------------|-------------------|---------------|
| App Launch | AppDelegate (AppKit) | AppDelegate/SceneDelegate | Shared ViewModels |
| Main UI | NSStatusItem + Popover | NavigationStack or TabView | Shared SwiftUI Views |
| Background Refresh | No special handling (always running) | BGAppRefreshTask | Shared PingScheduler |
| Data Persistence | HostStore with UserDefaults | Same (fully shared) | Direct |

## Architectural Patterns

### Pattern 1: Actor-Based Service Layer

**What**: Services (PingService, HostStore, PingScheduler) are Swift actors for thread-safe async operations.

**When to use**: When service manages mutable state and is accessed from multiple async contexts.

**Trade-offs**:
- Pro: Thread safety guaranteed by Swift concurrency
- Pro: Clean async/await APIs
- Con: Requires await at call sites
- Con: Cannot access @Published properties directly

**Already implemented**: This is the current architecture and should be maintained.

### Pattern 2: @MainActor ViewModels with @Published Properties

**What**: ViewModels are @MainActor classes conforming to ObservableObject with @Published properties.

**When to use**: For all SwiftUI binding and UI state management.

**Trade-offs**:
- Pro: SwiftUI automatic view updates
- Pro: Thread-safe UI updates (always on main thread)
- Con: All calls must be from @MainActor context or use Task { @MainActor in }

**Already implemented**: Continue this pattern, fully cross-platform compatible.

### Pattern 3: Coordinator-Based Lifecycle Management

**What**: AppDelegate acts as root coordinator, owning services and view models, coordinating lifecycle.

**When to use**: For centralized dependency management and lifecycle coordination.

**Trade-offs**:
- Pro: Clear ownership hierarchy
- Pro: Easy to reason about data flow
- Con: Potentially large AppDelegate
- Con: macOS-specific (needs iOS adaptation)

**Current implementation**: AppDelegate is very comprehensive. For cross-platform, consider extracting shared coordination logic into a platform-independent AppCoordinator that both macOS AppDelegate and iOS SceneDelegate can use.

### Pattern 4: Shared Container for Widget Data

**What**: Use App Groups entitlement + UserDefaults(suiteName:) for data sharing.

**When to use**: Required for widget access to app data.

**Trade-offs**:
- Pro: Official Apple pattern, well-documented
- Pro: Automatic synchronization
- Con: macOS Sequoia requires team ID prefix (different from iOS "group." prefix)
- Con: Limited to UserDefaults-compatible data (need Codable)

**Implementation required**:
1. Add App Group entitlement to both app and widget targets
2. Create WidgetDataStore to encapsulate shared UserDefaults access
3. Modify HostStore to optionally use shared suite

### Pattern 5: Platform Abstraction via Conditional Compilation

**What**: Use `#if os(macOS)` / `#if os(iOS)` for platform-specific code, minimize usage.

**When to use**: When platform APIs differ significantly (AppKit vs UIKit).

**Trade-offs**:
- Pro: Single codebase for multiple platforms
- Pro: Swift native, no runtime overhead
- Con: Can become messy if overused
- Con: Harder to test both paths

**Recommended approach**:
```swift
// GOOD: Isolate platform differences in dedicated files
#if os(macOS)
typealias PlatformViewController = NSViewController
#elseif os(iOS)
typealias PlatformViewController = UIViewController
#endif

// BETTER: Create protocol abstraction
protocol StatusDisplaying {
    func updateStatus(_ status: MenuBarStatus)
}

// macOS implementation
class MacStatusItemController: StatusDisplaying { }

// iOS implementation (future)
class iOSStatusBarController: StatusDisplaying { }
```

## Anti-Patterns to Avoid

### Anti-Pattern 1: Sharing View Models Directly with Widget

**What people do**: Try to instantiate and use main app's ViewModels in widget extension.

**Why it's wrong**:
- ViewModels are @MainActor and may depend on AppDelegate lifecycle
- Widget runs in separate process, can't share memory
- ViewModels have @Published properties that widgets can't subscribe to

**Do this instead**:
- Widget should have read-only data access via shared UserDefaults
- Create lightweight WidgetEntry models specific to widget needs
- Widget doesn't need full ViewModel capabilities

### Anti-Pattern 2: Real-Time Ping Execution in Widget

**What people do**: Attempt to run PingService directly in widget's timeline provider.

**Why it's wrong**:
- Widgets have strict CPU/memory budgets
- Network requests in widget are unreliable and slow
- Widget may be evicted before ping completes
- Violates widget's display-only purpose

**Do this instead**:
- Widget displays cached results from shared storage
- Main app (which runs continuously for menu bar app) performs pings
- Widget timeline policy is `.never`, only updates when app calls reloadAllTimelines()

### Anti-Pattern 3: Overusing #if os() Throughout Views

**What people do**: Scatter `#if os(macOS)` conditionals throughout shared view code.

**Why it's wrong**:
- Makes code hard to read and maintain
- Increases complexity and test surface
- Often indicates architectural problem

**Do this instead**:
- Use ViewModifiers to encapsulate platform differences
- Create platform-specific container views
- Keep shared views truly platform-agnostic
```swift
// BAD
struct HostListView: View {
    var body: some View {
        List {
            #if os(macOS)
            ForEach(hosts) { host in
                HostRow(host: host)
                    .listRowBackground(Color.clear)
            }
            #elseif os(iOS)
            ForEach(hosts) { host in
                HostRow(host: host)
            }
            #endif
        }
    }
}

// GOOD
struct HostListView: View {
    var body: some View {
        List {
            ForEach(hosts) { host in
                HostRow(host: host)
                    .platformListRowStyle()
            }
        }
    }
}

extension View {
    func platformListRowStyle() -> some View {
        #if os(macOS)
        self.listRowBackground(Color.clear)
        #else
        self
        #endif
    }
}
```

### Anti-Pattern 4: Separate UserDefaults Keys for App and Widget

**What people do**: Create separate persistence logic for app and widget.

**Why it's wrong**:
- Duplicated logic, easy to get out of sync
- Risk of using different keys or encoding
- Harder to maintain

**Do this instead**:
- Create shared WidgetDataStore that both app and widget use
- Single source of truth for keys, encoding/decoding
- Place in Shared/ folder so both targets can access

## Build Order and Dependencies

### Phase 1: Shared Infrastructure (No Widget Yet)

**Goal**: Prepare data layer for sharing without breaking existing functionality.

1. Create App Group entitlement (both Debug and Release)
2. Create WidgetDataStore service (shared UserDefaults access)
3. Modify HostStore to support both standard and app group UserDefaults
4. Create Shared/ folder structure
5. Move models (Host, PingResult, etc.) to Shared/ target/folder

**Dependencies**: None, can start immediately.
**Validation**: Existing app still works, data persists correctly.

### Phase 2: Widget Extension Target

**Goal**: Add widget target and basic structure.

1. Create WidgetExtension target in Xcode
2. Add App Group entitlement to widget target
3. Link Shared models/services to widget target
4. Create WidgetTimelineEntry model
5. Create stub TimelineProvider
6. Create placeholder widget views (small/medium/large)

**Dependencies**: Phase 1 complete (shared models available).
**Validation**: Widget compiles, shows placeholder content.

### Phase 3: Widget Data Integration

**Goal**: Widget displays real ping data.

1. Implement WidgetDataStore.saveLatestResults() in main app
2. Call WidgetDataStore after each ping result
3. Implement TimelineProvider.getTimeline() to read from WidgetDataStore
4. Create WidgetEntry from shared ping results
5. Implement actual widget views with real data binding

**Dependencies**: Phase 2 complete (widget target exists).
**Validation**: Widget displays latest ping status from app.

### Phase 4: Widget Update Coordination

**Goal**: Widget updates when app data changes.

1. Add WidgetCenter.shared.reloadAllTimelines() calls in AppDelegate
2. Test update latency and reliability
3. Implement proper timeline refresh policy (likely `.never`)
4. Add widget update logs for debugging

**Dependencies**: Phase 3 complete (widget displays data).
**Validation**: Widget updates within reasonable time after app data changes.

### Phase 5: Cross-Platform Structure (Preparation Only)

**Goal**: Reorganize project for future iOS support without shipping iOS.

1. Create Shared/, macOS/, WidgetExtension/ folder structure
2. Move macOS-specific code to macOS/ folder
3. Move truly shared code to Shared/ folder
4. Update Xcode targets to reference new paths
5. Create platform abstraction protocols where needed
6. Document which components need iOS equivalents

**Dependencies**: Phase 4 complete (widget fully functional).
**Validation**: macOS app and widget still work after reorganization.

**Future**: iOS target can be added by implementing iOS/ folder equivalents and linking to Shared/.

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| Single widget size | Use StaticConfiguration, Timeline policy `.never`, simple TimelineEntry |
| Multiple widget sizes | Use WidgetFamily environment value, conditional view layouts |
| Widget configuration options (future) | Switch to IntentConfiguration, add Intent Definition File, implement IntentTimelineProvider |
| Multiple widget types (future) | Create separate Widget structs, use WidgetBundle |
| iOS support (future) | Phase 5 structure enables adding iOS target without refactoring |

### Scaling Priorities

1. **First priority**: App Group data sharing and basic widget display
   - Critical for widget functionality
   - Relatively simple to implement
   - Low risk of breaking existing app

2. **Second priority**: Reliable widget updates via WidgetCenter
   - Required for useful widget experience
   - May need iteration to handle system limitations
   - Document known issues (update delays)

3. **Third priority**: Cross-platform folder structure
   - Enables future iOS development
   - Can be done incrementally
   - Low risk if done carefully with validation

4. **Future priority**: Widget customization (IntentConfiguration)
   - Not needed for MVP
   - Requires significant additional work
   - Better to validate basic widget first

## Sources

**WidgetKit App Groups:**
- [App Groups Entitlement - Apple Developer](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups)
- [Sharing data with a Widget](https://useyourloaf.com/blog/sharing-data-with-a-widget/)
- [Sharing UserDefaults with widgets - Apple Developer Forums](https://developer.apple.com/forums/thread/651799)
- [Sharing data between macOS Widget - Apple Developer Forums](https://developer.apple.com/forums/thread/737732)

**WidgetKit Architecture:**
- [TimelineProvider - Apple Developer](https://developer.apple.com/documentation/widgetkit/timelineprovider)
- [Creating a widget extension - Apple Developer](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)
- [WidgetKit Architecture Overview - StudyRaid](https://app.studyraid.com/en/read/6182/136362/widgetkit-architecture-overview)
- [What's new in widgets - WWDC25](https://developer.apple.com/videos/play/wwdc2025/278/)

**WidgetKit Updates:**
- [reloadAllTimelines() - Apple Developer](https://developer.apple.com/documentation/widgetkit/widgetcenter/reloadalltimelines())
- [WidgetCenter reload issues - GitHub Feedback](https://github.com/feedback-assistant/reports/issues/360)

**Cross-Platform SwiftUI:**
- [Sharing cross-platform code in SwiftUI apps - Jesse Squires](https://www.jessesquires.com/blog/2022/08/19/sharing-code-in-swiftui-apps/)
- [Building a Unified Multiplatform Architecture with SwiftUI](https://medium.com/@mrhotfix/building-a-unified-multiplatform-architecture-with-swiftui-ios-macos-and-visionos-6214b307466a)
- [Setting up a multi-platform SwiftUI project](https://blog.scottlogic.com/2021/03/04/Multiplatform-SwiftUI.html)

**Platform Abstraction:**
- [Using compiler directives in Swift - Swift by Sundell](https://www.swiftbysundell.com/articles/using-compiler-directives-in-swift/)
- [Platform specific code in Swift Packages](https://www.polpiella.dev/platform-specific-code-in-swift-packages/)
- [Write Platform-Specific Code Using Conditional Compilation - Kodeco](https://www.kodeco.com/books/swiftui-cookbook/v1.0/chapters/6-write-platform-specific-code-using-conditional-compilation)

**Widget Configuration:**
- [How to Create Configurable Widgets With Static Options - Swift Senpai](https://swiftsenpai.com/development/configurable-widgets-static-options/)
- [Add configuration and intelligence to your widgets - WWDC20](https://developer.apple.com/videos/play/wwdc2020/10194/)

---
*Architecture research for: PingScope v2.0 WidgetKit & Cross-Platform*
*Researched: 2026-02-17*
