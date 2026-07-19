# PingScope Code Optimization Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement every confirmed, production-relevant optimization from the 2026-07-17 whole-repository audit while preserving PingScope behavior and platform support.

**Architecture:** Improve the existing boundaries rather than changing product behavior: SQLite remains the durable history/outbox, CloudKit becomes an independently drained batched sink, runtime streams and queues become bounded, and expensive presentation work moves behind prepared values or narrow caches. Extension targets receive minimal shared support modules, while UI and build cleanup preserve current rendering and test semantics.

**Tech Stack:** Swift 6, Swift Package Manager, Xcode, SwiftUI, SQLite C API, CloudKit/CKSyncEngine, Network, WidgetKit, ActivityKit, XCTest.

## Global Constraints

- Do not change probe/networking protocol, history retention, or graph-downsampling math.
- Do not rework `DisplayPresentationSampleFingerprint`, `PingScopeIOSSmoothedPathMemo.Key`, or `ContentCacheKey` semantics.
- Do not touch `design/`.
- Preserve macOS 14 and iOS 17 deployment targets and Swift 6 strict concurrency.
- Add or adjust tests first and observe each new test fail before production changes.
- Do not commit, stage, push, or open a pull request.
- Preserve all user changes already present in the dirty worktree.

---

### Task 1: SQLite sync queue and bounded buffer

**Files:**
- Modify: `Sources/PingScopeCore/HistoryStore.swift`
- Modify: `Sources/PingScopeCore/BoundedBuffer.swift`
- Test: `Tests/PingScopeFreshTests/HistoryStoreTests.swift`
- Test: `Tests/PingScopeFreshTests/BoundedBufferTests.swift`

**Interfaces:**
- Produces an indexed unsynced queue without changing `PingHistoryStore` behavior.
- Keeps `BoundedBuffer.popPrefix(_:) -> [Element]` and retention/drop semantics unchanged.

- [ ] Add a failing schema/query-plan test that requires an index usable for `synced = 0 ORDER BY timestamp DESC`, and a transaction-observation test proving a sync-mark batch is atomic.
- [ ] Add a failing buffer test that repeatedly pops a wrapped buffer and verifies order, capacity reuse, prepend behavior, and dropped-count semantics without tail rebuilding.
- [ ] Run the focused tests and confirm the expected failures.
- [ ] Add `ping_samples_unsynced_time` and wrap `markSamplesSynced` in the store's established transaction/rollback helper.
- [ ] Change the buffer to advance its circular start index and clear vacated slots without rebuilding the remaining array; use optional slots if required for element lifetime release.
- [ ] Run focused Core/history tests and refactor only while green.

### Task 2: Cloud sync outbox, acknowledgement, validation, and cache bounds

**Files:**
- Modify: `Sources/PingScopeCloudSync/PingScopeCloudSyncService.swift`
- Modify: `Sources/PingScopeCloudSync/CKSyncEngineBoundary.swift`
- Modify: `Sources/PingScopeCloudSync/MonitoredHostRecordMapper.swift`
- Test: `Tests/PingScopeFreshTests/CloudSyncCoordinatorTests.swift`
- Test: `Tests/PingScopeFreshTests/CloudSyncRecordMapperTests.swift`

**Interfaces:**
- Local `appendAndWait` waits only for SQLite durability.
- One actor-owned sync drain coalesces signals, keeps one upload in flight, batches durable unsynced rows up to 300, retries local acknowledgement without re-uploading confirmed IDs in-process, and flushes/stops through existing lifecycle methods.
- Remote host application sanitizes via `HostConfig.sanitizedForStorage()`, caps the resulting collection at 64, indexes hosts by UUID, and persists version changes once per batch.

- [ ] Add failing tests for nonblocking local append, coalesced drain signaling, local mark retry without duplicate upload, sanitized/capped remote hosts, batched version persistence, and clearing terminal delegate caches on definitive stop.
- [ ] Run focused CloudSync tests and verify failures.
- [ ] Implement the minimal actor-owned outbox/drain state using SQLite's unsynced rows as the durable source; preserve existing record formats and CKSyncEngine protocol.
- [ ] Separate remote upload success from local acknowledgement state and add bounded retry/backoff state.
- [ ] Batch remote-host merge/version persistence and clear or compact staged failure state at lifecycle boundaries.
- [ ] Run focused CloudSync tests and refactor while green.

### Task 3: Runtime task lifetimes, process termination, alert/log bounds

