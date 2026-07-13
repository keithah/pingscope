# PingScope iOS History Experience Cycle 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add persisted History ranges, race-safe ranged loading, deterministic chart reduction and statistics, sessionization, and the iOS History Chart lens.

**Architecture:** Pure History value types and reducers live in `PingScopeiOS`, including a reentrant actor that guards asynchronous loads by generation, host, and range. The iOS app model owns only persisted selection and wiring a `PingHistoryStore` into that loader. Focused SwiftUI views consume a prepared presentation rather than embedding algorithms in `PingScopeIOSShell`.

**Tech Stack:** Swift 6.2, Swift Concurrency, SwiftUI, XCTest, PingScopeCore, PingScopeiOS.

## Global Constraints

- No third-party dependencies.
- `PingScopeCore` must not import CoreLocation, MapKit, UIKit, NetworkExtension, or AppKit.
- iOS only; do not modify the macOS `PingScopeApp` target.
- Do not change probe, gateway detection, monitoring cadence, Live Activity, widget, or background-runtime behavior.
- Do not add SSID entitlements or background modes, fabricate data, or modify `design/`.
- Build only range persistence/loading, downsampling, metrics, sessionization, and Chart UI; defer Map and Sharing.
- Use test-first development and leave every task compiling and usable.

---

### Task 1: Pure History ranges, metrics, sessions, and chart reduction

**Files:**
- Create: `Sources/PingScopeiOS/PingScopeIOSHistoryPresentation.swift`
- Create: `Tests/PingScopeFreshTests/PingScopeIOSHistoryPresentationTests.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSGraphPresentation.swift`

**Interfaces:**
- Produces: `HistoryRange`, `HistoryMetrics`, `HistorySession`, `HistoryChartBucket`, `HistoryChartReduction`, and deterministic reducer entry points accepting `[PingResult]` plus explicit dates/intervals.
- Produces: arbitrary-window graph render data initializer used by the Chart UI.

- [ ] Write failing tests for all seven range raw values, durations, short/long query limits, and deterministic cutoffs.
- [ ] Run the focused tests and confirm failure because the types do not exist.
- [ ] Implement `HistoryRange` with raw values `1H`, `4H`, `12H`, `24H`, `7D`, `14D`, `30D`, default `24H`, duration, cutoff, long-range policy, and latest-sample limits sized for a two-second cadence (`2,500`, `8,000`, `25,000`, then `50,000` for 24H and longer).
- [ ] Run the focused tests and confirm they pass.
- [ ] Write failing tests for empty/single/mixed/long metric windows, nearest-rank p95 using only successful finite latency, contiguous failure runs, and clamped uptime.
- [ ] Run the focused tests and confirm the expected failures.
- [ ] Implement `HistoryMetrics`, reusing `SampleStats` for average/loss/min/max and calculating only p95, outages, and uptime directly.
- [ ] Run the focused tests and confirm they pass.
- [ ] Write failing tests for chronological sorting, lower-middle median of positive adjacent deltas, 60-second fallback, strict `gap > max(3 * nominal, 120)` boundaries, session metrics, bounded sparkline samples, and red outage state.
- [ ] Run the focused tests and confirm the expected failures.
- [ ] Implement `HistorySession` and sessionization with deterministic nominal interval and bounded sparkline reduction.
- [ ] Run the focused tests and confirm they pass.
- [ ] Write failing tests for chronological ~500-bucket reduction, retained min/average/max representatives, failure representatives, ordered timestamps, and a cap policy that never drops failure buckets.
- [ ] Run the focused tests and confirm the expected failures.
- [ ] Implement `HistoryChartReduction`, keeping successful extrema/average data and at least one failure representative per failure-bearing chronological bucket; expose average-line samples and extrema for the UI.
- [ ] Add and test an explicit start/end initializer to `PingScopeIOSLatencyGraphData` so History does not misuse live `TimeRange`.
- [ ] Run the complete new test file and `swift build`.

### Task 2: Persisted range and race-safe ranged history loading

**Files:**
- Modify: `Sources/PingScopeiOS/PingScopeIOSHistoryPresentation.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSShell.swift`
- Create: `Tests/PingScopeFreshTests/PingScopeIOSHistoryLoaderTests.swift`
- Modify: `Tests/PingScopeFreshTests/LiveMonitorSessionControllerTests.swift`

