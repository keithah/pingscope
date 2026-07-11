# iOS All Hosts and Multi-Host Live Activity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persisted All Hosts mode to the iOS monitor and render up to three enabled hosts with colored latency sparklines in Lock Screen Live Activities and expanded Dynamic Island presentations.

**Architecture:** Keep `LiveMonitorSessionController` single-host and compose one controller per enabled host in a new iOS coordinator. Convert controller snapshots into pure, bounded multi-host presentation snapshots shared by the iOS monitor and additive ActivityKit content state; restart the activity whenever focused versus All Hosts mode changes.

**Tech Stack:** Swift 6, SwiftUI, ActivityKit, WidgetKit, XCTest, SQLite history store, existing `LatencyCurve` CoreGraphics helper.

## Global Constraints

- Monitor and display enabled hosts only, in saved order.
- ActivityKit payloads contain at most three hosts and twelve latency samples per host.
- Keep existing scalar `ContentState` fields decodable from old payloads.
- Do not add dependencies, a watchOS target, or a new persistence format.
- Do not change probe, threshold, gateway, or on-disk history semantics.
- All Hosts always resolves to Signal presentation; focused mode retains Signal and Ring.
- Live Activity views derive exclusively from attributes and `ContentState`.

---

### Task 1: Persisted Host Scope

**Files:**
- Modify: `Sources/PingScopeiOS/PingScopeIOSHostStore.swift`
- Test: `Tests/PingScopeFreshTests/LiveMonitorSessionControllerTests.swift`

**Interfaces:**
- Produces: `PingScopeIOSHostScope`, `PingScopeIOSHostState.hostScope`, and `PingScopeIOSHostStore.save(hosts:selectedHostID:hostScope:)`.
- Preserves: existing host JSON and selected-host ID keys; adds one independent defaults key.

- [ ] **Step 1: Write failing persistence tests**

Add tests using a unique `UserDefaults(suiteName:)` that assert `.allHosts` round-trips, the concrete selected host remains unchanged, and reorder/edit/delete/disable saves preserve `.allHosts`.

```swift
func testIOSHostStorePersistsAllHostsIndependentlyFromConcreteSelection() {
    let suite = "PingScopeIOSHostScopeTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = PingScopeIOSHostStore(defaults: defaults)
    let hosts = PingScopeIOSHostStore.defaultHosts

    store.save(hosts: hosts, selectedHostID: hosts[1].id, hostScope: .allHosts)

    let state = store.load()
    XCTAssertEqual(state.hostScope, .allHosts)
    XCTAssertEqual(state.selectedHost.id, hosts[1].id)
}
```

- [ ] **Step 2: Run the focused test and confirm failure**

Run: `swift test --filter LiveMonitorSessionControllerTests/testIOSHostStorePersistsAllHostsIndependentlyFromConcreteSelection`

Expected: compile failure because `PingScopeIOSHostScope` and the new save argument do not exist.

- [ ] **Step 3: Implement additive scope persistence**

Add:

```swift
public enum PingScopeIOSHostScope: String, Codable, Sendable {
    case focused
    case allHosts
}
```

Default missing/invalid values to `.focused`. Keep the existing `save(hosts:selectedHostID:)` overload forwarding to the currently stored scope so callers do not silently reset All Hosts.

- [ ] **Step 4: Run host-store tests**

Run: `swift test --filter LiveMonitorSessionControllerTests`

Expected: all host-store and ordering tests pass.

---

### Task 2: Pure Multi-Host Presentation and Sample Reduction

**Files:**
- Create: `Sources/PingScopeiOS/PingScopeIOSMultiHostPresentation.swift`
- Test: `Tests/PingScopeFreshTests/PingScopeIOSMultiHostPresentationTests.swift`

**Interfaces:**
- Consumes: `HostConfig`, `HostHealth`, `PingResult`, and `PingScopeIOSDisplayMode`.
- Produces: `PingScopeIOSHostRowSnapshot`, `PingScopeIOSLatencySampleReducer.reduce(_:limit:)`, `PingScopeIOSHostScopePresentation.enabledHosts(from:)`, and `PingScopeIOSDisplayMode.resolvedForHostScope(showsAllHosts:)`.

