# Task 8 Build Graph Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align SwiftPM tests with product modules, preserve correct Xcode test hosts, and safely reduce oversized compilation units and confirmed dead code.

**Architecture:** Partition tests into Core, History, Cloud, iOS, and mac-app targets based on imports, with reusable fixtures kept beside their sole consumers. Preserve the Xcode-hosted mac test bundle and its Developer ID host, because Xcode schemes and SwiftPM solve different test-discovery needs. Split source files only at existing private-view boundaries and make no behavioral changes.

**Tech Stack:** Swift 6.2, SwiftPM, XCTest, SwiftUI, Xcode schemes/project files.

## Global Constraints

- Preserve all existing workspace changes and public behavior.
- Do not introduce `AnyView` or edit `design/`.
- Do not stage, commit, or push.
- Keep App Store scheme target selection unchanged if its existing assertion passes.
- Enable parallel test execution only where tests do not share mutable global/filesystem state.

---

### Task 1: Build-graph assertions

**Files:**
- Modify: `Tests/PingScopeFreshTests/BuildGraphOptimizationTests.swift`

- [ ] Assert the manifest defines module-aligned Core, History, Cloud, iOS, and mac-app test targets with minimal dependencies.
- [ ] Assert mac Xcode tests retain `PingScopeApp` as `TEST_HOST` and distribution/extension schemes select only their intended apps.
- [ ] Run the focused assertion and confirm RED on the monolithic target.

### Task 2: SwiftPM test partition

**Files:**
- Modify: `Package.swift`
- Move: `Tests/PingScopeFreshTests/*.swift` into five module-aligned test directories.

- [ ] Move each test according to its imports, keeping `ManualClock` with iOS tests and `TestDoubles` with Core tests.
- [ ] Replace `PingScopeTests` with five test targets whose dependencies match their imports.
- [ ] Run `swift test list` and focused tests; resolve cross-target fixture/import issues without broadening dependencies unnecessarily.

### Task 3: Safe source splits and dead code

**Files:**
- Modify: `Sources/PingScopeApp/PopoverViews.swift`
- Create: `Sources/PingScopeApp/PopoverSupportViews.swift`
- Modify: `Sources/PingScopeApp/PingScopeApp.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSShell.swift`
- Create: `Sources/PingScopeiOS/PingScopeIOSShellSupportViews.swift`

- [ ] Move standalone private support views into feature-focused files with module-internal visibility.
- [ ] Remove the unreferenced compact diagnosis view after source-usage assertion confirms zero call sites.
- [ ] Remove the redundant deferred detached-window resize; retain the constructor content rect and minimum size.
- [ ] Build after each source split.

### Task 4: Xcode graph and verification

**Files:**
- Modify only project/schemes proven necessary by assertions.
- Replace: `.superpowers/sdd/task-8-report.md`

- [ ] Keep App Store scheme unchanged when its assertion proves target truth.
- [ ] Run full SwiftPM tests and four requested scheme/build checks.
- [ ] Run `git diff --check`, verify no `AnyView`/design/staging changes, and write the report with exact evidence.
