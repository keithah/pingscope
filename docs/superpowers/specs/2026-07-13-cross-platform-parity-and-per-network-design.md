# PingScope — Cross-Platform Feature Parity + Per-Network Breakdown

## Objective
Bring macOS and iOS to feature parity for every capability that is **not inherently platform-specific**, and add **per-network latency breakdown** (with network-name detail: Wi-Fi SSID, cellular radio type, VPN flag) as a shared capability present on both. The enabling move is extracting today's iOS-only History/metrics/presentation logic into a **shared module both apps link**, so the same behavior can be presented natively on each platform. This subsumes and coordinates with the existing specs: per-network breakdown (`2026-07-13-per-network-breakdown-design.md`), iOS History maps/sharing (`2026-07-12-…`), and CloudKit sync (`2026-07-13-cloudkit-history-sync-design.md`).

## §0 Ground truth
- Targets: `PingScopeCore` (shared, platform-neutral), `PingScopeApp` (macOS exe, **depends only on `PingScopeCore`**), `PingScopeiOS` (framework, `PingScopeCore`) + `PingScopeiOSApp`, `PingScopeCloudSync` (new), widget + Live Activity extensions.
- **All rich History logic is iOS-only:** `HistoryMetrics`/sessionization/`HistoryRange`/lens (`PingScopeIOSHistoryPresentation.swift`), map presentation+reduction (`PingScopeIOSHistoryMapPresentation.swift`), report presentation (`HistoryReportPresentation.swift`), export/report/annotated-map (`HistoryExportService.swift`, `HistoryReportCard.swift`, `HistoryMapDrawingPlan.swift`) — all in `Sources/PingScopeiOS`, which **macOS does not link**. These pure types carry no `#if os(iOS)`, so they are portable; they are simply in the wrong (iOS-only) target.
- **iOS is missing** (macOS has): network-perspective diagnosis UI (`NetworkPerspectiveDiagnosis` used only in `PingScopeApp`), the notification engine wiring (`NotificationRules`/`UNUserNotificationCenter` not wired on iOS), and Starlink telemetry UI (`StarlinkTelemetry` shown only on macOS).
- **macOS is missing** (iOS has/gets): longer History ranges (1H–30D), History metrics strip (p95/outages/uptime), sessions, per-network breakdown, report card + structured sharing.
- Existing shared infra to reuse: `SampleStats`, `TimeRange`, `LatencyCurve`, `PingHistoryStore`/`SQLiteHistoryStore`, `NotificationRules`, `NetworkPerspectiveDiagnosis`, `StarlinkTelemetry`, `PingResult`/`HostConfig` (all in `PingScopeCore`).

## §1 Principles
- **Parity = shared behavior, native presentation.** Identical data/logic on both platforms; the UI is idiomatic per platform (macOS popover/overlay/Settings window/menu bar; iOS 3-tab/Live Activity). Do **not** force one platform's UI onto the other.
- **Extract, don't duplicate.** Move platform-neutral logic to a shared module; both apps consume it. No forked copies.
- **Respect platform-inherent features** (§7) — those are intentionally single-platform and out of parity scope.
- Additive and backward-compatible; no probe/cadence/persistence-format regressions; `PingScopeCore` stays free of CoreLocation/MapKit/UIKit/NetworkExtension/AppKit.

## §2 Parity matrix
| Capability | macOS today | iOS today | Parity action |
|---|---|---|---|
| Multi-host / All Hosts | ✅ | ✅ | none |
| Signal + Ring display modes | ✅ | ✅ | none |
| Host management (CRUD/reorder/thresholds/notif policy) | ✅ | ✅ | reconcile persistence (§6d) |
| Network-perspective diagnosis | ✅ | ❌ | **add iOS diagnosis UI** (§5b) |
| Notification engine (down/recovery/high-latency/loss) | ✅ | ❌ | **add iOS notifications** (§5a) |
| Starlink telemetry display | ✅ | ❌ | **add iOS Starlink UI** (§5c) |
| Diagnostics / log export | ✅ | ❌ | **add iOS diagnostics/log export** (§5d) |
| First-run / onboarding checklist | ✅ | ❌ | **add iOS onboarding** (§5e) |
| History: 1H–30D ranges, metrics (p95/outages/uptime), sessions | ❌ | ✅ | **add to macOS** (§6a) |
| History: report card + structured sharing (CSV/JSON/text/PNG/PDF) | partial (CSV/JSON/text only) | ✅ | **add report card + share to macOS** (§6b) |
| Per-network breakdown (+ SSID/radio/VPN) | ❌ | ❌ | **add to both** (§4–§5) |
| History Maps (Pins/Heat) | ❌ | ✅ | **iOS-only by design** (§7) — low value on a stationary Mac; not parity |
| Menu bar item, floating overlay, Sparkle, start-at-login, ICMP | ✅ | — | macOS-only (§7) |
| Live Activity / Dynamic Island, background keep-alive, run-control durations | — | ✅ | iOS-only (§7) |
| CloudKit sync | (new, both) | (new, both) | delivered by the CloudKit spec |