- [ ] **Step 1: Write failing reducer and filtering tests**

Cover empty, one, fewer than twelve, exactly twelve, and more than twelve usable samples; failed results are excluded. Define deterministic reduction for `n > limit`: include indices `round(Double(slot) * Double(n - 1) / Double(limit - 1))` for slots `0..<limit`, deduplicated in ascending order.

```swift
func testReducerKeepsEndpointsAndEvenlyRoundedInterior() {
    let results = makeSuccessfulResults(count: 25)
    let reduced = PingScopeIOSLatencySampleReducer.reduce(results, limit: 12)
    XCTAssertEqual(reduced.first, 0)
    XCTAssertEqual(reduced.last, 24)
    XCTAssertEqual(reduced.count, 12)
    XCTAssertEqual(reduced, [0, 2, 4, 7, 9, 11, 13, 15, 17, 20, 22, 24])
}
```

Also assert enabled-only stable order and ActivityKit capping to the first three enabled hosts.

- [ ] **Step 2: Run tests and confirm missing-symbol failures**

Run: `swift test --filter PingScopeIOSMultiHostPresentationTests`

Expected: compile failure for the new presentation types.

- [ ] **Step 3: Implement pure presentation types**

`PingScopeIOSHostRowSnapshot` carries host ID, display name, endpoint caption, status, optional latest latency, reduced samples, and stale state. Keep SwiftUI colors out of this file; expose status and formatted latency (`--ms` for nil) for view mapping.

- [ ] **Step 4: Run presentation tests**

Run: `swift test --filter PingScopeIOSMultiHostPresentationTests`

Expected: all reducer, order, cap, display-mode, and latency-format tests pass.

---

### Task 3: Coordinated Controller Fan-Out and History Safety

**Files:**
- Create: `Sources/PingScopeiOS/PingScopeIOSMultiHostSessionCoordinator.swift`
- Modify only if required by evidence: `Sources/PingScopeCore/SQLiteHistoryStore.swift`
- Test: `Tests/PingScopeFreshTests/LiveMonitorSessionControllerTests.swift`
- Test: `Tests/PingScopeFreshTests/SQLiteHistoryStoreTests.swift`

**Interfaces:**
- Consumes: enabled `[HostConfig]`, shared `PingHistoryStore`, `MonitorSessionDuration`, and existing `LiveMonitorSessionController`.
- Produces: aggregate session state and ordered `[UUID: LiveMonitorSessionSnapshot]` through `start(duration:)`, `stop(reason:)`, `snapshots()`, and `reconcile(hosts:)`.

- [ ] **Step 1: Write failing fan-out tests with controller doubles**

Inject a controller factory protocol so tests assert one controller per enabled host, identical duration fan-out, disabled-host exclusion, ordered reconciliation, and stop/flush calls for removed hosts.

```swift
await coordinator.reconcile(hosts: [enabledA, disabledB, enabledC])
await coordinator.start(duration: .oneMinute)
XCTAssertEqual(factory.startedHostIDs, [enabledA.id, enabledC.id])
XCTAssertEqual(factory.startedDurations, [.oneMinute, .oneMinute])
```

- [ ] **Step 2: Run focused tests and confirm failure**

Run: `swift test --filter LiveMonitorSessionControllerTests/testIOSAllHosts`

Expected: compile failure for the coordinator and factory seam.

- [ ] **Step 3: Confirm SQLite serialization before editing**

Inspect the store's isolation and run a new test that concurrently appends distinct host rows through task groups, then queries by host ID and asserts no missing/corrupt records.

Run: `swift test --filter SQLiteHistoryStoreTests/testConcurrentMultiHostAppends`

If the actor/serial queue already protects the database, make no production store change and document that evidence. If it fails, isolate existing append transactions behind one internal actor without changing protocol signatures or schema.

- [ ] **Step 4: Implement coordinator composition**

