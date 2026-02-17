# Roadmap: PingScope

## Milestones

- ✅ **v1.0 MVP** - Phases 1-12 (shipped 2026-02-17)
- 🚧 **v1.1 App Store Release** - Phases 13-16 (in progress)

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

</details>

### 🚧 v1.1 App Store Release (In Progress)

**Milestone Goal:** Make PingScope available in the Mac App Store while maintaining Developer ID direct downloads.

- [x] **Phase 13: Xcode Infrastructure Setup** - Create dual-build Xcode project with sandbox-aware configurations
- [x] **Phase 14: Privacy and Compliance** - Complete privacy manifest and App Store compliance requirements
- [x] **Phase 15: App Store Metadata and Assets** - Create screenshots, description, and marketing materials (completed 2026-02-17)
- [ ] **Phase 16: Submission and Distribution** - Submit to App Store and establish CI/CD workflows

## Phase Details

### Phase 13: Xcode Infrastructure Setup
**Goal**: Establish dual-build capability for App Store and Developer ID distributions
**Depends on**: Nothing (first phase of v1.1)
**Requirements**: INFRA-01, INFRA-02, INFRA-03, INFRA-04, INFRA-05, INFRA-06, INFRA-07, INFRA-08
**Success Criteria** (what must be TRUE):
  1. Xcode project builds both App Store (sandboxed) and Developer ID (non-sandboxed) variants from single codebase
  2. App Store build correctly hides ICMP option and shows TCP/UDP methods only
  3. Developer ID build shows all three ping methods (ICMP, TCP, UDP) as in v1.0
  4. Both builds produce functionally identical apps except for sandbox-gated features
  5. Asset catalog contains valid 1024x1024 opaque PNG app icon meeting App Store requirements
**Plans**: 4 plans

Plans:
- [x] 13-01-PLAN.md — Prepare asset catalog and configuration directory
- [x] 13-02-PLAN.md — Create dual entitlements and migrate Info.plist
- [x] 13-03-PLAN.md — Create Xcode project with dual build schemes
- [x] 13-04-PLAN.md — Verify dual-build sandbox behavior

**Status**: ✅ COMPLETED (2026-02-16)
- Dual-build capability verified for App Store and Developer ID distributions
- Both variants compile and run successfully
- Deferred: Entitlements differentiation and Escape key UX (post-submission)

### Phase 14: Privacy and Compliance
**Goal**: Complete all App Store compliance requirements including privacy manifest and export declarations
**Depends on**: Phase 13
**Requirements**: PRIV-01, PRIV-02, PRIV-03, PRIV-04, PRIV-05, PRIV-06, PRIV-07, PRIV-08
**Success Criteria** (what must be TRUE):
  1. PrivacyInfo.xcprivacy exists declaring network client access with correct required reason codes
  2. Privacy Nutrition Label questionnaire completed in App Store Connect stating "Data Not Collected"
  3. Age rating questionnaire completed with 4+ rating
  4. Export compliance declaration added to Info.plist (ITSAppUsesNonExemptEncryption = NO)
  5. Archived App Store build tested on clean macOS environment - runs sandboxed, ICMP hidden, TCP/UDP work
**Plans**: 3 plans

Plans:
- [x] 14-01-PLAN.md — Export compliance, privacy manifest verification, and sandbox verification script
- [x] 14-02-PLAN.md — Complete App Store Connect questionnaires (Privacy Nutrition Label and Age Rating)
- [x] 14-03-PLAN.md — Archive and verify sandboxed App Store build

**Status**: ✅ COMPLETED (2026-02-17)
- Privacy manifest verified complete (UserDefaults with CA92.1 reason code)
- Export compliance declared (ITSAppUsesNonExemptEncryption=false)
- Verification tooling created (Scripts/verify-sandbox.sh with 6 automated checks)
- App Store Connect questionnaires completed (Privacy: Data Not Collected, Age Rating: 4+)
- App Store archive created and verified (sandbox enabled, ICMP hidden, TCP/UDP functional)

### Phase 15: App Store Metadata and Assets
**Goal**: Create all required App Store listing content including screenshots and descriptions
**Depends on**: Phase 14
**Requirements**: META-01, META-02, META-03, META-04, META-05, META-06, META-07, META-08, META-09, META-10, META-11, META-12, META-13, META-14
**Success Criteria** (what must be TRUE):
  1. App name, subtitle, and description written highlighting differentiators (multi-host, gateway detection, dual modes)
  2. Keywords optimized within 100-char limit avoiding trademarked terms
  3. Five screenshots at 2880x1800 resolution showing: (1) menu bar + full interface, (2) multi-host tabs + graph, (3) settings, (4) ping history, (5) compact mode
  4. Support URL, copyright notice, and promotional text created
  5. Review notes explain dual sandbox modes and how to test both distributions
**Plans**: 2 plans

Plans:
- [ ] 15-01-PLAN.md — Create metadata text files with validation (app name, subtitle, description, keywords, promotional text, legal notices, review notes)
- [ ] 15-02-PLAN.md — Capture and validate five screenshots at 2880x1800 resolution

### Phase 16: Submission and Distribution
**Goal**: Submit first build to App Store Review and establish automated release workflows
**Depends on**: Phase 15
**Requirements**: SUBM-01, SUBM-02, SUBM-03, SUBM-04, SUBM-05, SUBM-06, SUBM-07, SUBM-08, SUBM-09, SUBM-10
**Success Criteria** (what must be TRUE):
  1. App bundle validated locally with xcrun altool --validate-app (all checks pass)
  2. App uploaded to App Store Connect and available in TestFlight for internal testing
  3. Internal TestFlight testers confirm App Store build works identically to Developer ID build (except ICMP)
  4. First submission to App Review completed with all metadata, screenshots, and review notes
  5. Manual submission workflow documented for reproducibility
**Plans**: TBD

Plans:
- [ ] 16-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 13 → 14 → 15 → 16

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-12. v1.0 MVP | v1.0 | 50/50 | Complete | 2026-02-17 |
| 13. Xcode Infrastructure Setup | v1.1 | 4/4 | Complete | 2026-02-16 |
| 14. Privacy and Compliance | v1.1 | 3/3 | Complete | 2026-02-17 |
| 15. App Store Metadata and Assets | v1.1 | Complete    | 2026-02-17 | - |
| 16. Submission and Distribution | v1.1 | 0/TBD | Not started | - |
