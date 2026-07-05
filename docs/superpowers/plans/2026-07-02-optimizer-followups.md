# Optimizer Followups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the remaining optimizer findings: graph render-data precompute, streaming JSON history export, Xcode signing configuration split, and shared macOS signing helpers.

**Architecture:** Keep behavior stable and move expensive work to existing model/build boundaries. Graph views should consume precomputed render data; file export should stream JSON to the existing temporary file; Xcode/signing changes should make flavor intent explicit without changing app source behavior.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Xcode project build settings, bash signing scripts.

---

### Task 1: Graph Render-Data Precompute

**Files:**
- Modify: `Sources/PingScopeApp/LatencyGraphViews.swift`
- Modify: `Sources/PingScopeApp/PingScopeModel.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSShell.swift`
- Modify: `Sources/PingScopeiOSApp/PingScopeIOSApp.swift`
- Test: `Tests/PingScopeFreshTests/RuntimeBehaviorTests.swift`

- [ ] Add tests that assert graph render data is built from model/presenter inputs and not by the views.
- [ ] Make macOS `LatencyGraphData`, `MultiHostLatencyGraphData`, and their point wrappers internal enough for model properties.
- [ ] Add `primaryGraphData` and `allHostsGraphData` model properties and rebuild them where `visibleSamples` and `allHostGraphSeries` are rebuilt.
- [ ] Change macOS views to accept render data.
- [ ] Add iOS `graphRenderData` alongside `graphSamples` and change `PingScopeIOSLatencyGraph` to render from it.
- [ ] Run focused graph/model tests, then `swift test`.

### Task 2: Streaming JSON History Export

**Files:**
- Modify: `Sources/PingScopeCore/HistoryExport.swift`
- Modify: `Tests/PingScopeFreshTests/HistoryStoreTests.swift`

- [ ] Add/adjust tests so file JSON is validated by decoding from disk, not byte-equality against in-memory JSON.
- [ ] Stream JSON object fields and sample array to `FileHandle` for `.json` file export.
- [ ] Keep `HistoryExporter.data(..., .json)` intact for small/test callers.
- [ ] Run `swift test --filter HistoryStoreTests`.

### Task 3: Xcode Signing Configuration Split

**Files:**
- Modify: `PingScope.xcodeproj/project.pbxproj`
- Modify: `PingScope.xcodeproj/xcshareddata/xcschemes/PingScope-DeveloperID.xcscheme`
- Modify: `PingScope.xcodeproj/xcshareddata/xcschemes/PingScope-AppStore.xcscheme`

- [ ] Add explicit DeveloperID/AppStore build configurations or project settings that make each scheme select the right target/signing/entitlements.
- [ ] Remove production entitlements and non-macOS deployment keys from macOS test targets.
- [ ] Run unsigned Xcode builds for iOS and macOS schemes.

### Task 4: Shared macOS Signing Helpers

**Files:**
- Create: `scripts/lib/codesign-macos.sh`
- Modify: `scripts/build-xcode-app-bundle.sh`
- Modify: `deploy/sign-notarize.sh`

- [ ] Extract `sign_framework_tree`, dylib signing, extension signing, and extension-entitlement selection into the shared helper.
- [ ] Source the helper from both scripts.
- [ ] Verify `scripts/build-xcode-app-bundle.sh debug .build/codesign-check developer-id` and `codesign --verify --deep --strict`.

### Task 5: Final Verification

- [ ] Run `swift test`.
- [ ] Run iOS unsigned Xcode build with `CODE_SIGNING_ALLOWED=NO`.
- [ ] Run Developer ID-style macOS codesign build and strict codesign verification.
- [ ] Run `git diff --check`.
