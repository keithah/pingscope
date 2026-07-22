# PingScope iOS History, Maps, and Sharing Design

## Objective

Extend the iOS History tab into one surface with Chart, Pins, and Heat lenses, longer retained history, opt-in location tagging, and on-device exports. Preserve the existing Monitor, Hosts, All Hosts, Live Activity, widget, probe, and monitoring behavior. The macOS `PingScopeApp` target remains out of scope.

The implementation follows the visual and interaction requirements in the approved History, Maps, and Sharing brief. When the brief and `design/PingScope iOS.dc.html` disagree, the brief wins.

## Delivery Structure

The work is split into three linked implementation cycles. Each cycle consists of reviewable milestones, uses test-first development for behavior, ends with `swift build`, and includes an iOS Simulator check.

1. **Data foundation:** location model, SQLite migration, 30-day iOS retention, location capture, and history-write enrichment.
2. **History experience:** persisted range/lens state, metrics and session reducers, Chart, Pins, and Heatmap.
3. **Sharing and polish:** structured exports, report-card rendering, annotated map export, permission/empty states, privacy documentation, and compact-device validation.

Intermediate commits may not expose the full feature, but every commit must compile and every cycle must leave the app usable.

## Ownership and Boundaries

### PingScopeCore

Core receives only platform-neutral, additive data changes:

- `SampleLocation`: latitude, longitude, optional horizontal accuracy, optional network name, and optional normalized interface kind.
- `PingResult.location: SampleLocation?`, defaulting to `nil` through all existing initializers and factories (`init`, `success`, `failure`, `withHostMetadata`). Because `PingResult` is `Codable` + `Equatable` by synthesis, the added optional decodes as `nil` from older payloads (missing key) and older builds ignore the new key. **Equality concern:** synthesized `==` now includes `location`; before implementation, verify no equality-based dedup/throttle (e.g. write-buffer coalescing, widget/Live Activity change detection) depends on location-independent equality. If any does, give `PingResult` a custom `==`/`Hashable` that excludes `location`, or switch that call site to `id`-based comparison — decide per call site and record it.
- Five nullable columns on `ping_samples`, added idempotently with `addColumnIfNeeded`.
- SQLite INSERT binding and row decoding for those columns, updated together so the bound column list and the `result(from:)` read indices stay in lockstep.

Core does not import CoreLocation, MapKit, NetworkExtension, or UIKit. Existing databases migrate on open and old rows decode with `location == nil`. Older builds ignore the additional columns.

### PingScopeiOS

The framework owns pure presentation and reduction logic:

- `HistoryRange` and its duration/query/render policy.
- Persistable `HistoryLens` and `HistoryMapLens` values.
- `HistoryMetrics` for average, p95, loss, outage runs, and uptime.
- `HistorySession` plus chronological gap clustering.
- Bounded chart and map downsampling.
- Map pin/heat presentation values and latency status colors.
- `HistoryReportPresentation` for branded report content.
- Reusable History Chart and report-card SwiftUI components that do not require AppKit.

These types accept `[PingResult]` and deterministic dates/intervals so they can be unit-tested without UI or location services.

### PingScopeiOSApp

The app target owns platform adapters and mutable application state:

- The existing `BackgroundLocationKeepAliveController` gains map-tagging mode plus a lock-protected, `nonisolated` last-fix + network-interface snapshot (see "Concurrency contract" below); no second `CLLocationManager` is created.
- Authorization state and the current network-interface label flow into the app model.
- The app injects a `@Sendable` sample-enrichment provider into each focused and multi-host `LiveMonitorSessionController`.
- To keep `PingScopeIOSApp.swift` and its already-large, concurrency-sensitive app model maintainable, the new platform work is split into discrete, injected services rather than embedded in `PingScopeIOSAppModel`:
  - `HistoryLocationService` — owns the location manager policy switching, the `@unchecked Sendable` fix/interface snapshot holder, authorization state, and the enrichment provider factory.
  - `HistoryExportService` — owns temporary-file lifecycle, CSV/JSON/text via Core, `HistoryReportCard` PNG/PDF rendering, `MKMapSnapshotter` map export, and `UIActivityViewController` presentation.
  The app model retains only ranged history loading, persisted History selections, and wiring these services into the view.