**Interfaces:**
- Consumes: `HistoryRange.cutoff(endingAt:)`, `queryLimit`, and `HistoryChartReduction` from Task 1.
- Produces: `UserDefaults.pingScopeIOSHistoryRange` and `PingScopeIOSHistoryLoader.load(store:hostID:range:now:) async -> PingScopeIOSHistoryLoadResult?`.

- [ ] Write failing tests proving invalid/missing persisted values fall back to `24H` and all valid ranges round-trip.
- [ ] Run the focused persistence tests and confirm failure.
- [ ] Implement the `UserDefaults` property beside the existing display-mode preference.
- [ ] Run the focused persistence tests and confirm they pass.
- [ ] Write a suspending controlled-store test where request A starts, request B changes host or range, B publishes, then A resumes and returns no publishable result.
- [ ] Write query-capture tests asserting host, exact injected-now cutoff, use of `latestSamples`, and the per-range limits from Task 1.
- [ ] Run the loader tests and confirm failure because the loader is absent.
- [ ] Implement the reentrant `PingScopeIOSHistoryLoader` actor with a monotonically increasing generation and post-await generation/host/range guard. Return chronologically ordered raw samples plus reduced chart presentation and collecting state.
- [ ] Run loader and persistence tests, then `swift build`.

### Task 3: App-model wiring and Chart lens UI

**Files:**
- Create: `Sources/PingScopeiOS/PingScopeIOSHistoryChartView.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSShell.swift`
- Modify: `Sources/PingScopeiOSApp/PingScopeIOSApp.swift`
- Modify: `Tests/PingScopeFreshTests/PingScopeIOSHistoryPresentationTests.swift`

**Interfaces:**
- Consumes: `PingScopeIOSHistoryLoadResult`, `HistoryRange`, `HistoryMetrics`, sessions, and chart reduction.
- Produces: root-view inputs `historyRange`, `historyPresentation`, and `onSelectHistoryRange` with compatibility defaults.

- [ ] Write failing presentation tests for collecting state, monitoring-first empty copy/state, formatted monospaced statistic values, and session status semantics.
- [ ] Run the focused tests and confirm the expected failures.
- [ ] Implement a pure `PingScopeIOSHistoryPresentation` value that prepares metric strings, empty/collecting state, sessions, and graph data from a load result.
- [ ] Run focused tests and confirm they pass.
- [ ] Wire the app model to initialize from `UserDefaults.pingScopeIOSHistoryRange`, persist changes, and force a ranged History load on range change through `PingScopeIOSHistoryLoader`.
- [ ] Preserve widget and live graph behavior with a separate operational recent-history buffer that keeps the old 24-hour/100-sample query semantics; ranged/reduced History state feeds only History UI.
- [ ] Replace the old History body with a fixed header/range control and focused `PingScopeIOSHistoryChartView`: smoothed gradient graph, Avg/p95/Loss/Outages strip, subtle collecting indicator, session cards with mini sparklines/status dots, and monitoring-first empty state.
- [ ] Use adaptive system colors, monospaced numeric text, existing `LatencyCurve`, and shared health status color vocabulary; keep Map and Share controls absent.
- [ ] Run focused tests, `swift build`, and launch the iOS simulator for a compact-layout inspection.

### Task 4: Cycle verification and scope audit

**Files:**
- Modify only Cycle 2 files if verification exposes an in-scope defect.

- [ ] Run `swift build` and retain actual output.
- [ ] Run `swift test`, record exact total and new test names, and compare to the prior 371.
- [ ] Run `xcodebuild -scheme PingScope-iOS -destination 'generic/platform=iOS Simulator' build` and retain actual output.
- [ ] Run `scripts/validate-app-smoke.sh`, `scripts/validate-ios-simulator-smoke.sh`, and `scripts/validate-ios.sh`, retaining actual output.
- [ ] Run `git diff --check`.
- [ ] Audit warnings, forbidden Core imports, macOS target changes, and `design/` status.
- [ ] Run a final whole-cycle code review and correct any actionable Cycle 2 findings test-first.
