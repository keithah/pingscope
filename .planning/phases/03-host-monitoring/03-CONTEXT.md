# Phase 3: Host Monitoring - Context

**Gathered:** 2026-02-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Multi-host monitoring with per-host configuration. Users can monitor Google DNS, Cloudflare, auto-detected gateway, and custom hosts. Each host can have its own ping method and settings. Default hosts are protected; custom hosts can be added, edited, and deleted.

</domain>

<decisions>
## Implementation Decisions

### Host list UX
- Flat list of all hosts (no separate sections for defaults vs custom)
- Defaults have a subtle indicator (lock icon or similar) showing they can't be deleted
- Active host (shown in menu bar) indicated with checkmark
- Each host row shows: name + current latency (e.g., "Google DNS • 12ms")

### Per-host settings
- Global defaults apply to all hosts
- Per-host override only when explicitly set by user
- Configurable per host: ping interval, timeout, latency thresholds (green/yellow/red), ping method (TCP/UDP/ICMP)
- Responsive defaults: 2s interval, 2s timeout, thresholds at 50/150ms

### Default gateway behavior
- Network-aware naming: "Home Wi-Fi Gateway" if network name available, otherwise shows IP
- Continuous monitoring for network changes — gateway updates in real-time
- Brief "Network changed" indicator in menu bar when network switches
- When no network available: gateway shows as gray/unavailable, skipped from monitoring

### Add/edit host flow
- "+" button opens a dedicated sheet/modal for adding hosts
- Required fields: hostname/IP address and display name
- Optional fields use global defaults (interval, timeout, thresholds, method)
- Test ping before saving — warn if unreachable but allow save anyway
- Delete requires confirmation dialog

### Claude's Discretion
- Whether all hosts ping in parallel or only active host (resource/UX tradeoff)
- How per-host overrides are visually indicated
- Sheet layout and field arrangement for add/edit flow
- Exact styling of "Network changed" indicator

</decisions>

<specifics>
## Specific Ideas

- Responsive feel: 2-second interval gives quick feedback without hammering the network
- Network-aware gateway naming makes it clear which network you're on
- Test ping on add catches typos early but doesn't block saving (user might be adding a host they'll connect to later)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-host-monitoring*
*Context gathered: 2026-02-14*
