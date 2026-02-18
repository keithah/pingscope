# Project Milestones: PingMonitor

## v1.0 MVP (Shipped: 2026-02-17)

**Delivered:** Complete menu bar ping monitor rewrite with stable async architecture, multi-host monitoring, visualization, and true ICMP support

**Phases completed:** 1-12 (50 plans total)

**Key accomplishments:**
- Async-first architecture with Swift Concurrency eliminating race conditions and false timeouts
- Multi-host monitoring with auto-detected gateway, configurable intervals, and per-host thresholds
- Real-time latency graph visualization with 1hr/10m/5m/1m time ranges and history table
- Full/compact display modes with stay-on-top floating window option
- 7 alert types with per-host notification overrides and cooldown behavior
- True ICMP ping support when running outside App Store sandbox
- Comprehensive test coverage with automated regression suite

**Stats:**
- 236 files changed, ~8000 LOC Swift
- 12 phases, 50 plans
- 226 commits over 5 months

**Git range:** `5e0e94c` → `b6c12a1`

**What's next:** Widget extension and data export for v2.0

---

## v1.1 App Store Release (Shipped: 2026-02-18)

**Delivered:** PingScope submitted to Mac App Store with dual-distribution strategy (App Store + Developer ID)

**Phases completed:** 13-16 (13 plans total)

**Key accomplishments:**
- Dual-build Xcode configuration supporting both App Store (sandboxed) and Developer ID (non-sandboxed) distributions
- Complete App Store compliance: privacy manifest, export declarations, age rating, and privacy nutrition label
- Professional App Store listing: optimized metadata, 5 screenshots at 2880x1800, review notes
- First build (v1.0 build 1) uploaded and submitted for App Store Review
- Manual ICNS creation workflow for App Store icon requirements
- Automated validation tooling for pre-submission confidence

**Stats:**
- 4 phases, 13 plans
- Build uploaded: 2.2MB package with complete icon set
- App Store listing created with metadata and screenshots
- In review as of 2026-02-17

**Git range:** `e16880f` → `0efd9cc`

**What's next:** CI/CD automation and v2.0 feature expansion

---

