# PingScope iOS Maps and Sharing Cycle 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the approved History Maps experience through Pins and Heat, then stop for human review before any Sharing implementation.

**Architecture:** `PingScopeiOS` owns persistable lens values, authorization decisions, and deterministic bounded map presentation derived from the keyed ranged History result. `PingScopeiOSApp` owns the sole location manager, MapKit views, and camera/selection state. Privacy Option A excludes Place presentation and reverse geocoding. A SwiftUI injection seam keeps MapKit out of Core and the framework while preserving the stable History header and Chart body.

**Tech Stack:** Swift 6.2, SwiftUI, MapKit, CoreLocation, XCTest, PingScopeCore, PingScopeiOS.

## Global Constraints

- Execute only Milestones 1–4, then stop for human review. Do not implement Sharing, report cards, map export, or privacy-polish milestones.
- iOS only; do not modify the macOS `PingScopeApp` target.
- No third-party dependencies, SSID entitlement, or new background mode.
- `PingScopeCore` must not import CoreLocation, MapKit, UIKit, NetworkExtension, or AppKit.
- Preserve probe, gateway detection, monitoring cadence, Live Activity, widget, background runtime, and the separate 24-hour/100-sample operational History buffer.
- Ranged History remains visible-History-driven, keyed by host/range, and prepared off `MainActor`.
- Use the existing sole `CLLocationManager`; tagging never requests Always and remains independent from keep-alive.
- Do not show Place or perform reverse geocoding. Do not fabricate coordinates, SSIDs, per-sample loss percentages, or stored sessions.
- Do not modify, stage, delete, or commit untracked `design/`. Do not commit any work unless explicitly asked.

---

### Task 1: Persisted lenses and pure authorization decisions

**Files:**
- Create: `Sources/PingScopeiOS/PingScopeIOSHistoryMapPresentation.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSShell.swift`
- Modify: `Sources/PingScopeiOS/HistoryLocationSnapshot.swift`
- Create: `Tests/PingScopeFreshTests/PingScopeIOSHistoryMapPresentationTests.swift`
- Modify: `Tests/PingScopeFreshTests/LiveMonitorSessionControllerTests.swift`

**Interfaces:**
- Produces: `HistoryLens`, `HistoryMapLens`, optional persisted map-lens override, `HistoryMapAuthorizationPresentation`, and effective-lens/request decisions.
- Extends: `PingScopeIOSHistoryLocationAuthorization` with distinct `.restricted` handling.

- [ ] Write failing tests for Chart default, lens round trips, invalid persistence fallback, Pins defaults for 1H–24H, Heat defaults for 7D–30D, and explicit override persistence across ranges.
- [ ] Run focused tests and confirm missing-type failures.
- [ ] Implement persistable lens values and `UserDefaults` properties. Store the map override as optional; absence means range-derived default.
- [ ] Run focused tests and confirm green.
- [ ] Write failing tests for undetermined/denied/restricted/granted authorization presentation, effective Chart fallback, contextual prompt visibility, and no repeat request after denial/restriction.
- [ ] Add `.restricted` to the pure authorization enum/state machine switches and implement the presentation/request decision. Verify tagging authorization emits only When-In-Use.
- [ ] Run new tests plus existing location state-machine tests and `swift build`.

### Task 2: Authorization service wiring and stable History lens container

**Files:**
- Modify: `Sources/PingScopeiOSApp/HistoryLocationService.swift`
- Modify: `Sources/PingScopeiOSApp/PingScopeIOSApp.swift`
- Create: `Sources/PingScopeiOS/PingScopeIOSHistoryView.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSHistoryChartView.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSShell.swift`
- Modify: `Tests/PingScopeFreshTests/PingScopeIOSHistoryMapPresentationTests.swift`

**Interfaces:**
- Consumes: Task 1 lens/authorization decisions.
- Produces: published authorization/lens state, opt-in permission action, stable Chart/Map container, and an app-provided map-content SwiftUI seam that does not import MapKit in Core/framework presentation logic.

- [ ] Write failing pure integration-decision tests showing undetermined opt-in, denied/restricted no-repeat behavior, granted Map availability, authorization revocation fallback, and host/range keyed content preservation across lens switches.
- [ ] Expose read-only authorization plus `onAuthorizationChange` from `HistoryLocationService`; map restricted distinctly. Keep the existing state machine as the only request/policy executor.
- [ ] Add app-model persisted lens state and authorization publication. A user opt-in sets tagging enabled and requests When-In-Use; granted authorization keeps tagging enabled while monitoring; it never invokes the keep-alive Always request path.
- [ ] Refactor the History header/range control into `PingScopeIOSHistoryView`, with Chart body and contextual permission surface. Inject app-target map content through a defaulted SwiftUI closure/value so MapKit stays in `PingScopeiOSApp`.
- [ ] Keep host/range loading keyed exactly as Cycle 2; lens changes must reuse current ranged content and never trigger the operational history path.
- [ ] Run focused tests, `swift build`, iOS scheme build, and launch the simulator.