- MapKit and UIKit stay in the app target (in the services above and focused SwiftUI wrapper files), never in `PingScopeCore`. The report-card **view** may live in `PingScopeiOS` (SwiftUI only); its UIKit/MapKit **rendering + snapshotting** live in `HistoryExportService` in the app target.

### Concurrency contract (enrichment seam)

`LiveMonitorSessionController` is an `actor` and writes history at `ingest(_:)` via `await historyWriter?.append(result)`. The enrichment provider is a `@Sendable (PingResult) -> PingResult` value invoked there on the history-bound copy only. Because it runs inside the actor, it must capture **only `Sendable` values** — never the `@MainActor` app model or the non-`Sendable` `BackgroundLocationKeepAliveController` reference. `HistoryLocationService` therefore exposes an `@unchecked Sendable` snapshot holder (a small lock-guarded box of `lastFix` + normalized interface) and builds the provider as a synchronous closure that reads that holder. No `await`, no actor hop, no per-ping GPS. `health.ingest`/`series.append`/presentation continue to use the original, unenriched `PingResult`.

## Data Model and Persistence

`SampleLocation` is Codable, Equatable, and Sendable. Coordinates are accepted only when finite and within valid latitude/longitude ranges. Horizontal accuracy is retained when finite and nonnegative; otherwise it becomes `nil`. Interface values are normalized to `wifi`, `cellular`, `wired`, or `other`.

SQLite adds:

- `latitude REAL`
- `longitude REAL`
- `horizontal_accuracy REAL`
- `network_name TEXT`
- `network_interface TEXT`

An absent location binds all five columns as NULL. Decoding requires valid latitude and longitude; partial or corrupt coordinate pairs yield `location == nil` without discarding the rest of the sample.

Only the iOS history-store construction changes to `.days(30)`. The macOS store keeps its existing default. Pruning remains on the existing serialized, amortized path.

## Location Capture and Sample Enrichment

The single location manager supports two policies:

- **Keep-alive:** three-kilometer accuracy, 1,000-meter filter, existing Always-authorization behavior.
- **Map tagging:** hundred-meter accuracy, 50-meter filter, When-In-Use sufficient.

Map tagging is opt-in. Entering the Map permission surface requests When-In-Use authorization. When granted and tagging is enabled, the manager uses the more accurate policy while monitoring is active. Otherwise it restores the existing keep-alive policy. `didUpdateLocations` stores the latest valid fix behind synchronized access.

`LiveMonitorSessionController` accepts a **defaulted** `@Sendable (PingResult) -> PingResult` enrichment closure (default: identity, so existing callers and monitoring behavior are unchanged). Immediately before the write buffer receives a sample (`ingest(_:)` → `await historyWriter?.append(enrich(result))`), the controller invokes it on the history-bound copy. The closure reads the lock-guarded fix + interface snapshot (see Concurrency contract) and returns a copy with `location` set. Disabled, denied, or missing-fix states return the sample unchanged. Probe results, health ingestion, Live Activity updates, and monitor presentation keep using the original, unenriched sample.

Multi-host controllers receive the same provider through `PingScopeIOSMultiHostSessionControllerFactory`. No GPS request is performed per ping.

Network interface comes from the **existing `NWPathMonitor`** (`PingScopeIOSApp.swift` — `pathMonitor`, `startNetworkPathMonitoring`). Today its `pathUpdateHandler` only triggers gateway refresh; it must be **extended** to also record the current interface (`path.usesInterfaceType(.wifi)`/`.cellular`/`.wiredEthernet` → normalized `wifi`/`cellular`/`wired`/`other`) into the same `HistoryLocationService` snapshot holder (the handler runs on `pathMonitorQueue`, not MainActor, so writes go through the lock). `networkName` uses that user-facing interface label. SSID lookup is omitted unless the required entitlement already exists; this change does not add that entitlement.

## History State and Queries

History state persists in iOS `UserDefaults` using the same pattern as the display-mode preference:

- Range: default `24H`.
- Primary lens: default Chart.
- Map sub-lens: persisted user choice, with Pins as the default for 1H–24H and Heat for 7D–30D until the user overrides it.

