# PingScope Resource Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Address the supplied behavioral, efficiency, duplication, and dead-code findings without changing PingScope's monitoring semantics or rendering output.

**Architecture:** Keep authoritative health state at its existing owners, reduce append-only data to small shared fingerprints, and move avoidable graph work behind bounded cache misses. Every behavior-preserving refactor gets an equivalence test; suggestions that cannot be proven safe are documented in place instead of forced through.

**Tech Stack:** Swift 6, Swift Package Manager, XCTest, SwiftUI, Xcode schemes for iOS and macOS.

## Global Constraints

- Work test-first (RED→GREEN for any behavior change).
- Preserve unrelated worktree changes. Do not stage or commit.
- Do not touch `design/`.
- Do not change probe/networking protocols, retention, graph-downsampling point counts or extreme-preservation behavior, or existing cache-key fingerprint fields.
- Leave Control Center `shouldReloadControls` gating logic unchanged.
- If a fix proves riskier than the finding, retain the implementation and add a one-line comment explaining why.

---

### Task 1: Backoff cadence follows authoritative health where available

**Files:**
- Modify: `Sources/PingScopeCore/ProbeIdleBackoffPolicy.swift`
- Modify: `Sources/PingScopeCore/Runtime.swift`
- Modify: `Sources/PingScopeiOS/LiveMonitorSessionController.swift`
- Test: `Tests/PingScopeFreshTests/Core/RuntimeBehaviorTests.swift`
- Test: `Tests/PingScopeFreshTests/iOS/LiveMonitorSessionControllerTests.swift`

**Interfaces:**
- Consume the existing `HostHealth` status transition after `ingest` in `LiveMonitorSessionController`.
- Produce the same duration sequence: base interval through the first confirmed-down failure, doubling thereafter, capped at 30 seconds.

- [ ] Add `testBackoffCadenceUsesAuthoritativeStatusTransition` and a controller test that restarts or edits a host while down and pins both health status and the next sleep duration.
- [ ] Run `swift test --filter 'RuntimeBehaviorTests|LiveMonitorSessionControllerTests'` and verify the new assertion fails for the private shadow-health API or restart cadence.
- [ ] Replace the tracker-owned `HostHealth` with a counter driven by the caller's authoritative status transition where cleanly available; document why `MeasurementScheduler` cannot consume downstream runtime health if its stream architecture prevents that safely.
- [ ] Simplify the policy to `.seconds`, remove the redundant exponent clamp, and remove the unused `hostID` initializer argument without changing values.
- [ ] Re-run the focused tests and record the RED→GREEN evidence.

### Task 2: Shared append-only fingerprints and bounded memo storage

**Files:**
- Create or modify a shared utility under `Sources/PingScopeCore/`
- Modify: `Sources/PingScopeApp/PingScopeModel.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSHistoryChartView.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSShell.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSGraphViews.swift`
- Test: `Tests/PingScopeFreshTests/Core/DomainBehaviorTests.swift`
- Test: `Tests/PingScopeFreshTests/MacApp/PingScopePresentationViewModelTests.swift`
- Test: relevant iOS presentation tests

**Interfaces:**
- `DisplayPresentationSampleFingerprint` must retain identical equality semantics: per-host count, newest timestamp, and greatest UUID on a timestamp tie.
- UUID ordering must compare the 16 UUID bytes rather than allocating `uuidString` values.
- Cache keys must retain all current fingerprint fields and append-only invalidation behavior.

- [ ] Add an equivalence oracle test covering reordered input, multiple hosts, equal timestamps, UUID tie-breaking, count changes, and newest-sample changes; add bounded memo eviction/hit tests.
- [ ] Run the focused tests and verify RED from the not-yet-shared utility or an instrumentation assertion that detects cache recomputation.
- [ ] Implement a single forward-pass fingerprint over time-ascending samples, with a correctness fallback or documented precondition for unordered test inputs, and bytewise UUID ordering.
- [ ] Extract a small shared bounded memo utility and adopt it only where the existing key/value behavior remains identical; leave a one-line risk comment where a single-entry content cache or render-data key cannot share semantics safely.
- [ ] Re-run focused tests and record RED→GREEN evidence.

### Task 3: Lightweight history network labels and reducer equivalence decision

**Files:**
- Modify: `Sources/PingScopeHistoryKit/HistoryReportPresentation.swift`
- Modify: `Sources/PingScopeHistoryKit/PingScopeIOSHistoryMapPresentation.swift`
- Modify: `Sources/PingScopeHistoryKit/PingScopeIOSGraphPresentation.swift`
- Test: `Tests/PingScopeFreshTests/MacApp/MacHistorySurfaceTests.swift`
- Test: `Tests/PingScopeFreshTests/iOS/PingScopeIOSHistoryMapPresentationTests.swift`
- Test: `Tests/PingScopeFreshTests/History/HistoryNetworkPresentationTests.swift`

