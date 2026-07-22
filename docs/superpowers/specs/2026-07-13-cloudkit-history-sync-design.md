# PingScope CloudKit Sync — History + Hosts across macOS & iOS

## Objective

Sync PingScope latency **history** and the **monitored host list** between the macOS and iOS apps through the user's **private iCloud database**, so history recorded on one device appears on the other. Per the approved decisions this includes **map coordinates**, **all raw 30-day history**, and the **host list**. The monitoring engine, probe cadence, Live Activity, widgets, and background runtime are unchanged except where they read/write the store or host list.

## Resolved decisions (from design review)
- **Coordinates ARE synced** → the shipped "coordinates never leave the device" guarantee is retired; `PRIVACY.md`/`README.md` and an in-app disclosure must be updated (see §9).
- **All raw 30-day history syncs** (not downsampled). This is high volume; §7 defines the batched-backfill + throttling mitigations that make it survivable. (Accepted with the scale caveat.)
- **Host list syncs** in addition to history.
- **Mechanism:** `CKSyncEngine` (private DB), not `NSPersistentCloudKitContainer` (which would force a Core Data migration away from the hand-rolled `SQLiteHistoryStore`).

## §0 Ground truth
- Two independent local stores today: macOS `SQLiteHistoryStore(url: defaultURL())` (`PingScope`, retention `.days(7)`); iOS `defaultURL(appName: "PingScope-iOS")`, retention `.days(30)`. No app group, no CloudKit, no iCloud entitlement anywhere.
- `ping_samples` (`Sources/PingScopeCore/HistoryStore.swift`): `id TEXT PRIMARY KEY` (UUID), `host_id, address, method, port, timestamp, latency_ms, failure_reason, metadata_note, metadata_json, latitude, longitude, horizontal_accuracy, network_name, network_interface`. Serial-`DispatchQueue` worker; `addColumnIfNeeded` idempotent migrations; `PingHistoryStore` protocol: `append`, `appendAndWait`, `samples(hostID:since:limit:)`, `latestSamples`, `exportSamples`, `prune(olderThan:)`.
- `HostConfig` (`Domain.swift`) is fully `Codable`: `id, displayName, address, tier, method, port, interval, timeout, thresholds, isEnabled, notifications`.
- Host persistence differs per platform: macOS `HostConfigPersistence` (`UserDefaults` `hostConfigs` JSON); iOS `PingScopeIOSHostStore` (`UserDefaults` `PingScope.iOS.hosts` JSON + `selectedHostID`, `hostScope`).
- Platforms: `macOS 15`, `iOS 18` — `CKSyncEngine` (macOS 14+/iOS 17+) available on both. Bundle id `com.hadm.PingScope` on both AppStore targets; macOS also ships a DeveloperID (direct) build.

## §1 Scope & non-goals
**In scope:** a new shared sync layer using `CKSyncEngine`; mirroring `ping_samples` and host configs to/from the CloudKit private DB; local-store integration (merge-by-id, change tracking); retention reconciliation; an opt-in sync setting + disclosure; entitlements/plist and manual-provisioning documentation; tests behind a fake-sync seam.

**Non-goals / unchanged:** probe/gateway/monitoring cadence, Live Activity, widgets, background runtime; the CloudKit *public/shared* databases (private only); Windows/watch; conflict UX beyond last-writer/union merge; migrating the store to Core Data. No third-party dependencies.

## §2 Module boundary
Add a new SwiftPM target **`PingScopeCloudSync`** that depends on `PingScopeCore` and imports `CloudKit`, used by both `PingScopeApp` and `PingScopeiOSApp`. **`PingScopeCore` must not import `CloudKit`** — it stays platform-neutral; the sync engine lives in `PingScopeCloudSync`, reading/writing history through the existing `PingHistoryStore` protocol (extended minimally, §5) and host configs through a small injected adapter. UI (settings toggle) lives in each app target.

