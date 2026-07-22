# PingScope iOS History Cycle 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add backward-compatible sample locations, 30-day iOS retention, and a race-free iOS-only history enrichment path without changing monitoring presentation semantics.

**Architecture:** `PingScopeCore` stores a platform-neutral `SampleLocation` in additive SQLite columns. `PingScopeiOS` accepts a synchronous Sendable history-enrichment closure and applies it only to the persisted copy. The iOS app owns one location manager plus a lock-guarded snapshot service used by focused and multi-host controllers.

**Tech Stack:** Swift 6, SwiftPM, XCTest, SQLite3, CoreLocation, Network, Xcode iOS Simulator.

## Global Constraints

- iOS only; do not change macOS `PingScopeApp` behavior.
- Do not change probes, gateway detection, cadence, Live Activity, widgets, or background-runtime behavior.
- No third-party dependencies or new entitlements/background modes.
- `PingScopeCore` must not import Apple UI/location/network frameworks.
- Use TDD and leave `design/` untouched.

---

### Task 1: SampleLocation model and compatibility

**Files:**
- Modify: `Sources/PingScopeCore/Domain.swift`
- Test: `Tests/PingScopeFreshTests/DomainBehaviorTests.swift`

**Interfaces:**
- Produces: `SampleLocation.init?(latitude:longitude:horizontalAccuracy:networkName:networkInterface:)`
- Produces: `PingResult.location: SampleLocation?`

- [ ] Write tests asserting valid normalization, invalid coordinate rejection, invalid accuracy removal, old JSON decoding to nil, and location preservation through factories/metadata copying.
- [ ] Run `swift test --filter DomainBehaviorTests` and confirm failures are caused by missing APIs.
- [ ] Implement the failable normalized model and custom backward-compatible `PingResult` decoding if synthesized decoding rejects the missing key.
- [ ] Audit equality consumers with `rg`; retain synthesized equality unless a location-independent comparison is found.
- [ ] Re-run focused tests and `swift build`.

### Task 2: SQLite migration and round trips

**Files:**
- Modify: `Sources/PingScopeCore/HistoryStore.swift`
- Test: `Tests/PingScopeFreshTests/HistoryStoreTests.swift`

**Interfaces:**
- Consumes: `PingResult.location`
- Produces: nullable `latitude`, `longitude`, `horizontal_accuracy`, `network_name`, and `network_interface` columns.

- [ ] Write tests for located/unlocated round trips, legacy-schema migration, partial/corrupt coordinates, and independent 30-day/default retention stores.
- [ ] Run the focused tests and confirm migration/round-trip failures.
- [ ] Add idempotent columns, extend INSERT SQL/binds, and decode valid optional location without dropping rows.
- [ ] Re-run focused tests and `swift build`.

### Task 3: History enrichment seam

**Files:**
- Modify: `Sources/PingScopeiOS/LiveMonitorSessionController.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSMultiHostSessionCoordinator.swift`
- Test: `Tests/PingScopeFreshTests/LiveMonitorSessionControllerTests.swift`

**Interfaces:**
- Produces: `typealias PingScopeIOSHistorySampleEnricher = @Sendable (PingResult) -> PingResult`
- Changes: defaulted `historySampleEnricher` on controller and multi-host factory/coordinator.

- [ ] Write tests proving only the persisted sample is enriched, presentation/health retain the original sample, identity is the default, and factory fan-out uses the same provider.
- [ ] Run focused tests and confirm failures.
- [ ] Add the defaulted closure and invoke it immediately before `historyWriter.append`.
- [ ] Thread it through the default multi-host factory/coordinator without changing existing call sites.
- [ ] Re-run focused tests and `swift build`.

### Task 4: HistoryLocationService and single-manager policy

**Files:**
- Create: `Sources/PingScopeiOSApp/HistoryLocationService.swift`
- Modify: `Sources/PingScopeiOSApp/PingScopeIOSApp.swift`
- Modify: `Configuration/Info-iOS.plist`
- Test: `Tests/PingScopeFreshTests/LiveMonitorSessionControllerTests.swift` for platform-neutral holder/provider behavior exposed from `PingScopeiOS`

**Interfaces:**
- Produces: lock-guarded Sendable `PingScopeIOSHistoryLocationSnapshotStore` in `PingScopeiOS` so XCTest can stress it without importing the app target.
- Produces: app-target `HistoryLocationService` coordinating the existing `BackgroundLocationKeepAliveController`.
- Produces: synchronous provider capturing only the snapshot store.

- [ ] Write provider tests for enabled/fix, disabled, unauthorized, missing fix, and concurrent snapshot mutation.
- [ ] Run focused tests and confirm failures.
- [ ] Implement the lock-guarded platform-neutral snapshot/provider seam.
- [ ] Move/extend the existing location controller behind `HistoryLocationService`; track keep-alive and tagging flags independently and apply the most accurate active policy.
- [ ] Update `NWPathMonitor` to publish normalized interface snapshots through the lock.
- [ ] Inject the provider into focused/replacement/multi-host controllers.
- [ ] Set only the iOS SQLite store to `.days(30)` and refine the When-In-Use plist copy.
- [ ] Run focused tests and `swift build`.

### Task 5: Cycle verification

**Files:**
- Verify all modified Cycle 1 files.

- [ ] Run `swift test` and record total/new test names.
- [ ] Run `swift build`.
- [ ] Run `xcodebuild -scheme PingScope-iOS -destination 'generic/platform=iOS Simulator' build`.
- [ ] Run `git diff --check` and `git diff --stat`.
- [ ] Audit warnings and confirm Core has no forbidden imports.
- [ ] Launch the built iOS app in Simulator and confirm the existing Monitor screen remains usable.
