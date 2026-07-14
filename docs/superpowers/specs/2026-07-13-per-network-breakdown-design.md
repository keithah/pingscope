# PingScope — Per-Network Latency Breakdown

## Objective
Let users see latency/quality **grouped by the network the samples were taken on** — home Wi-Fi vs. office Wi-Fi vs. cellular vs. wired — so they can answer "which network is bad?" Most valuable on iOS (device roams between networks), but capture is cross-platform for consistency and CloudKit-sync coherence. Monitoring/probe cadence, notifications, Live Activity, widgets, and background runtime are unchanged except for the additive capture below.

## §0 Ground truth
- `PingResult` (`Sources/PingScopeCore/Domain.swift`) has `metadata` and an optional `location: SampleLocation?`. **Network info exists only nested in `SampleLocation.networkName`/`networkInterface` (`:453-454`)** — populated by the iOS enricher only when location tagging is enabled + authorized + a fix is present. So today network data is coupled to location, iOS-only, and absent from most samples. macOS captures no network label.
- Both platforms already run an `NWPathMonitor`: macOS `PingScopeModel.pathMonitor`/`startNetworkPathMonitoring`; iOS `PingScopeIOSAppModel.pathMonitor`/`startNetworkPathMonitoring` (handler currently updates the location snapshot's interface + triggers gateway refresh).
- iOS has the `@Sendable` history enrichment seam (`LiveMonitorSessionController` applies `historySampleEnricher` to the history-bound copy at `ingest`); macOS writes via `PingScopeModel` → its own `SQLiteHistoryStore`.
- `SampleStats`/`HistoryMetrics` (avg/p95/loss/uptime/outages) already exist and operate on `[PingResult]`. `ping_samples` columns are added idempotently via `addColumnIfNeeded`.
- SSID requires the "Access WiFi Information" entitlement (out of scope, per prior decisions). Interface *type* (Wi-Fi/Cellular/Wired/Other) is available from `NWPath` with no entitlement and is not privacy-sensitive.

## §1 Scope & non-goals
**In scope:** promote network capture to a top-level, always-captured field on `PingResult`; capture it on both platforms independent of location; persist it (SQLite column + CloudKit field); a pure per-network grouping reducer; an iOS History "By network" breakdown; a modest macOS surfacing.
**Non-goals:** SSID capture / new entitlement; changing probe cadence; per-network *alerting* (a later idea); reverse geocoding or any new coordinate handling.

## §2 Data model — decouple network from location (Core, additive)
- Add top-level fields to `PingResult`: `networkInterface: String?` (normalized `wifi`/`cellular`/`wired`/`other`) and `networkName: String?` (best-effort user-facing label; today = the interface display name, since SSID is out of scope). Default `nil` in all initializers/factories; `Codable` decodes missing as `nil` (backward compatible), matching the `SampleLocation` pattern.
- `SampleLocation` **keeps** its `networkName`/`networkInterface` for the map detail card, but they are now **mirrors** sourced from the same capture; the authoritative per-sample network is the new top-level field. (Do not remove `SampleLocation`'s copies — the Map + CloudKit mapping already reference them; just ensure both are populated from one source so they never disagree.)
- SQLite: add `network_interface_top` / `network_name_top` columns to `ping_samples` via `addColumnIfNeeded` (distinct names to avoid colliding with the existing location columns `network_interface`/`network_name`), with bind + `result(from:)` read updated in lockstep. Absent → NULL → `nil`.
- CloudKit (`PingScopeCloudSync`, if/when built): add the two fields to the `PingSample` record mapping. Coordinate the field keys with that spec.

## §3 Capture (both platforms, always-on, no new permission)
- Introduce a small `@unchecked Sendable` current-network holder (normalize `NWPath.usesInterfaceType(.wifi/.cellular/.wiredEthernet)` → label), updated from each platform's existing `NWPathMonitor.pathUpdateHandler` (extend, don't add a monitor). On iOS this can reuse the `HistoryLocationSnapshotStore` interface field or a sibling holder; on macOS add the equivalent lock-guarded holder.
- Stamp every persisted `PingResult` with the current network label **regardless of location tagging or authorization**:
  - iOS: extend the existing history enricher to also set the top-level `networkInterface`/`networkName` (it already sets them inside `SampleLocation`; now set the top-level too, always — not gated on a fix).
  - macOS: stamp in `PingScopeModel`'s history-write path from its network holder.
- This is a `@Sendable`, snapshot-read stamp on the history-bound copy only; health/series/presentation continue to use the un-stamped sample (network isn't needed live). No GPS, no per-ping syscalls beyond reading the cached path label.

## §4 Reducer (pure, PingScopeiOS or Core-neutral helper)
Add `HistoryNetworkBreakdown` that takes `[PingResult]` and returns, per distinct `networkInterface`/`networkName` (nil grouped as "Unknown"): sample count, first/last seen, and a full `HistoryMetrics` (avg, p95, loss, uptime, outages). Deterministic ordering (by worst uptime, then most samples). Operates on the already ranged/downsampled sample set — no new query volume.

## §5 iOS History UI ("By network")
- Add a **By network** presentation to the History Chart lens (a section or a third chip alongside the existing content): one card per network showing label + interface glyph (Wi-Fi/Cellular/Wired), sample count, and its metrics (avg / p95 / loss / uptime), using the shared status pill/colors, monospaced numerics, and `LatencyCurve` sparkline. Tapping a network filters the graph/stats to that network for the selected range.
- Empty/degenerate states: single-network windows show one card; samples with no captured network group under "Unknown" (older pre-capture history).

## §6 macOS surfacing (modest)
Surface the same breakdown in the macOS History settings pane (`SettingsRootView+History`) as a compact per-network table (label, samples, avg/p95/loss/uptime). macOS usually sees one network, so keep it lightweight; the value is mainly the shared data model + CloudKit coherence.

## §7 Privacy
Interface *type* only (no SSID, no coordinates); no new entitlement, no transmission beyond whatever the user already opted into (CloudKit sync, if enabled). Network labels are not location. No `PRIVACY.md` change required unless the label is later upgraded to SSID (it is not here).

## §8 Testing
- `PingResult` network fields: default nil, Codable back-compat (legacy JSON → nil), factories carry the fields.
- SQLite round-trip incl. new columns; legacy rows read `nil`; column indices consistent.
- Capture: enricher stamps the network label with NO location fix present (decoupled); disabled/denied location does not suppress network capture; macOS write path stamps from its holder.
- `HistoryNetworkBreakdown`: grouping by interface/name, "Unknown" bucket for nil, per-group metrics correctness (avg/p95/loss/uptime), deterministic ordering, single-network and empty inputs.
- No regression: health/series/live presentation unaffected (they use the original sample).

## §9 Milestones (each: `swift build` + tests; app usable)
1. **Core capture decoupling:** top-level `PingResult.networkInterface`/`networkName`, SQLite columns + bind/read, iOS + macOS always-on capture from the existing `NWPathMonitor` holders, keep `SampleLocation` mirrors consistent. Tests: model/SQLite/capture.
2. **Reducer:** `HistoryNetworkBreakdown` + tests (pure).
3. **iOS "By network" UI** in the History Chart lens + filter-to-network.
4. **macOS History pane table** + (if `PingScopeCloudSync` exists) add the two fields to the `PingSample` CloudKit mapping.

## §10 Open questions (defaults chosen)
- **"Unknown" bucket** for pre-capture / untagged samples: shown as its own group (default) vs. hidden — default show, labeled clearly.
- **macOS depth:** compact table (default) vs. a full History-tab lens — default compact, since macOS rarely roams.
- **SSID:** out of scope (no entitlement); label stays interface-type. Revisit only if requested.
