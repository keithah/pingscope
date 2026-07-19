# Resource Efficiency Follow-up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce CloudKit wakeups/network operations, per-cycle iOS presentation work, and SQLite transaction overhead without changing rendered output, sync semantics, or throttling correctness.

**Architecture:** Cloud durable-sample signals use a generation-gated accumulation timer and capped exponential retry state. iOS hot paths replace flattening/repeated reduction with bounded incremental helpers and lifecycle-owned weak tasks. Existing history write buffers remain the batching boundary, while local SQLite inserts use fresh-ID semantics and remote imports retain upsert semantics.

**Tech Stack:** Swift 6, Swift Concurrency, XCTest, CloudKit, SQLite3, SwiftUI, ActivityKit.

## Global Constraints

- Strict RED→GREEN for every behavior change.
- Preserve unrelated worktree changes; do not stage or commit.
- Do not touch `design/`.
- Do not change the probe/network wire protocol, retention windows, graph-downsampling math, or existing cache-key fingerprint fields.
- Rendered output, sync semantics, and throttle correctness must remain unchanged.

---

### Task 1: Cloud drain accumulation and exponential retry

**Files:**
- Modify: `Sources/PingScopeCloudSync/PingScopeCloudSyncService.swift`
- Test: `Tests/PingScopeFreshTests/Cloud/CloudSyncDrainHardeningTests.swift`

**Interfaces:**
- Durable-sample notifications schedule a short, lifecycle-owned accumulation delay; explicit flush paths remain immediate.
- Retry state produces `1, 2, 4, ... 60` second fallback delays, honors valid server retry-after metadata, resets on success/fresh durable input, and cancels on disable/account recovery.

- [ ] Add deterministic clock/sleeper injection and failing tests for trickled batching, prompt burst flush, widening/capped retry delays, server retry-after, reset, and disable cancellation.
- [ ] Run focused tests and record the expected RED failures.
- [ ] Implement the minimal generation-gated debounce and retry counter.
- [ ] Run the focused cloud suites GREEN and review lifecycle/account-change races.

### Task 2: iOS per-cycle and rendering costs

**Files:**
- Modify: `Sources/PingScopeiOSApp/PingScopeIOSApp.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSHistoryChartView.swift`
- Modify only if required for cadence exposure: `Sources/PingScopeiOS/LiveMonitorSessionController.swift`, `Sources/PingScopeiOS/PingScopeIOSMultiHostSessionCoordinator.swift`
- Test: `Tests/PingScopeFreshTests/iOS/LiveMonitorSessionControllerTests.swift`
- Test: relevant iOS presentation tests

**Interfaces:**
- Latest timestamp scans only each series tail.
- Widget publishing can reject unchanged cheap state before constructing the merged sample list while preserving `WidgetSnapshotPublishPolicy` decisions.
- All-host rows/series reuse prior reductions for unchanged append-only fingerprints and preserve `orderedHostIDs` order.
- Refresh loop weakly owns the model and follows the controller's bounded next refresh cadence.
- History memo capacity is four; average paths are smoothed once per segment and reused for fill/stroke.

- [ ] Add failing helper/lifecycle tests for latest-tail selection, unchanged widget short-circuit, delta reuse/order, cadence, weak task ownership, memo reuse, and one smoothing computation.
- [ ] Run each focused RED test before production edits.
- [ ] Implement the minimal helpers and hot-path substitutions without changing presentation math or policy keys.
- [ ] Run the focused iOS suites GREEN and inspect source to ensure the full-buffer `flatMap` is gone.

### Task 3: SQLite local batching semantics

**Files:**
- Modify: `Sources/PingScopeCore/HistoryStore.swift`
- Modify only if required: `Sources/PingScopeCore/HistoryWriteBuffer.swift`, `Sources/PingScopeCore/Runtime.swift`
- Test: `Tests/PingScopeFreshTests/Core/HistoryStoreTests.swift`
- Test: `Tests/PingScopeFreshTests/Core/SQLiteHistoryStoreTests.swift`

**Interfaces:**
- Existing Runtime and live-session write buffers remain the short-interval batching boundary and call `appendAndWait(_:)` once per batch.
- Locally generated samples use plain `INSERT`; remote CloudKit imports retain conflict-replacing upsert behavior.

- [ ] Add failing tests that observe one transaction for a buffered batch and distinguish local duplicate rejection from remote upsert.
- [ ] Run focused RED tests and confirm failure is transaction/conflict behavior.
- [ ] Split local insert from remote upsert with the smallest SQL change; do not alter pruning or retention.
- [ ] Run focused history/SQLite suites GREEN.

### Task 4: Optional measurement-gated items and merge hygiene

**Files:**
- Inspect: `Sources/PingScopeCore/HistoryStore.swift`
- Inspect: `PingScope.xcodeproj/project.pbxproj`
- Inspect: `Package.swift`

- [ ] Search for an existing seeded dense-week RSS benchmark. If none exists, defer weekly-digest streaming and document the missing measurement rather than changing behavior speculatively.
- [ ] Verify widget links only `PingScopeExtensionSupport` and Live Activity links only `PingScopeLiveActivitySupport`, with neither extension pulling monolithic modules.
- [ ] Run full Swift/Xcode verification serially plus git hygiene commands; report warnings, totals, deferrals, and untouched/staged state.
