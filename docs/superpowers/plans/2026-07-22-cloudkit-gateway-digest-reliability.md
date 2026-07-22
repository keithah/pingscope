# CloudKit, Gateway, and Digest Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver durable inbound CloudKit retries, explicit fastest-probe gateway provenance, and equivalent but lower-work incident onset diagnosis.

**Architecture:** CloudKit inbound delivery gains an explicit durable queue at the service/boundary boundary so storage failures cannot be hidden by CKSyncEngine state serialization. Gateway behavior stays a race; returned `HostConfig` remains the single provenance carrier. History diagnosis moves from repeated latest-sample searches to monotonic per-host cursors.

**Tech Stack:** Swift 6 concurrency, CloudKit `CKSyncEngine`, XCTest, PingScopeCore, PingScopeCloudSync, PingScopeHistoryKit.

## Global Constraints

- Base this stacked branch on PR #7's head; do not merge unrelated release work.
- Do not modify `design/`, probe/network wire protocols, retention windows, graph-downsampling math, or cache-key fingerprint fields.
- Preserve fastest-success gateway selection.
- Preserve observable incident-digest results and diagnosis ordering.
- Use TDD: each production change follows a behavioral failing XCTest run.

---

### Task 1: Durable inbound CloudKit work

**Files:**
- Modify: `Sources/PingScopeCloudSync/CKSyncEngineBoundary.swift`
- Modify: `Sources/PingScopeCloudSync/PingScopeCloudSyncService.swift`
- Modify: `Sources/PingScopeCloudSync/PingScopeCloudSyncCoordinator.swift`
- Test: `Tests/PingScopeFreshTests/Cloud/CloudSyncCoordinatorTests.swift`

**Interfaces:**
- Consumes: `CKSyncEngineBoundary.RemoteChangeHandler`, `CloudSyncRemoteReceiver.apply(records:deletions:)`.
- Produces: a throwing remote apply path and persisted inbound work replayed before a new fetch.

- [ ] **Step 1: Write the failing test**

Add `testRemoteApplyFailureIsReplayedAfterRestart` using an injected history store that throws once during `upsertRemoteSamples`. Drive a fetched-record callback, restart with the same dedicated `UserDefaults` suite, then succeed. Assert one stored sample and no remaining queued work.

- [ ] **Step 2: Verify RED**

Run: `swift test --filter CloudSyncCoordinatorTests/testRemoteApplyFailureIsReplayedAfterRestart`

Expected: FAIL because the existing `try?` drops the storage error and no inbound work survives restart.

- [ ] **Step 3: Implement minimum durable handoff**

Make `CloudSyncRemoteReceiver.apply(records:deletions:)` throw. Persist an inbound batch before invoking the receiver; remove it after success; replay it during `start()` before fetching. Use existing lifecycle/cancellation checks and report a retryable failure without an unbounded delegate retry loop.

- [ ] **Step 4: Verify GREEN**