## §3 Enabling architecture — shared `PingScopeHistoryKit`
Create a new platform-neutral SwiftPM target **`PingScopeHistoryKit`** (depends on `PingScopeCore`; may use SwiftUI/CoreGraphics but **no** UIKit/AppKit/MapKit/CoreLocation). Linked by `PingScopeApp`, `PingScopeiOSApp`, and `PingScopeiOS`. **Move** the platform-neutral History logic out of `PingScopeiOS` into it:
- `HistoryRange`, `HistoryLens`/`HistoryMapLens`, `HistoryMetrics` (avg/p95/outages/uptime), `HistorySession` + `sessionize` + `nominalInterval`, chart reduction/buckets, the History loader/stale-query guard, `HistoryReportPresentation`, and the **map reduction/presentation** value types (pins/heat/route reduction — MapKit-free; MapKit rendering stays in the iOS app).
- Add the **per-network reducer** (`HistoryNetworkBreakdown`, §5) here.
- Keep iOS-only SwiftUI views + MapKit + geocode/snapshot in `PingScopeiOSApp`/`PingScopeiOS`; they import the kit.
- `PingScopeiOS` keeps its name (no risky rename); it re-exports or imports the kit. All existing iOS call sites update to the kit types. This is a mechanical move + import fix, guarded by the existing test suite.

## §4 Network capture model (shared, the data foundation for per-network)
Extends the per-network spec with the approved network-name additions. In `PingScopeCore`:
- Promote network to top-level, **always-captured** `PingResult` fields (decoupled from `location`): `networkInterface: String?` (`wifi`/`cellular`/`wired`/`other`), `networkName: String?`, plus `isVPN: Bool` (default false). Defaults nil/false; Codable backward-compatible; SQLite columns via `addColumnIfNeeded`; CloudKit `PingSample` mapping gains the fields.
- **networkName sources** (best-effort, per platform, from a lock-guarded `@unchecked Sendable` network holder fed by the existing `NWPathMonitor`):
  - **Wi-Fi → SSID** via `NEHotspotNetwork.fetchCurrent` (iOS) / CoreWLAN (macOS). Requires the **"Access WiFi Information" entitlement** + **When-In-Use location** (iOS) / Location Services (macOS). When unavailable → fall back to the interface label "Wi-Fi".
  - **Cellular → "Cellular · 5G/LTE"** via `CTTelephonyNetworkInfo.serviceCurrentRadioAccessTechnology` (radio type only; the carrier brand is unavailable on iOS 16+ — `CTCarrier` deprecated, returns "--", so it is NOT captured).
  - **Wired/Other →** interface label.
- **VPN flag** (`isVPN`): heuristic, cross-platform — scan active interfaces for tunnel prefixes (`utun`/`tun`/`tap`/`ppp`/`ipsec`) and/or `NWPath` tunnel `.other`; local boolean, privacy-benign; surfaced in the label (e.g. "Home-WiFi · VPN"). Best-effort, not guaranteed.
- Capture is stamped on the **history-bound copy** only (via the iOS enricher seam / the macOS write path); health/series/live presentation use the original sample. No GPS per ping (SSID uses the last known network state; a fix is only needed to satisfy the SSID authorization gate, which the location-tagging flow already provides when enabled).

## §5 iOS gains (bring macOS capabilities to iOS)
a. **Notifications engine.** Wire `NotificationRules` to `UNUserNotificationCenter` on iOS for host-down/recovery/high-latency/internet-loss, honoring per-host notification policy and cooldowns, within iOS execution limits (foreground + finite background; best-effort when suspended). Reuse the Core rules; add the iOS scheduler + permission flow (permission already requested today).
b. **Network-perspective diagnosis UI.** Surface `NetworkPerspectiveDiagnosis` (gateway/upstream/remote/partial) in the iOS Monitor/All-Hosts UI, mirroring the macOS `CompactDiagnosisReasonRow`.
c. **Starlink telemetry UI.** Show `StarlinkTelemetry` (state/drop/obstruction/throughput/uptime) on iOS where a Starlink host is monitored, mirroring the macOS summary.
d. **Diagnostics / log export** on iOS (probe-failure log + export), mirroring macOS.
e. **Onboarding checklist** on iOS (notification permission, local-network, location for map/SSID, widgets) — the iOS analog of the macOS first-run checklist.