Use existing controllers unchanged. Aggregate session remaining from the common start/duration and derive aggregate health from ordered host snapshots. Reconcile by stopping removed/disabled controllers before dropping them.

- [ ] **Step 5: Run fan-out and SQLite tests**

Run: `swift test --filter 'LiveMonitorSessionControllerTests|SQLiteHistoryStoreTests'`

Expected: focused behavior remains green; fan-out and concurrent-write tests pass.

---

### Task 4: Additive ActivityKit Payload

**Files:**
- Modify: `Sources/PingScopeiOS/PingScopeLiveActivity.swift`
- Test: `Tests/PingScopeFreshTests/PingScopeLiveActivityTests.swift`

**Interfaces:**
- Consumes: `PingScopeIOSHostRowSnapshot`.
- Produces: optional/defaulted `ContentState.hostRows`, `ContentState.mode`, and bounded ActivityKit row/sample payload models.

- [ ] **Step 1: Write Codable compatibility tests**

Test focused and All Hosts round trips, three-row/twelve-sample caps, and decode JSON containing only the old scalar keys.

```swift
let decoded = try JSONDecoder().decode(
    PingScopeLiveActivityAttributes.ContentState.self,
    from: oldScalarOnlyJSON
)
XCTAssertEqual(decoded.mode, .focused)
XCTAssertEqual(decoded.hostRows, [])
```

- [ ] **Step 2: Run compatibility tests and confirm failure**

Run: `swift test --filter PingScopeLiveActivityTests`

Expected: compile failure for `mode` and `hostRows`.

- [ ] **Step 3: Implement custom backward-compatible decoding**

Retain all scalar fields. Decode absent mode as `.focused` and absent rows as `[]`; encode new fields additively. Clamp rows and samples in initializers rather than relying on callers.

- [ ] **Step 4: Assert payload size**

Encode a worst-case three-row state with twelve samples each and assert `encoded.count < 4_096`.

- [ ] **Step 5: Run ActivityKit model tests**

Run: `swift test --filter PingScopeLiveActivityTests`

Expected: all new and old-payload tests pass.

---

### Task 5: Wire App Model Selection, Lifecycle, and Activity Restart

**Files:**
- Modify: `Sources/PingScopeiOSApp/PingScopeIOSApp.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSShell.swift`
- Test: `Tests/PingScopeFreshTests/LiveMonitorSessionControllerTests.swift`

**Interfaces:**
- Consumes: persisted host scope, multi-host coordinator, and bounded row snapshots.
- Produces: root-view `hostScope`, `allHostRows`, graph series, `onSelectAllHosts`, and mode-coherent ActivityKit updates.

- [ ] **Step 1: Write failing selection/lifecycle tests around extracted pure decisions**

Extract a small decision helper that returns `.update`, `.restart`, or `.none` from old/new host scope and focused host ID. Assert focused-to-All Hosts and All Hosts-to-focused restart, while ordinary content refresh updates.

- [ ] **Step 2: Implement app-model fan-out wiring**

Keep the last focused host in `snapshot.host`. In All Hosts mode, delegate start/stop/refresh/reconcile to the coordinator and publish ordered row/graph snapshots. Preserve host scope through add/edit/delete/reorder/enable changes.

- [ ] **Step 3: Implement coherent Live Activity restart**

On scope switch, end the current activity before requesting a new one. Focused attributes use the selected host. All Hosts attributes use `hostName = "All Hosts"` and the first enabled host ID/address/method solely as stable attribute placeholders; mode and rows live in content state, with a code comment explaining the immutable-attribute constraint.

- [ ] **Step 4: Run app-model tests**

Run: `swift test --filter LiveMonitorSessionControllerTests`

Expected: startup, run controls, focused selection, All Hosts fan-out, and restart decisions pass.

---

### Task 6: In-App All Hosts Monitor

**Files:**
- Modify: `Sources/PingScopeiOS/PingScopeIOSShell.swift`
- Reuse: `Sources/PingScopeCore/LatencyCurve.swift`
- Test: `Tests/PingScopeFreshTests/PingScopeIOSMultiHostPresentationTests.swift`