**Interfaces:**
- A lightweight helper returns the same sorted, deduplicated network labels as `HistoryMapPresentation(samples:).summary.networkLabels` without constructing map points, route, or spatial reduction.
- iOS graph output must retain the exact existing first/last points, bucket allocation, chronological extrema ordering, and maximum point count.

- [ ] Add `testHistoryMapNetworkLabelsMatchesFullPresentationSummary` with valid, invalid, duplicated, and mixed network/location samples.
- [ ] Run the focused test and verify RED because the helper does not yet exist.
- [ ] Add the lightweight label helper and use it when `HistoryReportPresentation` receives no existing map summary.
- [ ] Add an equivalence test comparing the current iOS graph reducer against `HistoryChartReduction`; reuse it only if every output point is identical, otherwise retain it and add the requested cross-reference comment.
- [ ] Re-run focused tests and record RED→GREEN evidence.

### Task 4: All-host graph and ring per-frame efficiency

**Files:**
- Modify: `Sources/PingScopeiOS/PingScopeIOSGraphViews.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSMultiHostPresentation.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSRingViews.swift`
- Test: `Tests/PingScopeFreshTests/iOS/PingScopeIOSMultiHostPresentationTests.swift`
- Test: `Tests/PingScopeFreshTests/History/LatencyGraphPresentationTests.swift`

**Interfaces:**
- Rendered paths and scrubbed latency selection remain byte-for-byte/value-for-value equivalent.
- Ring cells preserve input order, unnamed-host fallback, stale `.noData`, stale `--ms`, and the existing threshold progress formula.

- [ ] Add tests proving cache hits skip point projection, nine or more host paths remain resident, nearest scrub selection matches a flat-scan oracle, and ring cells match row-presentation rules.
- [ ] Run focused tests and verify RED for projection count, memo capacity, or duplicated rules.
- [ ] Move point projection into the path builder closure and make memo capacity at least `max(8, series.count)` without changing key fields.
- [ ] Use binary search for each chronological series only if the current combined chronological-point binary search is not already equivalent and more efficient; otherwise retain the current implementation and document the already-resolved finding in the report.
- [ ] Route ring-cell status/text/name rules through the existing row-presentation mapping and use `cell.status.iosStatusColor`.
- [ ] Re-run focused tests and record RED→GREEN evidence.

### Task 5: Dead APIs, explicit control decisions, and cadence source

**Files:**
- Modify: `Sources/PingScopeApp/PingScopePresentationViewModels.swift`
- Modify: `Sources/PingScopeApp/PopoverViews.swift`
- Modify: `Sources/PingScopeApp/OverlayView.swift`
- Modify: `Sources/PingScopeCore/WidgetSnapshotPublishPolicy.swift`
- Modify: all initializer call sites found by `rg 'WidgetSnapshotPublishDecision\\('`
- Review: `Sources/PingScopeiOSApp/PingScopeIOSApp.swift`
- Test: `Tests/PingScopeFreshTests/MacApp/PingScopePresentationViewModelTests.swift`
- Test: `Tests/PingScopeFreshTests/Core/HistoryStoreTests.swift`

**Interfaces:**
- Ring remains selectable for All Hosts; callers switch directly on `displayMode`.
- Every `WidgetSnapshotPublishDecision` call explicitly supplies `shouldReloadControls`.
- The refresh loop uses the real controller policy only if reachable without expanding ownership; otherwise the intentional two-second default comment remains.

- [ ] Change the obsolete display-mode test to expect Ring to remain Ring for All Hosts and run it to verify RED.
- [ ] Delete `resolvedForHostScope(showsAllHosts:)`, switch directly on `displayMode`, and update all references.
- [ ] Remove the `shouldReloadControls = false` default and explicitly pass `false` at unchanged call sites; leave Control Center reload gating unchanged.
- [ ] Inspect controller policy ownership and either use the actual interval or retain the current documented default.
- [ ] Run the two focused suites and record RED→GREEN evidence.

### Task 6: Whole-branch review and required verification

**Files:**
- Review all files changed by Tasks 1–5 plus the pre-existing uncommitted branch diff.

- [x] Run a task-scoped correctness review after each implementation task and fix every Critical or Important finding.
- [x] Run a final whole-branch review against the supplied constraints.
- [x] Run `swift build`.
- [x] Run `swift test` and record total tests and failures.
- [x] Run `xcodebuild -scheme PingScope-iOS -destination 'generic/platform=iOS Simulator' build`.
- [x] Run `xcodebuild -scheme PingScope-DeveloperID -destination 'generic/platform=macOS' build`.
- [x] Run `git diff --check`, `git status --short -- design`, `git diff --cached --stat`, and `git status --short`.
- [x] Report file:line changes, RED→GREEN test names/evidence, warnings, and confirmation that nothing was staged or committed.
