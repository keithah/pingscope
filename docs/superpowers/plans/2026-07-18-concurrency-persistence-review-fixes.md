# PingScope Concurrency and Persistence Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the reviewed CloudKit, process-cancellation, logging, and alert-coalescing defects after first auditing multi-host concurrency and extracted-target wiring.

**Architecture:** Keep actor ownership and durable-store boundaries explicit. CloudKit recovery will tear down or reactivate state at account boundaries, sample drains will distinguish terminal from retryable outcomes and own their retry scheduling, process escalation will use a non-cooperative execution context, and bounded queues will preserve O(1) hot paths and transition state.

**Tech Stack:** Swift 6, structured concurrency, CloudKit, Foundation `Process`, Swift Package Manager, XCTest, Xcode.

## Global Constraints

- Work test-first: RED→GREEN for every behavior change.
- Preserve unrelated worktree changes. Do not stage or commit.
- Do not touch `design/`.
- Do not change the probe/network wire protocol, retention windows, graph-downsampling math, or existing cache-key fingerprint fields.
- If a fix is riskier than the bug, retain the code, add a tradeoff comment, and report it.
- Run the two Phase 0 investigations before implementation tasks.

---

### Task 1: Audit parallel multi-host operations

**Files:**
- Review: `Sources/PingScopeiOS/PingScopeIOSMultiHostSessionCoordinator.swift`
- Review: every production match for `TaskGroup`, `async let`, `withTaskGroup`, `concurrentPerform`, and `Task.detached` relevant to multi-host work
- Test: `Tests/PingScopeFreshTests/iOS/LiveMonitorSessionControllerTests.swift`

**Interfaces:**
- Lifecycle fan-out invokes independent `Sendable` controllers concurrently.
- `orderedSnapshots()` returns the saved enabled-host order regardless of task completion order.
- Coordinator dictionaries and ordered IDs remain actor-isolated.

- [x] Add or strengthen a stable-order test using controllers that complete in reverse or staggered order.
- [x] Run the focused test and record RED only if current ordering or synchronization is defective; otherwise record the passing coverage-gap investigation without production edits.
- [x] Audit every parallel capture for shared mutable writes, `Sendable` conformance, and actor crossings; add synchronization only for a demonstrated race.
- [x] Run the focused coordinator suite and write a findings report including explicit “no issue found” results.

### Task 2: Audit SwiftPM and Xcode target wiring

**Files:**
- Review: `Package.swift`
- Review: `PingScope.xcodeproj/project.pbxproj`
- Review: `PingScope.xcodeproj/xcshareddata/xcschemes/`
- Test: `Tests/PingScopeFreshTests/BuildGraph/BuildGraphOptimizationTests.swift`
- Test: `Tests/PingScopeFreshTests/BuildGraph/CorePlatformImportGuardTests.swift`

**Interfaces:**
- Every source under each SwiftPM target path is compiled exactly once by that target.
- Widget links `PingScopeExtensionSupport` without monolithic PingScope modules.
- Live Activity links `PingScopeLiveActivitySupport` and its minimal extension-support dependency without monolithic PingScope modules.

- [x] Extend build-graph assertions to cover source-path membership, package products, extension framework phases, and absence of monolithic products.
- [x] Run the focused tests and record RED for any missing assertion seam or broken wiring.
- [x] Fix project/package wiring only if the audit demonstrates a concrete omission, duplicate, or wrong dependency.
- [x] Direct-build both extensions and inspect linked libraries; write an explicit findings report.

### Task 3: Recover CloudKit after account changes and tear down stale state

**Files:**
- Modify: `Sources/PingScopeCloudSync/CKSyncEngineBoundary.swift`
- Modify: `Sources/PingScopeCloudSync/PingScopeCloudSyncCoordinator.swift`
- Test: `Tests/PingScopeFreshTests/Cloud/CloudSyncCoordinatorTests.swift`

**Interfaces:**
- A sign-in account-change event can reactivate or rebuild synchronization after `stopSync` without a manual settings toggle.
- Sign-out/account switch fully retires the engine handle and coordinator start state.
- Pending serialized changes from one account are not replayed into another account.
- Deferred cancellation cannot retain the engine/delegate/state cycle after teardown.

- [ ] Add `testSignInAccountChangeRestartsAfterStopAndResumesUpload`, plus teardown/deallocation and cross-account pending-state tests.
- [ ] Run the focused Cloud boundary/coordinator tests and capture the intended unreachable/dead-engine RED.
- [ ] Move account-change handling outside the inactive-event gate and implement a single idempotent teardown/restart path with account-status revalidation.
- [ ] Ensure `engineHandle`, coordinator `hasStarted`, pending serialization, and deferred cancellation are retired consistently.
- [ ] Re-run focused tests and record RED→GREEN evidence.