## §6 macOS gains (bring iOS History to macOS)
a. **Rich History**: 1H–30D ranges, the metrics strip (avg/p95/outages/uptime), sessions list, and per-network breakdown, presented in a macOS **History surface** (a dedicated History window/tab off the Settings window or the popover's history area), built on `PingScopeHistoryKit`.
b. **Report card + structured sharing**: the branded PNG/PDF report card and share flow (macOS uses `ImageRenderer` + an AppKit share/`NSSharingServicePicker`; the existing macOS `PingScopeShareGraphImage` is a starting point). CSV/JSON/text already exist on macOS via `HistoryExporter`.
c. **Per-network breakdown** table (§5 of the per-network spec) in the macOS History surface.
d. **Host-config reconciliation** (prerequisite for CloudKit host sync too): macOS `HostConfigPersistence` (`UserDefaults hostConfigs`) and iOS `PingScopeIOSHostStore` (`PingScope.iOS.hosts`) store the same `[HostConfig]` under different keys/shapes. Introduce a shared host-store contract so both platforms read/write a consistent representation (and so CloudKit host sync is coherent).
- **Maps (Pins/Heat) are NOT brought to macOS** (§7): a travel map is low value on a stationary Mac and adds CoreLocation/MapKit weight; macOS History is Chart + metrics + sessions + per-network + report.

## §7 Explicitly platform-specific (out of parity scope)
- **iOS-only:** Live Activity / Dynamic Island, background keep-alive (Always Location), finite run-control durations (30s/1m), History **Maps** lens.
- **macOS-only:** menu-bar status item, floating overlay, Sparkle updates + in-app update view, start-at-login, Developer-ID ICMP.
These stay single-platform by nature; "parity" does not mean porting them.

## §8 Shared vs platform UI
- **Shared (in `PingScopeHistoryKit`):** all value/presentation logic (ranges, metrics, sessions, per-network, report presentation, map reduction values) — no UIKit/AppKit/MapKit.
- **Platform UI:** SwiftUI views idiomatic to each app. Cross-platform SwiftUI components (e.g. the report card, a chart card) may be shared where they use only `LatencyCurve` + platform-agnostic SwiftUI; anything needing `NSImage`/`UIImage`, MapKit, or AppKit/UIKit stays in the respective app target.

## §9 Privacy & entitlements
- **SSID** makes the network label location-adjacent PII: add the "Access WiFi Information" entitlement on both apps and a When-In-Use/Location dependency; disclose in-app; if CloudKit sync is on, SSID/coordinates reach the user's private iCloud (already disclosed by the CloudKit spec). Provisioning (container + WiFi-info capability + signing incl. DeveloperID) is a manual step.
- **VPN flag** and **interface type / radio type** are not sensitive; no entitlement.
- Update `PRIVACY.md`/`README.md` for SSID capture + iCloud sync.

## §10 Testing
- Kit extraction: existing iOS History tests move with the code and stay green; add macOS-target tests exercising the same shared types (proves cross-platform).
- Network capture: top-level fields + SSID/radio/VPN capture (decoupled from location); Codable/SQLite/CloudKit round-trips; VPN heuristic on tunnel-interface fixtures.
- Per-network reducer: grouping incl. SSID names + "Unknown", metrics per group, deterministic order.
- iOS gains: notification-rule → scheduled-notification mapping (fake center), diagnosis presentation, Starlink presentation.
- macOS gains: History ranges/metrics/sessions/per-network render from the kit; report card renders (PNG/PDF); host reconciliation round-trips both persistence shapes.
- No regression to Monitor/Hosts/Live Activity/widgets/overlay/menu-bar.

## §11 Milestones / cycles (sequence the refactor first)
1. **Extract `PingScopeHistoryKit`** — move pure History/metrics/map-reduction/report-presentation types out of `PingScopeiOS`; link from all three; fix imports; suite green on both platforms. (Pure refactor, high test coverage, no behavior change.)
2. **Network capture model** — top-level `networkInterface`/`networkName`/`isVPN` on `PingResult` (+ SQLite + CloudKit), cross-platform capture incl. SSID (entitlement + location), cellular radio type, VPN heuristic.
3. **Per-network reducer + iOS "By network" UI + macOS per-network table.**
4. **macOS rich History** — ranges/metrics/sessions surface on the kit.
5. **macOS report card + sharing.**
6. **iOS notifications engine.**
7. **iOS diagnosis UI + Starlink UI.**
8. **iOS diagnostics/log export + onboarding checklist.**
9. **Host-config reconciliation (shared host store).**
Each milestone: `swift build`, tests, both scheme builds; app usable; independently reviewable.

## §12 Open questions (defaults chosen)
- **Shared module name:** `PingScopeHistoryKit` (default) vs folding pure logic into `PingScopeCore`. Default a new kit so Core stays dependency-light and SwiftUI-free.
- **macOS History surface:** dedicated window vs Settings tab vs popover section. Default: a dedicated History window opened from the menu/popover (room for ranges + sessions + per-network + report).
- **SSID default:** capture when the entitlement + location are granted; otherwise fall back to "Wi-Fi" — no forced permission prompt outside the existing location opt-in.
- **iOS notification scope:** down/recovery/high-latency/internet-loss (match macOS); network-change alerts stay off by default (match macOS).
- **Maps on macOS:** out of scope (default). Revisit only if requested.
- **Sequencing:** the extraction refactor (M1) gates everything; it can ship on its own with zero behavior change first.
