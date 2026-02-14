# Phase 1: Foundation - Context

**Gathered:** 2026-02-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Establish correct async patterns and connection lifecycle management. Build the PingService that measures TCP/UDP connection latency using async/await, handles timeouts accurately, and cleans up connections properly. This is the foundation that prevents race conditions and stale connections.

</domain>

<decisions>
## Implementation Decisions

### Timeout behavior
- Immediate failure when deadline passes — don't wait for late responses
- 3 consecutive failures required before marking host as down (reduces false positives)
- Default timeout duration: 3 seconds per ping

### Connection cleanup
- Claude's discretion on fresh vs pooled connections (choose based on reliability vs performance)
- Immediate cleanup after ping completes (success or failure) — no lingering resources
- Periodic sweep mechanism to catch orphaned connections that weren't cleaned up
- Cancel all active connections immediately when app is suspended/backgrounded

### Concurrency model
- Staggered pings across the interval (spread to avoid bursts)
- Cancel and restart when host list changes mid-cycle
- Maximum 10 concurrent pings to limit resource usage
- Cancel and restart when user triggers manual refresh while pings are running

### Claude's Discretion
- Connection pooling vs fresh connections (choose based on reliability needs)
- Exact stagger timing between hosts
- Orphan sweep interval timing

</decisions>

<specifics>
## Specific Ideas

- Previous implementation had race conditions with DispatchSemaphore — this rewrite uses async/await exclusively
- Stale connections were accumulating — immediate cleanup + periodic sweep should prevent this
- The 3-consecutive-failure threshold mirrors what the previous app should have done

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-foundation*
*Context gathered: 2026-02-13*