Run: `swift test --filter CloudSyncCoordinatorTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```sh
git add Sources/PingScopeCloudSync/CKSyncEngineBoundary.swift Sources/PingScopeCloudSync/PingScopeCloudSyncService.swift Sources/PingScopeCloudSync/PingScopeCloudSyncCoordinator.swift Tests/PingScopeFreshTests/Cloud/CloudSyncCoordinatorTests.swift
git commit -m "Retry durable inbound CloudKit changes"
```

### Task 2: Fastest gateway probe provenance

**Files:**
- Modify: `Sources/PingScopeCore/Runtime.swift` only if RED proves provenance is lost.
- Test: `Tests/PingScopeFreshTests/Core/HostTestingTests.swift`

**Interfaces:**
- Consumes: `DefaultGatewayEndpointResolver.Candidate` and `HostConfig` method/port fields.
- Produces: a result whose method and port identify the successful candidate.

- [ ] **Step 1: Write the failing test**

Add `testGatewayResolverReturnsFastestSuccessfulCandidateWithProbeProvenance`. Use a factory where TCP/80 blocks while UDP/53 succeeds immediately. Assert the returned host has `.udp` and port `53`.

- [ ] **Step 2: Verify RED**

Run: `swift test --filter HostTestingTests/testGatewayResolverReturnsFastestSuccessfulCandidateWithProbeProvenance`

Expected: FAIL only if result mapping loses the successful candidate's method or port. If GREEN, record that current production wiring already preserves provenance and add test coverage only.

- [ ] **Step 3: Implement only if RED**

Return the `candidateHost` that produced the successful result and ensure callers do not reconstruct it as an unqualified default gateway. Do not replace task-group racing with priority ordering.

- [ ] **Step 4: Verify GREEN and commit**

Run: `swift test --filter HostTestingTests`

Expected: PASS.

```sh
git add Sources/PingScopeCore/Runtime.swift Tests/PingScopeFreshTests/Core/HostTestingTests.swift
git commit -m "Preserve fastest gateway probe provenance"
```

### Task 3: Monotonic incident-onset lookup

**Files:**
- Modify: `Sources/PingScopeHistoryKit/HistoryIncidentDigest.swift`
- Test: `Tests/PingScopeFreshTests/History/HistoryIncidentDigestTests.swift`

**Interfaces:**
- Consumes: per-host chronologically ordered `PingResult` sequences.
- Produces: identical `HistoryIncidentLog.incidents` using a forward-only cursor map.

- [ ] **Step 1: Write the failing equivalence/work test**

Add `testIncidentOnsetUsesLatestInterleavedSamplesAcrossHosts` with several focused-host failure onsets and remote samples before, between, and after them. Assert known scope/tier and the expected incident list. If current output is already GREEN, add a narrow internal work-count seam so RED proves repeated lookup work before replacing it.

- [ ] **Step 2: Verify RED**

Run: `swift test --filter HistoryIncidentDigestTests/testIncidentOnsetUsesLatestInterleavedSamplesAcrossHosts`

Expected: FAIL because the repeated-lookup implementation exceeds the bounded lookup count, not because observable output changed.

- [ ] **Step 3: Implement monotonic cursors**

Replace `latestSample(in:through:)` calls with `[UUID: Int]` cursors. Advance each cursor while its next timestamp is at or before the onset, then use that current sample. Keep sorting and the shared diagnoser call intact.

- [ ] **Step 4: Verify GREEN and commit**

Run: `swift test --filter HistoryIncidentDigestTests`

Expected: PASS.

```sh
git add Sources/PingScopeHistoryKit/HistoryIncidentDigest.swift Tests/PingScopeFreshTests/History/HistoryIncidentDigestTests.swift
git commit -m "Index incident onset history scans"
```

### Task 4: Integration verification and stacked PR

**Files:**
- Modify: `docs/superpowers/specs/2026-07-22-cloudkit-gateway-digest-reliability-design.md`
- Modify: `docs/superpowers/plans/2026-07-22-cloudkit-gateway-digest-reliability.md`

- [ ] **Step 1: Run full package verification**

Run: `swift build && swift test && git diff --check`

Expected: build and full suite pass; no whitespace errors.

- [ ] **Step 2: Run platform compile checks**

Run: `xcodebuild -project PingScope.xcodeproj -scheme PingScope-DeveloperID -destination 'generic/platform=macOS' -jobs 1 build CODE_SIGNING_ALLOWED=NO && xcodebuild -project PingScope.xcodeproj -scheme PingScope-iOS -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`

Expected: both scheme builds succeed.

- [ ] **Step 3: Commit planning records**

```sh
git add docs/superpowers/specs/2026-07-22-cloudkit-gateway-digest-reliability-design.md docs/superpowers/plans/2026-07-22-cloudkit-gateway-digest-reliability.md
git commit -m "Document CloudKit reliability follow-up"
```
