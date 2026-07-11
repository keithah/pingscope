# iOS All Hosts and Multi-Host Live Activity

## Goal

Add an All Hosts selection to PingScope on iOS and represent that selection in
the Lock Screen Live Activity with up to three compact host rows. Each row shows
the host identity, endpoint, health color, recent sparkline, and colored latency
value. Single-host monitoring and its Live Activity remain focused on one host.

## Product Behavior

### Host Selection

- The iOS host switcher adds `All Hosts` ahead of configured hosts.
- The selection is persisted independently from the last concrete host ID.
- Selecting a host returns to the existing single-host monitor.
- Adding, editing, deleting, and reordering hosts preserves All Hosts selection.
- All Hosts displays configured hosts in their saved order, capped at three in
  ActivityKit surfaces. The in-app monitor may show every configured host.

### Monitoring

- Single-host mode continues using the existing `LiveMonitorSessionController`.
- All Hosts mode owns one controller per configured host and applies the same
  selected session duration to each controller.
- Start, stop, scene lifecycle, background expiration, and history flushing are
  coordinated as one user-visible session.
- Host edits reconcile the controller set without changing probe semantics.
- Existing probe, threshold, gateway, and persistence formats remain unchanged.

### In-App Monitor

- All Hosts uses the Signal presentation regardless of the persisted Ring mode,
  because a ring cannot represent multiple hosts.
- The hero graph overlays one colored series per host.
- A compact row for each host shows status dot, name and endpoint, sparkline,
  and a status-colored latency number. It does not repeat a health label.
- Selecting a row switches to that host's focused monitor.

## Live Activity Contract

`PingScopeLiveActivityAttributes.ContentState` gains a bounded array of host-row
snapshots. Each snapshot contains:

- Stable host ID, display name, endpoint caption, and health status.
- Optional latest latency in milliseconds.
- A bounded, reduced sequence of recent latency values for the sparkline.

At most three rows and twelve values per row are encoded. Failed samples are
represented without inventing latency values. The single-host scalar fields are
retained for decoding compatibility and focused Dynamic Island presentations.

The activity attributes identify whether the activity represents one host or
All Hosts. Activity updates are derived from immutable presentation snapshots;
the extension does not read shared defaults or query monitoring state.

## Activity Layouts

### Lock Screen

- Single host: one compact row using the same visual language.
- All Hosts: up to three rows, ordered like the host list.
- Each row contains a colored status dot, host name with endpoint beneath it,
  a small smoothed sparkline, and a colored monospaced `ms` value.
- Status text such as `Healthy` is omitted; color provides the glanceable cue.
- Session remaining/live state appears once for the activity, not per row.

### Dynamic Island

- Expanded All Hosts shows the same bounded rows in a denser layout.
- Compact and minimal regions remain intentionally concise and use aggregate
  status plus session state; they do not attempt to fit three host rows.
- Focused mode retains the current host and latency treatment, enhanced with a
  sparkline where space permits.

### Apple Watch

The repository has no watchOS target. ActivityKit may mirror the iPhone Live
Activity through system-provided watchOS surfaces, and the richer bounded state
will be available to that presentation. A custom Apple Watch layout is outside
this change and would require a dedicated Watch extension and separate design.

## Data Reduction and Color

- A pure reducer selects no more than twelve ordered latency samples per host.
- The reducer preserves the first and latest usable samples and evenly samples
  the interior without fabricating points.
- Sparklines use the shared `LatencyCurve` smoothing helper.
- Latency text and status dots use existing health colors: gray, green, yellow,
  and red. Endpoint and timestamp text remain secondary.

## Failure and Lifecycle Handling

- A host with no data shows a gray dot, an empty sparkline, and `--ms`.
- A failed or stale host keeps its last bounded graph but reports current
  down/stale state and does not imply a successful latest reading.
- If fewer than three hosts are configured, only available rows are encoded.
- If a host is removed during All Hosts monitoring, its controller is stopped
  and its row disappears on the next update.
- Activity update failures remain non-fatal to monitoring.

## Testing

- Persisted All Hosts selection and preservation through reorder/edit/delete.
- Start and stop fan-out across all host controllers without changing focused
  mode behavior.
- Stable configured-host ordering and three-row ActivityKit cap.
- Sparkline reduction for empty, short, long, and failed-sample series.
- Correct status color and latency presentation for all health states.
- Content-state Codable round trips for focused and All Hosts payloads.
- Existing run controls, startup coordination, widgets, and Live Activity tests
  remain green.

## Verification

- `swift build` and `swift test`.
- Generic iOS Simulator and macOS scheme builds.
- Existing iOS validation and simulator smoke scripts.
- Simulator interaction: select All Hosts, start/stop each duration, switch back
  to a host, reorder hosts, and inspect the Lock Screen Live Activity.
- Confirm ActivityKit payload size remains comfortably below system limits.

## Non-Goals

- No new probe engine or monitoring protocol.
- No new persistence format for host configurations or history.
- No external dependency.
- No dedicated watchOS application or Watch extension in this change.
