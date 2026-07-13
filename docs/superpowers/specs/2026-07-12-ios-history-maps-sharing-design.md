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
- `PingResult.location: SampleLocation?`, defaulting to `nil` through all existing initializers and factories.
- Five nullable columns on `ping_samples`, added idempotently with `addColumnIfNeeded`.
- SQLite INSERT binding and row decoding for those columns.

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

- The existing `BackgroundLocationKeepAliveController` gains map-tagging mode and last-fix storage; no second `CLLocationManager` is created.
- Authorization state and the current network-interface label flow into the app model.
- The app injects a Sendable sample-enrichment provider into each focused and multi-host `LiveMonitorSessionController`.
- The app model owns ranged history loading, persisted History selections, reverse-geocode caching, MapKit snapshotting, temporary exports, and share-sheet presentation.
- MapKit and UIKit wrappers remain in focused iOS files rather than expanding `PingScopeIOSShell.swift` into a platform-services container.

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

`LiveMonitorSessionController` accepts a defaulted Sendable enrichment closure whose input and output are `PingResult`. Immediately before the write buffer receives a sample, the controller invokes this closure. The iOS app closure reads the last fix and network-interface snapshot and returns a copy with `location` set. Disabled, denied, or missing-fix states return the sample unchanged. Probe results, health ingestion, Live Activity updates, and monitor presentation continue using the original sample semantics.

Multi-host controllers receive the same provider through the controller factory. No GPS request is performed per ping.

Network interface comes from the existing `NWPathMonitor`: Wi-Fi, cellular, wired Ethernet, or other. `networkName` uses a user-facing interface label. SSID lookup is omitted unless the required entitlement already exists; this change does not add that entitlement.

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

Samples are sorted chronologically. A new session starts when the gap exceeds `max(3 * nominalInterval, 120 seconds)`. Nominal interval is derived robustly from positive adjacent gaps, falling back to 60 seconds for insufficient data. Each session contains its time span, bounded sparkline samples, metrics, and worst status. Any failure run makes the session outage state red.

### Long-range Chart Reduction

Chart rendering is capped near 500 buckets. Each chronological bucket retains representative minimum, average, and maximum successful latency values plus a failure representative when loss occurred. The primary line uses average values; extrema are available for a subtle band. Bucket timestamps remain ordered. Failures are never silently removed.

### Map Reduction

Only located samples participate. Rendering is capped at 500 points while preserving route order, the worst result in each bucket, and broad spatial coverage. Pins may additionally use a coordinate grid deduplication at long ranges. Raw 30-day sample counts are never passed to SwiftUI Map content.

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

Tapping a pin shows latency or Failed, success/failure, network label/interface, timestamp, accuracy when present, and an on-demand reverse-geocoded place. Geocoding occurs only for the selected coordinate and is cached for the session.

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

Coordinates stay in the app's local SQLite store unless the user explicitly invokes a system share sheet containing a report or annotated map. No automatic network transmission is added. `README.md` and `PRIVACY.md` will state this plainly. The When-In-Use plist message will mention History map tagging while preserving the existing keep-alive explanation.

## Failure and Concurrency Behavior

- SQLite migration is transactional through the existing open path; a failed migration closes the half-initialized connection.
- Missing or corrupt location fields do not make an otherwise valid sample unreadable.
- Missing authorization or location fix records a normal unlocated sample.
- Query completion checks selected host, range, and request generation before publishing.
- Reverse geocoding, map snapshotting, report rendering, and file export are cancellable UI tasks and never block monitoring actors.
- Map and sharing failures do not mutate history or persisted lens preferences.

## Testing and Verification

Test-first coverage includes:

- Located and unlocated `PingResult`/SQLite round trips.
- Old-schema migration and NULL location decoding.
- Corrupt/partial coordinate handling.
- Location enrichment enabled, disabled, denied, and missing-fix behavior through a platform-neutral provider seam.
- History-range persistence and query cutoffs.
- p95, outage runs, uptime, empty windows, session gap boundaries, and long-range caps.
- Map color thresholds, point caps, route ordering, and worst-zone selection.
- Report presentation and temporary-file cleanup logic.

Each milestone runs its focused tests followed by `swift build`. Each cycle runs the complete `swift test`, the `PingScope-iOS` Simulator build, `git diff --check`, and a simulator interaction pass. Final validation covers the smallest supported iPhone, light/dark Chart and Heat lenses, permission grant/denial, no-location and partial-retention states, pin detail, sharing cancellation, and no regression to Monitor/Hosts/Live Activity behavior.

Only known `DebugLog.swift` actor-isolation warnings are acceptable; new warnings require correction or explicit file-and-line reporting.

## Explicit Non-Goals

- No macOS UI or store changes.
- No probe, gateway-detection, monitoring cadence, Live Activity, widget, or background-runtime behavior changes.
- No third-party dependency or SSID entitlement.
- No roll-up table, schema-version framework, KDE renderer, cloud sync, or automatic coordinate transmission.
- No fabricated place, SSID, coordinate, per-sample loss percentage, or stored session concept.
