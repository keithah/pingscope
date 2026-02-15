# Project State

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-02-13)

**Core value:** Reliable, accurate ping monitoring that users can trust — no false timeouts, no stale connections, no crashes.
**Current focus:** Phase 6 - Notifications & Settings

## Current Position

Phase: 6 of 6 (Notifications & Settings) - IN PROGRESS
Plan: 3 of 6 in phase 6
Status: Phase 6 in progress
Last activity: 2026-02-15 - Completed 06-03-PLAN.md

Progress: [█████████░] 90% (28 of 31 plans complete)

## Performance Metrics

**Velocity:**
- Total plans completed: 28
- Average duration: 2 min
- Total execution time: 1.09 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Foundation | 4 | 4 | 2 min |
| 2. Menu Bar & State | 4 | 4 | 3 min |
| 3. Host Monitoring | 9 | 9 | 2 min |
| 4. Display Modes | 5 | 5 | 3 min |
| 5. Visualization | 3 | 3 | 2 min |
| 6. Notifications & Settings | 3 | 6 | 3 min |

**Recent Trend:**
- Last 5 plans: 05-02 (1 min), 05-03 (human verify), 06-01 (4 min), 06-02 (2 min), 06-03 (3 min)
- Trend: Stable

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- (init): Use Swift Concurrency over GCD semaphores to eliminate race conditions
- (init): Modular file structure over single file for maintainability
- (init): Defer widget to v2 to focus on core app stability
- (01-01): Used Duration instead of TimeInterval for type-safe timing
- (01-01): All models conform to Sendable for actor isolation
- (01-02): Use fresh NWConnection instances per measurement for reliability
- (01-02): Timeout racing uses withThrowingTaskGroup with immediate loser cancellation
- (01-02): pingAll default concurrency limit remains 10
- (01-03): Host down state requires 3 consecutive failures tracked per host
- (01-03): Connection sweeper defaults to 10-second cadence with 30-second max age
- (01-03): Ping scheduling spreads execution across 80% of interval with cancel-before-restart updates
- (01-04): PingService tests use real DNS endpoints to verify timeout racing and pingAll behavior
- (01-04): Timeout assertions use bounded tolerance windows to avoid flaky scheduling-edge failures
- (01-04): ConnectionSweeper tests use short 100ms/200ms timing for deterministic fast cleanup checks
- (02-01): Menu status thresholds use <=80ms for green and reserve red for sustained failures
- (02-01): Sustained failure threshold for red status is 3 consecutive failures
- (02-01): Display text smoothing uses bounded EMA (alpha 0.35, max step 40ms)
- (02-03): Popover section order is fixed as status first, quick actions second
- (02-03): Popover snapshot sanitizes blank or missing host/latency to N/A
- (02-02): Render status dot with SF Symbol tint and keep title compact to preserve menu-bar width
- (02-02): Route ctrl-click and cmd-click through the same context-menu path as right-click
- (02-02): Build menu sections from runtime state and persist mode toggles with a dedicated preference store
- (02-04): Status item uses a non-template drawn dot plus centered stacked text for reliable menu-bar contrast
- (02-04): Compact mode changes are observed alongside scheduler state so status rendering updates immediately
- (02-04): Settings action first tries showSettingsWindow and falls back to a dedicated NSWindow in accessory mode
- (03-01): Use responsive global defaults of 2s interval/timeout and 50ms/150ms thresholds for host monitoring
- (03-01): Preserve Host decode compatibility for legacy protocolType/timeout persisted payloads
- (03-02): Detect default gateway from sysctl route table and avoid NWPath gateway fields for stability
- (03-02): Debounce connected-path gateway updates at 200ms but emit unavailable immediately on disconnect
- (03-03): Route icmpSimulated through dedicated host-level probe sequencing across ports 53/80/443/22/25
- (03-03): Keep single-port ping overload limited to tcp/udp paths with explicit icmpSimulated misuse failure
- (03-04): Persist host lists with JSONEncoder/JSONDecoder while excluding the ephemeral gateway host
- (03-04): Enforce default-host restoration and default->gateway->custom host ordering from HostStore
- (03-05): Represent row latency with tri-state mapping (missing=blank, nil=Failed, value=ms text)
- (03-05): Keep host-row indicator slots fixed-width so checkmark/lock toggles do not shift row content
- (03-06): Keep add/edit sheet save gating tied to required fields; test ping failures warn but do not block save
- (03-06): Persist per-host interval/timeout/threshold overrides only when their custom toggles are enabled
- (03-07): Embed host list management directly in the popover for one-click host operations
- (03-07): Drive scheduler host targets from HostStore so add/remove changes apply immediately
- (03-07): Surface gateway churn via a brief runtime network change indicator
- (03-08): Schedule pings per host using Host.effectiveInterval with a runtime global fallback instead of one shared loop interval
- (03-08): Keep stagger behavior for concurrently due hosts while allowing shorter-interval hosts to run more frequently
- (03-08): Add deterministic PingScheduler cadence tests using injected ping and health test doubles
- (03-09): Pass effective green/yellow thresholds into menu status evaluation on each update instead of static bounds
- (03-09): Recompute menu status immediately when selected host changes so threshold boundary updates are instant
- (04-01): Persist display state as one Codable payload split into shared/full/compact partitions
- (04-01): Keep deterministic mode defaults with full (450x500) and compact (280x220) frame data
- (04-01): Expose focused DisplayPreferencesStore APIs for shared and per-mode updates
- (04-02): Use one DisplayViewModel to preserve selected host/time range across mode switches while panel visibility persists per mode
- (04-02): Keep bounded per-host sample buffers and project recent results newest-first for full/compact history surfaces
- (04-03): Re-anchor floating shell from status-item screen rect on each open/mode handoff and clamp to active visibleFrame
- (04-03): Enforce current-Space floating behavior with collectionBehavior [.transient, .moveToActiveSpace] and no all-spaces flags
- (04-03): Keep floating movement handle-only by leaving isMovableByWindowBackground disabled
- (04-04): Delegate status-item open/close through DisplayModeCoordinator so mode and shell toggles re-anchor active presentation consistently
- (04-04): Bind settings display toggles to menuBar.mode persisted keys and route writes through AppDelegate runtime setters
- (04-04): Preserve display selected host/time range across compact/full switches by reusing a single app-lifecycle DisplayViewModel
- (04-05): Host pill status indicators derive from most recent ping result per host instead of hardcoded green
- (06-01): Persist per-host notification overrides in NotificationPreferences as a [UUID: HostNotificationOverride] dictionary for efficient lookup
- (06-02): Intermittent failures count uses a time window (seconds) because failures are stored as timestamps
- (06-02): Per-host enabled alert types are intersected with global enabled alert types (overrides can restrict but not expand)
- (06-03): Host.notificationsEnabled defaults to true and decodes missing values as true for backwards compatibility

### Pending Todos

None.

### Blockers/Concerns

None.

## Session Continuity

Last session: 2026-02-15T20:14:24Z
Stopped at: Completed 06-03-PLAN.md
Resume file: None
