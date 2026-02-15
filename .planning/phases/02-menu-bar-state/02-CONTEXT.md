# Phase 2: Menu Bar & State - Context

**Gathered:** 2026-02-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver menu bar status display and interaction for PingMonitor: color-coded status dot, real-time ping value display, left-click popover/window access, and right-click context menu with host switching, mode toggles, Settings, and Quit. This phase clarifies behavior within that boundary and does not add new capabilities.

</domain>

<decisions>
## Implementation Decisions

### Status color rules
- `green` means healthy/acceptable latency range (not only best-case low latency).
- `yellow` means warning latency while still receiving responses.
- `red` means sustained failure, not a single failed ping.
- `gray` is used for both startup/no-data and intentionally inactive states.

### Menu bar text behavior
- Menu bar display shows only latency text (`## ms`) with no host name.
- Presentation should stay compact so it does not consume extra menu bar width.
- When unavailable, latency text is `N/A`.
- Value updates should be smoothed to reduce visual jitter.

### Left-click experience
- Left-click opens a popover (not a standard window for this phase).
- Left-click behaves as a toggle: click again closes the open popover.
- First-open content emphasis should be balanced between current status and quick actions.
- If right-click is used while left-click UI is open, keep the left UI open and also show the context menu.

### Right-click menu structure
- Top-to-bottom grouping is host controls first, then mode controls.
- Host control style is "current host + switch" (not a full inline host list).
- Mode toggle presentation should mirror the old app style shown in `~/src/old_pingmonitor` screenshots.
- `Settings` and `Quit` appear at the bottom with a separator above.

### Claude's Discretion
- Exact numeric latency thresholds for green/yellow/red transitions.
- Exact smoothing strategy for menu bar text updates.
- Exact visual implementation details for replicating old mode-toggle style.

</decisions>

<specifics>
## Specific Ideas

- "ms is below the dot" style intent: keep the status + latency readout visually compact in the menu bar.
- Use old app screenshots in `~/src/old_pingmonitor` as the reference for mode toggle look/behavior.

</specifics>

<deferred>
## Deferred Ideas

None - discussion stayed within phase scope.

</deferred>

---

*Phase: 02-menu-bar-state*
*Context gathered: 2026-02-14*