**Interfaces:**
- Consumes: root-view host scope, ordered row snapshots, and per-host samples.
- Produces: All Hosts switcher option, multi-series hero graph, and tappable compact rows.

- [ ] **Step 1: Add All Hosts to the host switcher**

Render it first with a checkmark when selected; selecting it invokes `onSelectAllHosts`. Concrete hosts retain current behavior.

- [ ] **Step 2: Add the Signal-only multi-host monitor branch**

Resolve Ring to Signal when `hostScope == .allHosts`. Draw one stable status-colored series per enabled host and retain the existing range/scrub controls where meaningful.

- [ ] **Step 3: Add compact host rows**

Each row shows dot, name, endpoint, a fixed-size smoothed sparkline using `Path(LatencyCurve.smoothedPath(...))`, and colored monospaced latency. Omit health words. Tapping selects that host.

- [ ] **Step 4: Build iOS Simulator target**

Run: `xcodebuild -scheme PingScope-iOS -destination 'generic/platform=iOS Simulator' build`

Expected: `** BUILD SUCCEEDED **` with no new compiler warnings.

---

### Task 7: Lock Screen and Dynamic Island Rows

**Files:**
- Modify: `PingScopeLiveActivity/PingScopeLiveActivityBundle.swift`
- Test: `Tests/PingScopeFreshTests/PingScopeLiveActivityTests.swift`

**Interfaces:**
- Consumes: additive content-state mode and bounded rows only.
- Produces: focused row, three-row Lock Screen layout, expanded Dynamic Island rows, and aggregate compact/minimal state.

- [ ] **Step 1: Create reusable ActivityKit host row view**

Use fixed dimensions, secondary endpoint text, shared Catmull-Rom path, status dot, and status-colored monospaced latency. Empty samples produce no line and nil latency renders `--ms`.

- [ ] **Step 2: Branch Lock Screen and expanded island by content-state mode**

All Hosts renders up to three rows and one session label. Focused renders one row built from scalar attributes/state and includes the bounded focused sparkline when present.

- [ ] **Step 3: Keep compact/minimal aggregate-only**

Use aggregate content-state status and remaining session. Do not squeeze host rows into compact/minimal regions.

- [ ] **Step 4: Build the iOS app scheme**

Run: `xcodebuild -scheme PingScope-iOS -destination 'generic/platform=iOS Simulator' build`

Expected: `** BUILD SUCCEEDED **` and the extension links `PingScopeCore` for `LatencyCurve`.

---

### Task 8: Full Verification and UX Evidence

**Files:**
- Modify only for defects found by verification.

**Interfaces:**
- Consumes: completed feature.
- Produces: actual command summaries, simulator evidence, warning audit, and diff stat.

- [ ] **Step 1: Run package verification**

Run:

```bash
swift build
swift test
```

Record total tests and every new test name.

- [ ] **Step 2: Run both platform builds**

```bash
xcodebuild -scheme PingScope-iOS -destination 'generic/platform=iOS Simulator' build
xcodebuild -scheme PingScope-DeveloperID -destination 'generic/platform=macOS' build
```

- [ ] **Step 3: Run repository validations**

```bash
scripts/validate-app-smoke.sh
scripts/validate-ios-simulator-smoke.sh
scripts/validate-ios.sh
```

- [ ] **Step 4: Exercise simulator flows**

Select All Hosts; run Live, 30s, and 1m; stop; switch to focused host; reorder and disable a host; confirm row ordering and enabled-only filtering; inspect Lock Screen Live Activity and expanded Dynamic Island; confirm focused/All Hosts switching ends and starts a new activity.

- [ ] **Step 5: Audit warnings and diff**

Run:

```bash
git diff --check
git diff --stat
rg -n "warning:" /private/tmp/pingscope-*.log
```

Report only the known `DebugLog.swift` actor-isolation warnings and identify any environment-level Xcode warnings separately.
