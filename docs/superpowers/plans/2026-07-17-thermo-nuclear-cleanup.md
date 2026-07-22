# Thermo-Nuclear Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Remove every structural and maintainability issue identified by the thermo-nuclear review without changing PingScope behavior.

**Architecture:** Move iOS ring and graph view implementations out of the root shell, keep derived graph content behind a view-local memo, model probe backoff as loop-owned value state, keep ring presentation values canonical, reuse the already-built history map summary, and route CloudKit account-loss cancellation through an owned delegate operation. Preserve existing public behavior and test each ownership boundary.

**Tech Stack:** Swift 6, SwiftUI, Swift Concurrency, CloudKit CKSyncEngine, XCTest, SwiftPM, Xcode.

## Global Constraints

- Work in `/Users/keith/src/pingscope` on `codex/ios-all-hosts-live-activity`.
- Preserve unrelated worktree changes.
- Do not change probe/networking protocol, retention, or graph-downsampling math.
- Do not touch `design/`.
- Do not stage or commit.

---

### Task 1: Split Ring and Graph Views from the Root Shell

**Files:**
- Create: `Sources/PingScopeiOS/PingScopeIOSRingViews.swift`
- Create: `Sources/PingScopeiOS/PingScopeIOSGraphViews.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSShell.swift`

**Interfaces:**
- Consumes: `PingScopeIOSHostRowSnapshot`, `PingScopeIOSLatencyGraphData`, `PingScopeIOSHostGraphSeries`, `TimeRange`, and existing host-selection callbacks.
- Produces: module-internal `PingScopeIOSAllHostsRingGrid`, `SignalHeroGraphCard`, `PingScopeIOSAllHostsSignalHeroGraphCard`, and `PingScopeIOSSparkline` views.

- [x] Move `PingScopeIOSAllHostsRingGrid` unchanged into the ring view file.
- [x] Move the three graph views and `PingScopeIOSSmoothedPathMemo` unchanged into the graph view file.
- [x] Make the shared `HealthStatus.iosStatusColor` and `Color.init(iosStatusColor:)` extensions module-internal so extracted views reuse one mapping.
- [x] Run `swift build`; expect success and a substantial reduction in `PingScopeIOSShell.swift` line count.

### Task 2: Make Probe Backoff Value-Semantic

**Files:**
- Modify: `Sources/PingScopeCore/ProbeIdleBackoffPolicy.swift`
- Modify: `Sources/PingScopeCore/Runtime.swift`
- Modify: `Sources/PingScopeiOS/LiveMonitorSessionController.swift`
- Modify: `Tests/PingScopeFreshTests/RuntimeBehaviorTests.swift`

**Interfaces:**
- Produces: `public struct ProbeIdleBackoffTracker: Sendable` with `public mutating func interval(after:baseInterval:)`.

- [x] Adjust the existing tracker test and both loop-local bindings to use `var`.
- [x] Replace the mutable `@unchecked Sendable` class with a Sendable struct.
- [x] Run `swift test --filter RuntimeBehaviorTests`; expect all selected tests to pass.

### Task 3: Remove Duplicate Ring Invariants and Identity Resolution

**Files:**
- Modify: `Sources/PingScopeiOS/PingScopeIOSMultiHostPresentation.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSShell.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSRingViews.swift`
- Modify: `Tests/PingScopeFreshTests/PingScopeIOSMultiHostPresentationTests.swift`

**Interfaces:**
- `PingScopeIOSAllHostsRingCell` keeps `status` as the sole status value.
- The ring view derives color from the canonical `HealthStatus.iosStatusColor` mapping.

- [x] Update the ring-cell test to expect no separate color contract and preserve status/progress/order assertions.
- [x] Remove `statusColor`, the duplicate switch, and `resolvedForHostScope(showsAllHosts:)`.
- [x] Replace the root view's identity resolver use with `displayMode` directly and remove its obsolete unit test.
- [x] Run `swift test --filter PingScopeIOSMultiHostPresentationTests`; expect all selected tests to pass.

### Task 4: Reuse the Existing History Map Summary

**Files:**
- Modify: `Sources/PingScopeHistoryKit/HistoryReportPresentation.swift`
- Modify: `Sources/PingScopeApp/MacHistoryPresentation.swift`
- Modify: `Tests/PingScopeFreshTests/MacHistorySurfaceTests.swift`

**Interfaces:**
- `HistoryLocationPresentation.init(samples:mapSummary:)` accepts an optional precomputed `HistoryMapSummary`.
- `HistoryReportPresentation.init(host:range:samples:mapSummary:)` forwards that summary.

- [x] Add a test with a deliberately supplied map summary and assert report network labels use it.
- [x] Run the focused test and confirm RED because the initializer does not accept `mapSummary`.
- [x] Add the optional summary parameter and use it instead of rebuilding `HistoryMapPresentation` when supplied.
- [x] Forward `MacHistorySurfacePresentation.mapPresentation.summary` from `MacHistoryReportPresentation.make`.
- [x] Run the focused macOS history tests; expect GREEN.

### Task 5: Own Deferred CloudKit Cancellation

**Files:**
- Modify: `Sources/PingScopeCloudSync/CKSyncEngineBoundary.swift`
- Modify: `Tests/PingScopeFreshTests/CloudSyncCoordinatorTests.swift`

**Interfaces:**
- `PingScopeCKSyncEngineDelegate` owns a lock-protected deferred-cancellation task and exposes `awaitDeferredCancellation()` for boundary shutdown.

- [x] Replace the source-string test with assertions that the delegate schedules cancellation outside the callback and owns/awaits the task.
- [x] Run the focused test and confirm RED against the discarded detached task.
- [x] Implement lock-protected task replacement, schedule cancellation without awaiting inside the delegate callback, and await it from boundary `stop()` before releasing the engine.
- [x] Run `swift test --filter CloudSyncCoordinatorTests`; expect all selected tests to pass.

### Task 6: Full Verification

**Files:**
- Verify all modified and created files; do not stage or commit.

- [x] Run `swift build`.
- [x] Run `swift test`.
- [x] Run `xcodebuild -scheme PingScope-iOS -destination 'generic/platform=iOS Simulator' build`.
- [x] Run `xcodebuild -scheme PingScope-DeveloperID -destination 'generic/platform=macOS' build`.
- [x] Run `git diff --check`.
- [x] Confirm `design/` and the staging area are unchanged and report `git status --short`.
