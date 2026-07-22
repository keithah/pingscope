# Battery-aware adaptive monitoring — design

Date: 2026-07-21

## Problem

PingScope monitors continuously with a fixed cadence and **zero power-state
awareness**. The scheduler in `MeasurementScheduler.runLoop` probes every
enabled host on a `Task.sleep(host.interval)` loop 24/7, regardless of whether
the machine is on battery, thermally throttled, in Low Power Mode, backgrounded,
or has its display asleep. Concretely:

- Default gateway interval is 2s (`Domain.swift`), internet hosts 5s; the floor
  is 250ms.
- Each host runs an **independent** sleep loop staggered by `offset * 250ms`
  (`Runtime.swift`), which defeats CPU idle and radio-tail collapse — the radio
  and CPU never settle between probes.
- No `isLowPowerModeEnabled`, no `thermalState`, no battery-vs-AC, no
  display-sleep / lock / background detection anywhere in the tree.
- On iOS, background monitoring is kept alive with **continuous**
  `CLLocationManager` updates (`startUpdatingLocation`,
  `allowsBackgroundLocationUpdates = true`,
  `pausesLocationUpdatesAutomatically = false`) — a well-known heavy battery
  sink that keeps the location subsystem powered whenever the app is
  backgrounded.

## Goals

- Adapt probe cadence to power / thermal / visibility state, uniformly, without
  special-casing conditions in the scheduler.
- Coalesce wakeups so probes fire in aligned bursts and the machine can sleep
  between them.
- Reduce the iOS background location drain.
- Preserve correctness of outage detection (never so slow that outages are
  missed; a hard ceiling guarantees this).

## Non-goals (deferred — "more functionality later")

- `BGAppRefreshTask` / `BGProcessingTask` for stationary iOS background
  monitoring. Documented as the follow-up that restores uninterrupted
  background monitoring; not in this change.
- Changing user-selectable probe *methods* (e.g. auto-swapping ICMP for
  in-process TCP). Method is user-facing; out of scope.
- Per-host user-configurable power policies. One global policy for now.

## Design

### 1. Cadence engine (platform-agnostic, Core)

A single value maps a host's configured interval to an effective interval given
the current environment. No per-condition branching leaks into the scheduler.

```
struct CadenceInputs: Sendable, Equatable {
    var visibility: Visibility        // .activeUI | .idleForeground | .background
    var powerSource: PowerSource      // .ac | .battery | .unknown
    var isLowPowerMode: Bool
    var thermalTier: ThermalTier      // .nominal | .fair | .serious | .critical
}
```

The effective multiplier is the **maximum** across independent axes
(most-conservative axis wins — bounded, predictable, and simple to test; avoids
compounding multiple factors into absurd intervals):

| Axis            | Factors |
|-----------------|---------|
| Visibility      | activeUI 1× · idleForeground 2× · background 4× |
| Power           | AC 1× · battery 2× · unknown 1× |
| Low Power Mode  | off 1× · on 4× |
| Thermal         | nominal/fair 1× · serious 4× · critical 8× |

```
effectiveInterval(base) = clamp(base × multiplier, low: base, high: 300s)
```

- **Floor = base**: adaptive backoff never probes *faster* than the user's
  configured interval.
- **Ceiling = 300s**: even fully constrained, an outage is caught within 5
  minutes.
- **Timeout is not scaled** — scaling it would degrade measurement accuracy for
  little energy gain.

`CadenceInputs.default` = all-nominal (multiplier 1×), so an environment that
reports nothing behaves exactly like today (minus the raised default, item 3).

Lives in a new `Sources/PingScopeCore/MonitoringCadence.swift`. Pure value +
pure function; unit-tested in isolation.

### 2. Coalesced, deadline-based scheduling (Core, `MeasurementScheduler`)

Replace the per-host relative-sleep loop with **absolute deadlines aligned to a
1s quantum**:

- On each iteration compute `effectiveInterval` from `host.interval` and the
  current `CadenceInputs`, then set the next deadline to
  `alignUp(now + effectiveInterval, quantum: 1s)` on a `ContinuousClock`, and
  sleep until that deadline.
- Aligning to a shared grid makes independent hosts wake together (one burst,
  then a long quiet gap), which is what lets the radio drop to low power and the
  CPU idle.
- The initial `offset * 250ms` stagger is **removed** — alignment supersedes it.

