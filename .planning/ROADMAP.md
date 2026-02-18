# Roadmap: PingScope

## Milestones

- ✅ **v1.0 MVP** - Phases 1-12 (shipped 2026-02-17)
- ✅ **v1.1 App Store Release** - Phases 13-16 (shipped 2026-02-18)

## Phases

<details>
<summary>✅ v1.0 MVP (Phases 1-12) - SHIPPED 2026-02-17</summary>

Complete menu bar ping monitor rewrite with stable async architecture, multi-host monitoring, visualization, and true ICMP support.

**Key accomplishments:**
- Async-first architecture with Swift Concurrency eliminating race conditions and false timeouts
- Multi-host monitoring with auto-detected gateway, configurable intervals, and per-host thresholds
- Real-time latency graph visualization with 1hr/10m/5m/1m time ranges and history table
- Full/compact display modes with stay-on-top floating window option
- 7 alert types with per-host notification overrides and cooldown behavior
- True ICMP ping support when running outside App Store sandbox
- Comprehensive test coverage with automated regression suite

**Stats:** 236 files changed, ~8000 LOC Swift, 12 phases, 50 plans, 226 commits over 5 months

See: [.planning/milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md)

</details>

<details>
<summary>✅ v1.1 App Store Release (Phases 13-16) - SHIPPED 2026-02-18</summary>

PingScope submitted to Mac App Store with dual-distribution strategy (App Store + Developer ID).

**Key accomplishments:**
- Dual-build Xcode configuration supporting both App Store (sandboxed) and Developer ID (non-sandboxed) distributions
- Complete App Store compliance: privacy manifest, export declarations, age rating, and privacy nutrition label
- Professional App Store listing: optimized metadata, 5 screenshots at 2880x1800, review notes
- First build (v1.0 build 1) uploaded and submitted for App Store Review

**Stats:** 4 phases, 13 plans, build in review as of 2026-02-17

See: [.planning/milestones/v1.1-ROADMAP.md](milestones/v1.1-ROADMAP.md)

</details>

## Progress

All v1.1 phases complete. Ready to plan next milestone.

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-12. v1.0 MVP | v1.0 | 50/50 | Complete | 2026-02-17 |
| 13. Xcode Infrastructure Setup | v1.1 | 4/4 | Complete | 2026-02-16 |
| 14. Privacy and Compliance | v1.1 | 3/3 | Complete | 2026-02-17 |
| 15. App Store Metadata and Assets | v1.1 | 2/2 | Complete | 2026-02-17 |
| 16. Submission and Distribution | v1.1 | 4/4 | Complete | 2026-02-18 |
