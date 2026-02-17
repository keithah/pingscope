# Phase 11: Tech Debt Closure - Research

**Researched:** 2026-02-16  
**Domain:** Internal codebase debt closure (network lifecycle wiring, settings UX wiring, planning traceability)  
**Confidence:** HIGH

## Summary

Phase 11 is a debt-closure phase driven by findings in `.planning/v1.0-v1.0-MILESTONE-AUDIT.md`.

No new external APIs or dependencies are required. All work uses existing project patterns:
- actor-managed networking services in `Sources/PingScope/Services`
- SwiftUI settings composition in `Sources/PingScope/Views/Settings`
- UserDefaults-backed notification preference persistence in `NotificationPreferencesStore`

Recommended scope:
1. Wire `ConnectionSweeper` into active TCP/UDP ping lifecycle so orphan cleanup runs in production path.
2. Expose an active settings UI path for `NotificationPreferences.hostOverrides`.
3. Remove unused legacy `HostSettingsView` and normalize summary path conventions (`PingScope` naming).

## Discovery Level

**Level 0 (Skip external discovery)**

Rationale:
- Work follows established repository patterns.
- No new third-party libraries.
- No external service integration.

## Constraints from Existing Decisions

- Keep Swift Concurrency and actor boundaries as-is (`PingService`, `PingScheduler`, `NotificationService`).
- Preserve active settings shell (`PingMonitorSettingsView`) as the single settings entrypoint.
- Do not introduce parallel/disconnected settings implementations.

## Source Artifacts Consulted

- `.planning/v1.0-v1.0-MILESTONE-AUDIT.md`
- `.planning/phases/01-foundation/01-03-SUMMARY.md`
- `.planning/phases/06-notifications-settings/06-01-SUMMARY.md`
- `.planning/phases/06-notifications-settings/06-07-SUMMARY.md`