Cadence-change propagation: the scheduler holds the current `CadenceInputs`.
`setCadenceInputs(_:)` on the scheduler (forwarded from
`PingRuntime.setCadenceInputs`) stores them; if the effective **tier changed**,
the running loops are restarted (reusing the existing generation/cancel
machinery). This makes "plug in" / "open the popover" speed up immediately and
delivers a fresh probe on that transition, rather than waiting out a possibly
5-minute slow interval. Tier changes are infrequent, so restart cost is
negligible.

Recompute-each-iteration also means a *slower* tier takes effect on the next
natural cycle without a restart.

### 3. Raised default cadence (Core, `Domain.swift`)

Gateway default interval **2s → 5s**. Internet hosts remain 5s. Floor stays
250ms for power users who set it explicitly. This is the baseline saving;
adaptive backoff (items 1–2) layers on top.

### 4. macOS power/activity monitor (App)

New `MacPowerActivityMonitor` (App target) observes and debounces into
`CadenceInputs`, pushed to the runtime via `PingRuntime.setCadenceInputs`:

- `NSWorkspace.screensDidSleep/DidWake` → visibility `.background` while asleep.
- Distributed `com.apple.screenIsLocked` / `...Unlocked` → `.background` while
  locked.
- Popover / overlay visibility (already tracked in `PingScopeApp`) → `.activeUI`
  when shown, `.idleForeground` otherwise.
- IOPS power source (`IOPSNotificationCreateRunLoopSource`) → `.ac` / `.battery`.
- `ProcessInfo.thermalStateDidChangeNotification` → `thermalTier`.
- `NSProcessInfo.processInfo.isLowPowerModeEnabled` +
  `NSProcessInfoPowerStateDidChange` → `isLowPowerMode`.

Visibility is the max-conservative of (screen asleep/locked ? .background) and
(popover shown ? .activeUI : .idleForeground).

### 5. iOS power/activity + location rework (iOSApp)

- New `PowerActivityMonitor` (iOS): `scenePhase` (foreground → `.activeUI` /
  background → `.background`), `isLowPowerMode` + power-state notification,
  `thermalState`. iOS has no user-facing AC/battery distinction we need; leave
  `powerSource = .unknown`. Pushed to the runtime like macOS.
- Rework `BackgroundLocationKeepAliveController`:
  `startUpdatingLocation()` → `startMonitoringSignificantLocationChanges()`,
  and drop the continuous-update configuration (`distanceFilter`,
  `pausesLocationUpdatesAutomatically`). This removes the continuous-location
  drain while preserving relaunch-after-terminate.
- The keep-alive remains behind the existing `backgroundKeepAliveEnabled`
  opt-in toggle; when off, the app suspends normally in the background (the
  most battery-preserving state).

**Known limitation (documented, accepted):** significant-location-change only
wakes the app on ~500m movement, so a *stationary* user's background monitoring
is reduced versus continuous location. Restoring uninterrupted stationary
background monitoring is the deferred `BGAppRefreshTask` follow-up (non-goal
above).

## Data flow

```
[platform monitors] --CadenceInputs--> PingRuntime.setCadenceInputs
    --> MeasurementScheduler.setCadenceInputs (store; restart loops if tier changed)
    --> runLoop: effectiveInterval(host.interval, inputs) --> aligned deadline sleep
```

The scheduler stays the single point that turns "environment" into "when to
probe next." Platform code only *reports* state; it never reaches into probe
timing.

## Error handling

- Missing/failed platform signals default to the nominal axis value (1×), i.e.
  today's behavior — never faster, never a crash.
- `effectiveInterval` clamps both ends, so no pathological input (0, negative,
  huge multiplier) can produce a busy-loop or an unbounded sleep.
- Location authorization loss on iOS already handled by the existing delegate;
  significant-change simply stops. No new failure path.

## Testing

- **Cadence engine** (`MonitoringCadenceTests`): multiplier is the max across
  axes; floor/ceiling clamping; `.default` == 1×; representative combinations
  (battery+background, low-power, thermal critical).
- **Scheduler** (extend `LiveMonitorSessionController` / scheduler tests with the
  existing `ManualClock`): deadlines align to the quantum; tier change restarts
  loops and re-probes; slower tier applies next cycle; effective interval never
  below base.
- **macOS/iOS monitors**: inject the notification/state sources; assert they map
  to the expected `CadenceInputs` (no live NSWorkspace/CLLocationManager in
  tests).

## Phasing

1. Core: cadence engine + coalesced scheduler + raised default. (TDD)
2. macOS power/activity monitor + wiring.
3. iOS power/activity monitor + significant-change location rework.

Each phase is independently testable and shippable.