Ranges are 1H, 4H, 12H, 24H, 7D, 14D, and 30D. Range changes trigger a host-scoped query from `now - duration`. Short ranges use the existing latest-samples path with an appropriate bounded limit. Long ranges may query up to 50,000 samples, then reduce them in Swift. A generation/host/range guard prevents suspended results from replacing newer History state.

When the earliest result is newer than the requested window start, the UI shows a subtle collecting indicator. The range remains selectable.

## Reduction Algorithms

### Metrics

- Average, loss, minimum, and maximum reuse `SampleStats`.
- p95 sorts successful finite latency values and selects the nearest-rank 95th percentile. Empty input yields no p95.
- An outage is one contiguous run of failed results in chronological order. Success ends a run.
- Uptime is `max(0, 100 - lossPercent)`.

### Sessions

Samples are sorted chronologically. A new session starts when the gap exceeds `max(3 * nominalInterval, 120 seconds)`. **Nominal interval is the median of the positive adjacent timestamp deltas** (collect all `t[i+1] - t[i] > 0`, sort, take the middle element — lower-middle for an even count); when fewer than two positive deltas exist, fall back to `60 seconds`. This median definition is deterministic and testable (no mean/mode ambiguity, robust to a single large gap). Each session contains its time span, bounded sparkline samples, metrics, and worst status. Any failure run makes the session outage state red.

### Long-range Chart Reduction

Chart rendering is capped near 500 buckets. Each chronological bucket retains representative minimum, average, and maximum successful latency values plus a failure representative when loss occurred. The primary line uses average values; extrema are available for a subtle band. Bucket timestamps remain ordered. Failures are never silently removed.

### Map Reduction