**Files:**
- Modify: `Sources/PingScopeCore/Probes.swift`
- Modify: `Sources/PingScopeCore/Runtime.swift`
- Modify: `Sources/PingScopeCore/AsyncProcess.swift`
- Modify: `Sources/PingScopeCore/DebugLog.swift`
- Test: `Tests/PingScopeFreshTests/ProbeBehaviorTests.swift`
- Test: `Tests/PingScopeFreshTests/RuntimeBehaviorTests.swift`
- Test: `Tests/PingScopeFreshTests/AsyncProcessTests.swift`
- Test: `Tests/PingScopeFreshTests/DebugLogTests.swift`

**Interfaces:**
- Timeout races cancel and join both children before returning.
- Scheduler restart cancels and joins the prior generation before launching the next.
- Alert delivery has a finite capacity with an explicit lossless coalescing policy for transition pairs.
- `AsyncProcess` applies bounded TERM then KILL escalation and closes readers on cancellation.
- `DebugLog.write` remains nonblocking and `flush()` remains a durability barrier, backed by bounded batching; `recentText` reads only the requested tail.

- [ ] Add failing lifetime tests for joined timeout losers, joined scheduler generations, bounded alert bursts, TERM-ignoring subprocesses, bounded/batched log bursts, and tail-only reads.
- [ ] Run focused tests and verify expected failures.
- [ ] Implement structured/joined task shutdown without changing probe implementations or protocols.
- [ ] Implement bounded alert/log queues and process escalation with deterministic cleanup.
- [ ] Run focused tests and refactor while green.

### Task 4: History digest/query preparation and presentation caching

**Files:**
- Modify: `Sources/PingScopeCore/HistoryStore.swift`
- Modify: `Sources/PingScopeHistoryKit/HistoryIncidentDigest.swift`
- Modify: `Sources/PingScopeHistoryKit/HistoryNetworkBreakdown.swift`
- Modify: `Sources/PingScopeApp/MacHistoryPresentation.swift`
- Modify: `Sources/PingScopeApp/PingScopeApp.swift`
- Modify: `Sources/PingScopeApp/HistoryWindowView.swift`
- Modify: `Sources/PingScopeiOSApp/PingScopeIOSApp.swift`
- Test: `Tests/PingScopeFreshTests/HistoryStoreTests.swift`
- Test: `Tests/PingScopeFreshTests/HistoryIncidentDigestTests.swift`
- Test: `Tests/PingScopeFreshTests/MacHistorySurfaceTests.swift`

**Interfaces:**
- Add a single multi-host weekly-history streaming/reduction API that returns only the exact inputs required by `HistoryWeeklyDigest` without changing its metric math.
- Coalesce identical in-flight history loads and cache the weekly digest by enabled host identity plus a history revision/end-window key.

- [ ] Add failing tests proving one multi-host store operation supplies a digest, repeated range changes reuse the weekly result, and macOS first appearance triggers one load.
- [ ] Add failing network-breakdown tests that exercise the same output through a one-pass accumulator.
- [ ] Run focused tests and confirm failures.
- [ ] Implement the narrow batched query/reducer, bounded cache, and single lifecycle owner for initial history preparation.
- [ ] Remove temporary timestamp arrays/repeated group scans without changing metrics.
- [ ] Run focused history tests and refactor while green.

### Task 5: SwiftUI graph and history rendering

**Files:**
- Modify: `Sources/PingScopeiOS/PingScopeIOSGraphViews.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSShell.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSHistoryChartView.swift`
- Modify: `Sources/PingScopeHistoryKit/PingScopeIOSGraphPresentation.swift`
- Modify: `Sources/PingScopeHistoryKit/PingScopeIOSHistoryPresentation.swift`
- Modify: `Sources/PingScopeApp/HistoryWindowView.swift`
- Modify: `Sources/PingScopeApp/PingScopeModel.swift`
- Modify: `Sources/PingScopeApp/PingScopeDisplayPresentation.swift`
- Test: relevant presentation tests under `Tests/PingScopeFreshTests/`

**Interfaces:**
- Graph nearest-point lookup is a pure binary-search helper over chronologically ordered rendered points.
- Scrub state lives in the narrow graph/reading component, not `PingScopeIOSRootView`.
- Per-host graph data and all-host statistics are prepared once per source/range/end-date change.
- Session views use lazy stacks and stable sample-derived identity.

- [ ] Add failing unit tests for nearest-point edge/tie cases, prepared per-host graph lookup, stable session IDs, and display preparation without duplicate materialization.
- [ ] Run focused presentation tests and verify failures.
- [ ] Implement binary search, localized scrub state, prepared graph/stat values, lazy session stacks, stable identity, and one-pass display fingerprint accumulation.
- [ ] Preserve cache-key semantics and graph-downsampling math verbatim.
- [ ] Run focused presentation tests and refactor while green.

