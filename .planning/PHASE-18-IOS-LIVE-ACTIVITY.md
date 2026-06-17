# Phase 18 - iOS Live Activity Preparation

Status: design approved
Target milestone: `0.3.0 - iOS Preparation`

## Goal

Prepare PingScope for an iOS companion app that can run a short, user-started latency monitor session and display it as a Live Activity.

The first version is intentionally narrow:

- Session durations: `30s` default, `1m` optional.
- Monitoring is live while PingScope is open.
- Monitoring may continue briefly after backgrounding only while iOS grants finite background runtime.
- The Live Activity must clearly become stale when fresh local measurements stop.

## Non-Goals

- No always-on iOS ping loop.
- No claim that a Live Activity keeps the app alive.
- No 5m, 15m, 1h, or 8h local monitoring sessions.
- No server push update path.
- No ICMP support for iOS App Store builds.
- No full iOS product UI beyond the shell needed to compile and validate the session model.

## Platform Constraints

Live Activities provide persistent system UI, not unlimited app execution. PingScope can update a Live Activity while it is running in foreground, while it has finite background time, or through a future push infrastructure. Because PingScope measures latency locally and has no server push path, Live Activity updates must be treated as best-effort after the app leaves foreground.

The iOS app must use a finite background task only to finish an already-started short monitor session. The session ends early if the iOS expiration handler fires.

Local network hosts, including default gateway monitoring, require iOS local-network privacy permission and clear usage copy.

## User Model

The user opens PingScope on iPhone, chooses a host, and taps a Live Monitor control.

Available durations:

- `30s` - default, best fit for iOS background limits.
- `1m` - useful when the app stays open, may end early in background.

The Live Activity shows:

- Host display name.
- Latest latency or failure state.
- Status color.
- Last updated age.
- Remaining session time.
- Stale state when no sample has arrived recently.

State rules:

- `live`: latest sample is no more than 10 seconds old.
- `stale`: latest sample is more than 15 seconds old, or iOS background runtime expired.
- `ended`: selected duration elapsed, user stopped the session, or iOS expiration handler fired.

## Architecture

Add platform-neutral session types to `PingScopeCore`:

- `MonitorSessionDuration`: `.thirtySeconds`, `.oneMinute`.
- `MonitorSessionState`: host id, duration, start date, end date, latest result, freshness state.
- `MonitorSessionPolicy`: interval, stale threshold, and timeout rules.

Add an iOS app shell target later in Phase 18:

- Depends on `PingScopeCore`.
- Uses TCP/UDP probes only.
- Starts a short runtime session when the user taps Live Monitor.
- Updates ActivityKit while the app has runtime.

Add ActivityKit types in an iOS/widget extension target:

- `PingScopeLiveActivityAttributes`.
- Content state with latency, status, last update, remaining time, and stale flag.
- Compact Lock Screen/Dynamic Island layout after compile plumbing works.

macOS behavior must not regress. Existing macOS menu bar, overlay, widgets, history, and App Store/Developer ID build flavors remain unchanged.

## Battery Position

The default 30-second session is the battery-safe product shape. A TCP probe every 2 seconds for a short, explicit session is reasonable. PingScope should stop probing immediately when the session ends or iOS asks the app to expire its background task.

The app must not attempt to keep the radio alive indefinitely.

## Testing

Core tests:

- Session duration values are fixed at 30 seconds and 60 seconds.
- Freshness transitions from `live` to `stale` after the stale threshold.
- Session ends at selected duration.
- Session ends early on explicit expiration.

Compile/build checks:

- `swift test` remains green.
- Existing macOS Xcode schemes still build.
- iOS shell target compiles once introduced.
- ActivityKit target compiles once introduced.

Manual checks on device:

- Starting a 30-second session creates a Live Activity.
- Foreground session updates latency.
- Backgrounding the app continues only briefly and then marks stale or ends.
- Local network prompt appears only when monitoring a local host.
- No excessive battery or heat during repeated 30-second sessions.

## Acceptance Criteria

- Product copy and code do not imply continuous iOS background monitoring.
- Users can choose `30s` or `1m`, with `30s` as default.
- The Live Activity never shows stale latency as if it were current.
- PingScope stops probing when the selected duration ends or iOS expires background runtime.
- The Mac app remains buildable and behaviorally unchanged.
