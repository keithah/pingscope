# Optimization Followups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all actionable optimizer findings while preserving validation coverage.

**Architecture:** Apply the fixes in small, verified batches: script safety, runtime/process bounds, history/export persistence, UI/cache reductions, and low-risk cleanups. Keep existing public APIs unless a test demonstrates the need for a small extension.

**Tech Stack:** Swift Package, XCTest, Swift concurrency, SQLite C API, SwiftUI/AppKit, bash.

---

### Task 1: Script Safety And Release Robustness

**Files:**
- Modify: `scripts/validate-history-export.sh`
- Modify: `scripts/release-github.sh`
- Modify: `deploy/sign-notarize.sh`

- [ ] Add bash-level checks proving unsafe output directories and traversal appcast paths are rejected.
- [ ] Implement path validation, `mktemp` defaults, cleanup traps, retry helpers, and bounded notarization waits.
- [ ] Verify with `bash -n` and temp-directory dry-run checks that do not call external release services.

### Task 2: Runtime And Process Resource Bounds

**Files:**
- Modify: `Sources/PingScopeCore/Runtime.swift`
- Modify: `Sources/PingScopeCore/AsyncProcess.swift`
- Test: `Tests/PingScopeFreshTests/RuntimeBehaviorTests.swift`
- Test: `Tests/PingScopeFreshTests/AsyncProcessTests.swift`

- [ ] Add failing tests for bounded concurrent probe measurements and output-cap reader behavior.
- [ ] Implement a scheduler concurrency gate and nonblocking timeout termination.
- [ ] Verify with focused runtime and async process tests.

### Task 3: History And Export Memory/Observability

**Files:**
- Modify: `Sources/PingScopeCore/HistoryStore.swift`
- Modify: `Sources/PingScopeCore/HistoryExport.swift`
- Modify: `Sources/PingScopeExportValidate/main.swift`
- Modify: `Sources/PingScopeCore/WidgetSnapshot.swift`
- Modify: `Sources/PingScopeiOSApp/PingScopeIOSApp.swift`
- Test: `Tests/PingScopeFreshTests/HistoryStoreTests.swift`

- [ ] Add failing tests for note-only metadata storage and validator/export behavior where possible.
- [ ] Avoid metadata JSON for note-only samples while preserving decode compatibility.
- [ ] Prefer streaming export validation and add logging/degraded-state hooks for silent failures.
- [ ] Verify history/export tests and the export validation tool build.

### Task 4: UI, Caching, And Presentation

**Files:**
- Modify: `Sources/PingScopeApp/PingScopeDisplayPresentation.swift`
- Modify: `Sources/PingScopeApp/LatencyGraphPresentation.swift`
- Modify: `Sources/PingScopeApp/LatencyGraphViews.swift`
- Modify: `Sources/PingScopeApp/OverlayView.swift`
- Modify: `Sources/PingScopeApp/PopoverViews.swift`
- Modify: `PingScopeWidget/WidgetData.swift`
- Modify: `PingScopeWidget/Views/LargeWidgetView.swift`

- [ ] Add focused tests for presentation cache keys or downsampling invariants.
- [ ] Move repeated allocation/downsampling out of render closures where safely scoped.
- [ ] Reduce small body-time allocations and widget lookup rebuilding.
- [ ] Verify runtime behavior and UI presentation tests.

### Task 5: Low-Risk Algorithmic And Build Cleanups

**Files:**
- Modify: `Sources/PingScopeCore/Domain.swift`
- Modify: `Sources/PingScopeCore/NotificationRules.swift`
- Modify: `Sources/PingScopeCore/Presentation.swift`
- Modify: `Sources/PingScopeCore/StarlinkHTTP2Transport.swift`
- Modify: `Sources/PingScopeApp/PingScopeModel.swift`
- Modify: `Sources/PingScopeApp/DebugLog.swift`
- Modify: `scripts/build-xcode-app-bundle.sh`
- Modify: `scripts/validate-ios-simulator-smoke.sh`
- Test: existing focused suites

- [ ] Replace unnecessary filters/sorts/materializations with single-pass alternatives.
- [ ] Add missing error handling/logging for Starlink send completion and widget/history failures.
- [ ] Debounce overlay frame persistence and reduce fixed sleeps where practical.
- [ ] Run focused tests plus `swift test` if the change set remains tractable.