### Task 6: Multi-host concurrency, failure logging, diagnostics, and export I/O

**Files:**
- Modify: `Sources/PingScopeiOS/PingScopeIOSMultiHostSessionCoordinator.swift`
- Modify: `Sources/PingScopeiOSApp/PingScopeIOSApp.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSDiagnostics.swift`
- Modify: `Sources/PingScopeiOSApp/HistoryExportService.swift`
- Modify: `Sources/PingScopeApp/MacHistoryReportView.swift`
- Test: relevant coordinator, diagnostics, and export tests under `Tests/PingScopeFreshTests/`

**Interfaces:**
- Independent controller snapshot/start/stop calls fan out concurrently while returned snapshots retain host order.
- One failure logger suppresses repeated host/reason events for 60 seconds and reports transitions immediately.
- Diagnostics literals are deduplicated and replaced in one pass; regexes are static.
- File writes leave the main actor after platform rendering produces immutable data.

- [ ] Add failing tests for concurrent fan-out/order, failure-log suppression, single-pass redaction equivalence, and off-main file writing boundaries.
- [ ] Run focused tests and verify failures.
- [ ] Implement task-group fan-out, shared suppression state, one-pass redaction, and utility-priority file writes.
- [ ] Run focused tests and refactor while green.

### Task 7: Minimal widget and Live Activity support targets

**Files:**
- Modify: `Package.swift`
- Modify: `PingScope.xcodeproj/project.pbxproj`
- Create: focused sources under `Sources/PingScopeExtensionSupport/` and `Sources/PingScopeLiveActivitySupport/`
- Modify: `PingScopeWidget/PingScopeControls.swift`
- Modify: `PingScopeWidget/PingScopeWidget.swift`
- Modify: `PingScopeLiveActivity/PingScopeLiveActivityBundle.swift`
- Test: extension presentation/storage tests under `Tests/PingScopeFreshTests/`

**Interfaces:**
- Widget extension depends only on extension-support DTO/storage/presentation code.
- Live Activity extension depends only on live-activity support plus the smallest shared domain surface.
- App targets continue to publish exactly the same shared payload formats.

- [ ] Add dependency-boundary tests or build assertions that fail while extensions link monolithic `PingScopeiOS`/`PingScopeCore` products.
- [ ] Run the assertions and verify failure.
- [ ] Extract minimal source-compatible support targets and update Xcode package-product dependencies.
- [ ] Build both extensions directly and measure stripped binaries.
- [ ] Run extension tests and refactor while green.

### Task 8: Build graph, compilation units, parallel tests, and dead code

**Files:**
- Modify: `Package.swift`
- Modify: `PingScope.xcodeproj/project.pbxproj`
- Modify: shared schemes under `PingScope.xcodeproj/xcshareddata/xcschemes/`
- Split oversized production/test files where access control permits without behavior changes.
- Modify: `Sources/PingScopeApp/PopoverViews.swift`
- Modify: `Sources/PingScopeApp/PingScopeApp.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSShell.swift`

**Interfaces:**
- Module-aligned test targets keep existing test discovery and platform coverage.
- App Store distribution scheme does not build both mac app flavors for ordinary tests.
- Parallelization is enabled only after shared global/filesystem state is isolated.

- [ ] Add build-graph assertions for module-aligned test dependencies, scheme hosts, and extension/app target selection.
- [ ] Run assertions and verify failures.
- [ ] Split test targets and reusable test support, update schemes/test plans, and enable safe parallel execution.
- [ ] Split oversized production/test compilation units along existing feature boundaries without introducing `AnyView`.
- [ ] Remove confirmed unused private views/properties and redundant window configuration.
- [ ] Run SwiftPM and scheme tests/builds and refactor while green.

### Task 9: Final verification and review

**Files:**
- Review all changed files; no new behavior beyond Tasks 1–8.

- [x] Run `swift build`.
- [x] Run `swift test` and report test count/failures.
- [x] Run `xcodebuild -scheme PingScope-iOS -destination 'generic/platform=iOS Simulator' build`.
- [x] Run `xcodebuild -scheme PingScope-DeveloperID -destination 'generic/platform=macOS' build`.
- [x] Direct-build and measure widget and Live Activity extension release binaries.
- [x] Run `git diff --check`.
- [x] Perform a whole-branch correctness/performance review, fix all actionable findings, and repeat affected verification.
- [x] Report the complete diff and verification output without committing.