### Task 3: Pure bounded map presentation

**Files:**
- Modify: `Sources/PingScopeiOS/PingScopeIOSHistoryMapPresentation.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSHistoryPresentation.swift`
- Modify: `Tests/PingScopeFreshTests/PingScopeIOSHistoryMapPresentationTests.swift`

**Interfaces:**
- Produces: `HistoryMapQuality`, `HistoryMapPoint`, `HistoryMapRoutePoint`, `HistoryMapSummary`, and `HistoryMapPresentation` derived from exact keyed ranged samples.
- Integrates: `PingScopeIOSHistoryPresentation.mapPresentation`, built off-main with the Chart presentation.

- [ ] Write failing tests for valid located-only filtering and exact quality boundaries: success below 30, exactly 30, exactly 80, above 80, and failure.
- [ ] Implement scalar, Sendable map presentation values without CLLocation/MapKit types.
- [ ] Write failing tests for a coordinate grid capped at 500, worst-per-cell selection, deterministic global-worst retention without exceeding the cap, zero-span coordinates, and antimeridian-safe grid behavior.
- [ ] Implement an aspect-aware spatial grid with rows × columns ≤ the requested cap. Failures outrank successes; successful severity uses finite latency; tie-breaking is deterministic.
- [ ] Write failing tests for independently reduced chronological route vertices, duplicate-coordinate handling, endpoint preservation, and a 500-vertex cap.
- [ ] Implement stable chronological, order-preserving route decimation independent of spatial pin order.
- [ ] Write failing tests for empty presentation, best/worst successful latency, worst rendered point, and sorted/deduplicated stored network labels using name then interface fallback.
- [ ] Integrate map presentation into the keyed History presentation from `loadResult.samples`; never use operational `historySamples`.
- [ ] Run focused tests and `swift build`.

### Task 4: Pins MapKit lens and private point detail

**Files:**
- Create: `Sources/PingScopeiOSApp/PingScopeIOSHistoryMapView.swift`
- Modify: `Sources/PingScopeiOSApp/PingScopeIOSApp.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSShell.swift`
- Modify: `Tests/PingScopeFreshTests/PingScopeIOSHistoryMapPresentationTests.swift`

**Interfaces:**
- Consumes: Task 3 bounded pins, route, summary, and selected map lens.
- Produces: iOS 17 SwiftUI Map Pins lens, selected-pin detail without Place/reverse geocoding, and inert disabled Share seam.

- [ ] Add pure detail/summary formatting tests ensuring latency-or-Failed, explicit success/failure, real stored network data, timestamp, optional accuracy, no Place, and no per-point loss percentage.
- [ ] Add a repository guard test proving iOS sources contain no `CLGeocoder`, `MKReverseGeocodingRequest`, or `reverseGeocode` use.
- [ ] Implement MapKit annotations and chronological `MapPolyline` from bounded presentation only. Reset camera and selected detail when host/range changes.
- [ ] Add selected-pin detail and bottom summary. Share remains visibly disabled/no-op through the review gate.
- [ ] Implement authorized no-located-samples map state and permission-safe Chart fallback.
- [ ] Run `swift build`, iOS scheme build, and simulator inspection.

### Task 5: Heat lens, default/override integration, and Maps review gate

**Files:**
- Modify: `Sources/PingScopeiOSApp/PingScopeIOSHistoryMapView.swift`
- Modify: `Sources/PingScopeiOSApp/PingScopeIOSApp.swift`
- Modify: `Tests/PingScopeFreshTests/PingScopeIOSHistoryMapPresentationTests.swift`

**Interfaces:**
- Consumes: the same bounded map points and persistent lens policy.
- Produces: MapCircle Heat lens, adaptive opacity, Pins/Heat switch, and worst-zone summary.

- [ ] Write failing tests for Heat/Pins resolution across ranges and explicit persisted override changes.
- [ ] Render bounded `MapCircle` overlays with the shared quality palette and adaptive light/dark opacity. Do not introduce a KDE/MKOverlayRenderer path.
- [ ] Add a floating Pins/Heat control and real worst-zone summary. Provide explicit textual/accessibility failure cues, not color alone.
- [ ] Validate light mode, dark mode, 1H Pins default, 7D Heat default, persisted override, no-location state, dense cap, and pin detail in the simulator.
- [ ] Run fresh `swift build`, full `swift test`, PingScope-iOS scheme build, all three validation scripts, `git diff --check`, warning/import/scope audits, and capture required Maps screenshots.
- [ ] Run a final Maps-only code review and fix actionable Milestones 1–4 findings test-first.
- [ ] STOP and report Maps for human review. Do not start Milestone 5 Sharing work.

## Deferred Review-Gated Work

Milestones 5–8 from the execution prompt—structured sharing, report-card PNG/PDF, annotated map export, privacy documentation, and final sharing polish—remain intentionally unimplemented until the user explicitly says to continue after reviewing Maps.