### Task 4: Make Cloud sample draining terminal, self-retrying, and host-reconciling

**Files:**
- Modify: `Sources/PingScopeCloudSync/PingScopeCloudSyncService.swift`
- Modify only if required: `Sources/PingScopeCore/HistoryStore.swift`
- Test: `Tests/PingScopeFreshTests/Cloud/CloudSyncCoordinatorTests.swift`
- Test: `Tests/PingScopeFreshTests/Core/HistoryStoreTests.swift`

**Interfaces:**
- Permanent per-record failures reach a bounded terminal disposition so they leave `unsyncedSamples` without blocking healthy records.
- Transient/partial failures schedule a bounded delayed re-drain, honoring `CKErrorRetryAfterKey` when available, without needing another append.
- Repeated `setEnabled(true, hosts:)` reconciles the supplied hosts before requesting a sample drain.

- [ ] Add `testPermanentRecordFailureStopsRetryingAndHealthyRecordsSync`, `testPartialTransientFailureRedrainsWithoutFurtherAppend`, and `testRedundantEnableReconcilesChangedHosts`.
- [ ] Run the focused tests and capture each independent RED before production changes.
- [ ] Classify retryable versus terminal record errors, persist terminal handling with a bounded attempt policy, and keep healthy confirmations exact.
- [ ] Add one owned retry task/timer with capped delay and cancellation on disable/teardown; avoid duplicate drains.
- [ ] Reconcile hosts on redundant enable and re-run focused tests.

### Task 5: Remove AsyncProcess handle races, cooperative blocking, and stale PID signaling

**Files:**
- Modify: `Sources/PingScopeCore/AsyncProcess.swift`
- Test: `Tests/PingScopeFreshTests/Core/AsyncProcessTests.swift`

**Interfaces:**
- Reader handles are never closed concurrently with `read(upToCount:)`.
- Cancellation escalation does not block Swift’s cooperative executor.
- TERM/KILL signals are sent only while the captured process instance is known unreaped; descendants still receive bounded cleanup.
- Cancellation and timeout remain responsive even when descendants inherit pipe write ends.

- [ ] Add a repeated mid-read cancellation stress test, simultaneous-cancellation responsiveness test, and late-cancellation/no-post-reap-signal test using injectable signal observation where necessary.
- [ ] Run the focused suite and capture RED for the current racy/blocking/stale-PID behavior.
- [ ] Remove racy reader closes and move blocking process-tree discovery/grace waits to a dedicated Dispatch queue or thread.
- [ ] Gate parent signaling with synchronized process-lifetime state captured before reap, preserving descendant cleanup.
- [ ] Re-run focused tests and record RED→GREEN evidence.

### Task 6: Make debug logging O(1) and preserve alert-transition state under pressure

**Files:**
- Modify: `Sources/PingScopeCore/DebugLog.swift`
- Modify: `Sources/PingScopeCore/Runtime.swift`
- Test: `Tests/PingScopeFreshTests/Core/DomainBehaviorTests.swift`
- Test: `Tests/PingScopeFreshTests/Core/RuntimeBehaviorTests.swift`

**Interfaces:**
- DebugLog pending writes overwrite/drop in O(1) under the existing lock while preserving sequence, flush, clear, and dropped-range semantics.
- Alert coalescing cannot discard a transition edge without reconciling `deliveredTransitionState`; informational entries yield before required transitions.

- [x] Add a wrapped-capacity logging test and a >127-transition stalled-consumer test that proves the delivered edge sequence.
- [x] Run each test and capture the intended RED.
- [x] Replace `pendingWrites.removeFirst()` with ring-buffer storage or bounded batch eviction and preserve ordering APIs.
- [x] Prefer required transition entries during coalescing or update delivered state for every dropped transition.
- [x] Re-run the focused suites and record RED→GREEN evidence.

### Task 7: Review and fresh verification

**Files:**
- Review all Task 1–6 files and the pre-existing uncommitted integration.

- [ ] Run a task-scoped correctness review after every implementation task and fix all actionable findings.
- [ ] Run a final integration review against the source request and Global Constraints.
- [ ] Run `swift build`.
- [ ] Run `swift test` and record total tests/failures.
- [ ] Run `xcodebuild -scheme PingScope-iOS -destination 'generic/platform=iOS Simulator' build`.
- [ ] Run `xcodebuild -scheme PingScope-DeveloperID -destination 'generic/platform=macOS' build` serially; clean DerivedData and rerun only for a database lock.
- [ ] Run `git diff --check`, `git status --short -- design`, `git diff --cached --stat`, and `git status --short`.
- [ ] Report file:line changes, RED→GREEN evidence, Phase 0 findings, deferred items, warnings, and staging/commit/design status.