## §3 CloudKit model
- **Container:** `iCloud.com.hadm.PingScope` (private database). One custom **record zone** `PingScopeHistory` (custom zone → enables `CKSyncEngine` change tracking + zone-wide operations/deletes).
- **Record types:**
  - `PingSample` — recordName = the sample's UUID `id` (string). Fields mirror `ping_samples` columns: `hostID`, `address`, `method`, `port`, `timestamp`, `latencyMs`, `failureReason`, `metadataNote`, `metadataJSON`, `latitude`, `longitude`, `horizontalAccuracy`, `networkName`, `networkInterface`. All optional except `hostID`/`timestamp`.
  - `MonitoredHost` — recordName = host UUID `id`. Field `configJSON` = the `HostConfig` Codable blob (plus a `modifiedAt` for last-writer-wins). One record per host keeps updates/deletes granular.
- **Keying/merge:** recordName = domain UUID, so both devices converge by id (union). Server-record-changed conflicts resolve last-writer-wins by `timestamp`/`modifiedAt`; `PingSample`s are effectively immutable (append-once) so conflicts are rare.

## §4 Sync engine
`CKSyncEngine` (one per app process) with a delegate that:
- **Outgoing:** on local `append`/host-edit, records the changed id in a pending-changes set; `CKSyncEngine` requests the batch and the delegate materializes `CKRecord`s from the store/host list. Deletes: host removals propagate as record deletes (user intent); history prunes do **not** (see §6).
- **Incoming:** applies fetched `PingSample` records into `SQLiteHistoryStore` via a new idempotent upsert (INSERT OR REPLACE by id, already the insert mode) tagged origin=remote so re-sync loops are avoided; applies `MonitoredHost` records into the platform host store, reconciling by id.
- **State:** persist `CKSyncEngine.State.Serialization` locally (a small file next to the store, or a `sync_state` table) so change tokens survive launches. Handle `CKSyncEngine.Event` account-change/zone-deleted by resetting state and re-backfilling.

## §5 Local-store integration (minimal Core additions)
- Add to `PingHistoryStore`: `changedSamples(since cursor:)`/a monotonic change cursor **or** a lightweight `dirty` flag + `markSynced`, so the outgoing path can find rows needing upload without diffing the whole table. Smallest viable: a `synced INTEGER DEFAULT 0` column (via `addColumnIfNeeded`) set to 1 after successful upload; incoming remote rows are inserted with `synced = 1`. Add `upsertRemote(_ samples:)` that writes without re-marking dirty.
- The write path (`LiveHistoryWriteBuffer` → `append`) notifies the sync layer of new local ids (callback/AsyncStream injected from the app), so `CKSyncEngine.sendChanges` is scheduled. Keep this additive and off the monitoring hot path.

## §6 Retention reconciliation (critical for "all 30 days")
- When sync is enabled, **both stores use `.days(30)` retention** (raise macOS from 7→30 while sync is on) so a device doesn't prune rows the other just sent, causing re-fetch churn.
- **Local retention prune must NOT emit CloudKit deletes.** Pruning is a local storage bound; deleting the record would wipe it from the peer. Prune locally only; the record stays in CloudKit until it ages out of the 30-day window on the *origin* device's re-evaluation, or is never deleted (accept slow CloudKit growth, bounded by the 30-day producing window). Document this; a future cleanup job can delete records whose `timestamp` is older than 30 days from *all* devices, but that is out of scope now.
- Host deletes are explicit and DO propagate.