Only located samples participate. **Map reduction is spatial, not temporal** (temporal bucketing is the chart's job): to preserve coverage of a travelled route rather than over-representing stationary periods, bucket located samples into a **coordinate grid** sized so the retained set is ≤ 500 points, keep the **worst result per occupied cell** as that cell's representative, and **always retain the single global-worst located sample** even if its cell already has a representative. The travelled `MapPolyline` is drawn from the located samples in **chronological order** (reduced with a route-order-preserving simplification such as distance-thresholded decimation, capped independently at ≤ 500 vertices) so the path never reorders. Raw 30-day sample counts are never passed to SwiftUI Map content.

## History User Interface

The History tab uses a stable header and a swappable content body:

1. Host/title row with share affordance.
2. Horizontally fitting segmented history-range control.
3. Chart/Map toggle only when location authorization is granted.
4. Chart or Map content below it.

Adaptive colors, monospaced numeric values, shared status colors/pills, and `LatencyCurve` smoothing match the shipped Signal design.

### Chart Lens

The chart contains:

- Smoothed gradient graph for the selected range.
- Avg, p95, Loss, and Outages strip.
- Collecting indicator when the window is only partially populated.
- Session cards with time range, status, mini sparkline, and average.

Empty history displays a focused monitoring-first empty state rather than fabricated values.

### Permission State

Before authorization, History stays chart-only and offers a clear, contextual location prompt. Denial keeps Map unreachable and does not repeatedly prompt. Granting permission reveals Chart/Map and enables tagging. Authorization changes propagate from `locationManagerDidChangeAuthorization`.

## Map Lenses

The Map uses the iOS 17 Map content API.

### Pins

Located samples render as colored annotations plus an ordered `MapPolyline`. Color thresholds are:

- Green below 30 ms.
- Yellow from 30 through 80 ms.
- Orange for successful latency above 80 ms.
- Red for failure.

Tapping a pin shows latency or Failed, success/failure, network label/interface, timestamp, and accuracy when present. It does not show a Place field or perform reverse geocoding.

The bottom summary reports best/worst latency and distinct network labels and provides Share. It never shows per-sample loss percentage.

### Heat

Heat mode draws bounded `MapCircle` overlays with latency/failure color and translucent overlap. Opacity adapts to light/dark appearance. The summary identifies the worst rendered zone. If MapCircle composition proves visually inadequate during simulator validation, changing to an `MKMapView` overlay renderer requires a separate reviewed decision rather than an unplanned rewrite.

Authorized windows without located samples show the map and an inline no-location-data note.

## Sharing

All exports are generated locally and handed to `UIActivityViewController`:

- CSV, JSON, and text reuse `historyStore.exportSamples`/`HistoryExporter`.
- PNG uses SwiftUI `ImageRenderer` to render `HistoryReportCard` to `UIImage`.
- PDF renders the same card through an iOS PDF graphics context.
- Map export uses `MKMapSnapshotter` for the visible region, then draws the currently selected polyline/pins or heat circles into a `UIGraphicsImageRenderer` result.

Every export receives a unique temporary filename. The activity-controller completion handler removes all temporary files whether the activity completes or is cancelled. Rendering and export errors produce a user-visible, nonfatal alert and leave History usable.

The report card includes brand, host, range, average, a smoothed sparkline, min, p95, max, loss, and uptime. It uses only the selected History window.

## Privacy

Coordinates stay in the app's local SQLite store unless the user explicitly invokes a system share sheet for an export. No automatic network transmission is added. `README.md` and `PRIVACY.md` state this plainly. The When-In-Use plist message mentions History map tagging while preserving the existing keep-alive explanation.

## Failure and Concurrency Behavior

- SQLite migration is transactional through the existing open path; a failed migration closes the half-initialized connection.
- Missing or corrupt location fields do not make an otherwise valid sample unreadable.
- Missing authorization or location fix records a normal unlocated sample.
- Query completion checks selected host, range, and request generation before publishing.
- Map snapshotting, report rendering, and file export are cancellable UI tasks and never block monitoring actors.
- Map and sharing failures do not mutate history or persisted lens preferences.

## Testing and Verification

Test-first coverage includes:

- Located and unlocated `PingResult`/SQLite round trips.
- Old-schema migration and NULL location decoding.
- Corrupt/partial coordinate handling.
- Location enrichment enabled, disabled, denied, and missing-fix behavior through a platform-neutral provider seam.
- **Enrichment concurrency:** the `@Sendable` provider, invoked from the `LiveMonitorSessionController` actor while the fix/interface snapshot changes concurrently, always yields a coherent `location` (or `nil`) and never data-races (exercise via the lock-guarded snapshot holder under a task group; must be clean under `-strict-concurrency=complete`).
- **Stale-query race:** a host/range change issued while a prior ranged query is suspended must not publish the older result — assert the generation/host/range guard drops the superseded query.
- **Retention isolation:** the iOS store constructed with `.days(30)` prunes at 30 days while a separately-constructed store at the default retention is unaffected (proves the change is store-local, not global).
- History-range persistence and query cutoffs.
- p95, outage runs, uptime, empty windows, session gap boundaries (**median nominal-interval**), and long-range caps.
- Map color thresholds, point caps, **grid-based spatial reduction incl. global-worst retention**, and route (polyline) ordering.
- Report presentation and temporary-file cleanup logic (completion **and** cancellation).

Each milestone runs its focused tests followed by `swift build`. Each cycle runs the complete `swift test`, the `PingScope-iOS` Simulator build, `git diff --check`, and a simulator interaction pass. Final validation covers the smallest supported iPhone, light/dark Chart and Heat lenses, permission grant/denial, no-location and partial-retention states, pin detail, sharing cancellation, and no regression to Monitor/Hosts/Live Activity behavior.

Only known `DebugLog.swift` actor-isolation warnings are acceptable; new warnings require correction or explicit file-and-line reporting.

## Explicit Non-Goals

- No macOS UI or store changes.
- No probe, gateway-detection, monitoring cadence, Live Activity, widget, or background-runtime behavior changes.
- No third-party dependency or SSID entitlement.
- No roll-up table, schema-version framework, KDE renderer, cloud sync, or automatic coordinate transmission.
- No Place field or reverse geocoding, and no fabricated SSID, coordinate, per-sample loss percentage, or stored session concept.

## Privacy Option A Field Audit

Pin detail does not show Place and iOS sources perform no reverse geocoding. Coordinates remain on device unless the user explicitly shares an export through the system share sheet.