## §7 Scale & initial backfill ("all raw 30 days")
- First enable performs a **batched backfill**: enumerate un-synced rows newest-first in chunks (e.g. 200–400 records/batch, CloudKit's per-request limit is 400), hand them to `CKSyncEngine`, and rely on its built-in rate-limit backoff/retry. Backfill is **resumable** (the `synced` flag is the cursor) and runs off the main actor at low priority.
- Expect the first sync of a densely-populated 30-day store to be long and network/battery heavy; surface progress and let the user pause. Ongoing steady-state sync is small (only new samples). This is the accepted cost of the "all raw" choice; if it proves impractical in testing, the fallback is a bounded window or roll-ups (a follow-up, not this change).
- Never block monitoring or the History UI on sync.

## §8 Settings & UX
**Hard invariant:** no history, coordinates, network name/SSID, or host config leaves either device unless the user has explicitly enabled iCloud Sync. Sync is **off by default**; enabling it requires an affirmative user action plus a one-time disclosure of what syncs and that it uses the user's private iCloud. `CKSyncEngine` must never be started, and no `CKRecord` ever created/uploaded, while the toggle is off. Disabling sync stops the engine immediately (local data retained). This invariant is covered by a test asserting no upload path runs when disabled.

- New **opt-in** "iCloud Sync" toggle (default **off**) in macOS Settings and the iOS Monitor settings sheet, with a one-time disclosure that history and coordinates are stored in the user's private iCloud. Enabling triggers backfill; disabling stops the engine (local data retained). Show sync status (idle/syncing/error, last-synced) and an account-unavailable state (not signed into iCloud).

## §9 Privacy, entitlements & provisioning (some steps are manual)
- **Docs:** rewrite the `PRIVACY.md`/`README.md` coordinate line — replace "coordinates remain local … unless you explicitly share an export" with an accurate statement: when iCloud Sync is enabled, history (including approximate coordinates) is stored in the user's **private** iCloud and synced to their devices; it is not shared with anyone else and sync is off by default.
- **Entitlements (I can write these):** add to both app entitlements `com.apple.developer.icloud-container-identifiers = [iCloud.com.hadm.PingScope]`, `com.apple.developer.icloud-services = [CloudKit]`, and `com.apple.developer.ubiquity-kvstore-identifier` only if KVS is used (not planned). Add the `remote-notification` background mode so `CKSyncEngine` push wakes are delivered.
- **Manual (you, in Xcode / CloudKit dashboard):** create the `iCloud.com.hadm.PingScope` container; enable the iCloud + CloudKit + Push capabilities on the macOS (incl. DeveloperID) and iOS targets with correctly-signed provisioning profiles; define the `PingScopeHistory` zone and record types (or let first run create them), and add the queryable indexes (`timestamp`, `hostID`, `recordName`). CKSyncEngine needs an APS push environment for change notifications.

## §10 Testing (behind a fake-sync seam)
Introduce a protocol seam over the CloudKit surface (`CloudDatabase`/`SyncScheduler`) so logic is unit-testable without a live account:
- Record↔row mapping round-trips for `PingSample` (incl. location + nil fields) and `MonitoredHost`.
- Merge-by-id union; idempotent remote upsert (no dup rows, no re-dirty loop); last-writer-wins on host edits by `modifiedAt`.
- Backfill batching: chunk sizes ≤ limit, resumable via `synced` cursor, newest-first ordering.
- Retention reconciliation: local prune does not enqueue CloudKit deletes; host delete does.
- Account/zone events reset state and re-backfill.
- Sync-state serialization survives a round trip.
Manual: two-device (or device+simulator, same iCloud account) sync of a seeded store; verify convergence, host add/edit/delete propagation, and no monitoring regression.

## §11 Milestones (each: `swift build`, tests; app usable)
1. `PingScopeCloudSync` target + CloudKit model types + record↔row/host mappers (pure, fully tested).
2. Store integration: `synced` column, `upsertRemote`, change-notification hook, retention→30d when enabled (Core-additive, tested).
3. `CKSyncEngine` wiring behind the seam: outgoing/incoming/state, delegate events (tested with fake).
4. Backfill (batched, resumable, throttled) + progress.
5. Settings toggle + disclosure + status UI (macOS + iOS) + privacy-doc rewrite.
6. Entitlements/plist + provisioning doc; end-to-end manual two-device verification.

## §12 Open questions (defaults chosen)
- **Sync default:** off (opt-in) — safer for a privacy-affecting iCloud feature; flip to on only if you want it enabled out of the box. (Human call.)
- **CloudKit record cleanup for aged-out samples:** deferred (accept bounded growth within the 30-day producing window).
- **DeveloperID macOS CloudKit:** confirm the direct-distribution build can be signed with the iCloud container (App Store build is straightforward; DeveloperID needs the capability on the profile). (Human/provisioning call.)
- **If "all raw 30 days" proves impractical in testing:** fall back to a bounded window or roll-ups — a separate follow-up, not this change.
