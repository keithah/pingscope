# Bold Utility Palette and Settings Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace pale iOS host identity colors with the approved Bold Utility palette everywhere and remove the Session status block from Monitor settings.

**Architecture:** Keep `PingScopeIOSHostIdentityPalette` as the single source of identity colors and preserve token order plus stable UUID mapping, changing only exact light/dark RGB values. Remove the settings-only Session SwiftUI section and its now-unused `remainingText` projection without changing session controls or runtime behavior.

**Tech Stack:** Swift 6, SwiftUI, UIKit dynamic colors, XCTest, Swift Package Manager, Xcode.

## Global Constraints

- Preserve all twelve `ColorToken` cases, order, stable UUID hashing, and identity assignments.
- Use the exact light/dark RGB values from `docs/superpowers/specs/2026-07-20-bold-utility-palette-design.md`.
- Apply colors through the existing shared palette to graphs, rings, legends, host dots, mini-graphs, and peer rows.
- Do not change semantic health colors, thresholds, graph math, probing, network behavior, retention, app versions, or build numbers.
- Remove the entire `Section("Session")` settings block and settings-only `remainingText`; preserve Monitor run controls.
- Do not touch `design/`.
- Preserve the existing uncommitted peer-latency work in `PingScopeIOSShell.swift`, `PingScopeIOSApp.swift`, and `BuildGraphOptimizationTests.swift` while staging only task-owned hunks.

---

### Task 1: Replace the shared host identity RGB values

**Files:**
- Modify: `Sources/PingScopeiOS/PingScopeIOSMultiHostPresentation.swift:151-184`
- Test: `Tests/PingScopeFreshTests/iOS/PingScopeIOSMultiHostPresentationTests.swift:324-345`

**Interfaces:**
- Consumes: `PingScopeIOSHostIdentityPalette.ColorToken.lightRGB` and `.darkRGB`.
- Produces: the same token API, case order, `color(at:)`, and `color(for:)` behavior with exact Bold Utility components.

- [ ] **Step 1: Add an exact-value behavioral test**

Add this test, using the existing public RGB type so it compiles against current HEAD and fails on the current pale values:

```swift
func testHostIdentityPaletteUsesExactBoldUtilityComponents() {
    typealias RGB = PingScopeIOSHostIdentityPalette.RGB
    let expected: [(PingScopeIOSHostIdentityPalette.ColorToken, RGB, RGB)] = [
        (.cobalt, RGB(red: 0x00, green: 0x68, blue: 0xD9), RGB(red: 0x27, green: 0x8D, blue: 0xFF)),
        (.magenta, RGB(red: 0xD9, green: 0x1D, blue: 0x5B), RGB(red: 0xFF, green: 0x3D, blue: 0x7F)),
        (.teal, RGB(red: 0x00, green: 0x8C, blue: 0x78), RGB(red: 0x00, green: 0xD1, blue: 0xB2)),
        (.violet, RGB(red: 0x6D, green: 0x28, blue: 0xD9), RGB(red: 0x9B, green: 0x6C, blue: 0xFF)),
        (.gold, RGB(red: 0xB7, green: 0x79, blue: 0x00), RGB(red: 0xFF, green: 0xC4, blue: 0x00)),
        (.orange, RGB(red: 0xD9, green: 0x5F, blue: 0x00), RGB(red: 0xFF, green: 0x8A, blue: 0x00)),
        (.seaGreen, RGB(red: 0x00, green: 0x83, blue: 0x5D), RGB(red: 0x00, green: 0xC8, blue: 0x96)),
        (.purple, RGB(red: 0x8C, green: 0x22, blue: 0xC7), RGB(red: 0xC5, green: 0x4C, blue: 0xFF)),
        (.azure, RGB(red: 0x00, green: 0x77, blue: 0xB6), RGB(red: 0x00, green: 0xB8, blue: 0xF5)),
        (.crimson, RGB(red: 0xC9, green: 0x1E, blue: 0x3A), RGB(red: 0xFF, green: 0x45, blue: 0x60)),
        (.olive, RGB(red: 0x56, green: 0x8A, blue: 0x00), RGB(red: 0x8F, green: 0xD4, blue: 0x00)),
        (.bronze, RGB(red: 0xA8, green: 0x5D, blue: 0x00), RGB(red: 0xEF, green: 0xA3, blue: 0x3A))
    ]

    XCTAssertEqual(PingScopeIOSHostIdentityPalette.ColorToken.allCases, expected.map(\.0))
    XCTAssertEqual(expected.map { $0.0.lightRGB }, expected.map(\.1))
    XCTAssertEqual(expected.map { $0.0.darkRGB }, expected.map(\.2))
}
```

- [ ] **Step 2: Run the test and capture behavioral RED**

Run:

```bash
swift test --filter PingScopeIOSMultiHostPresentationTests/testHostIdentityPaletteUsesExactBoldUtilityComponents
```

Expected: compilation succeeds and `XCTAssertEqual` fails because current RGB arrays contain the old values.

- [ ] **Step 3: Replace only the RGB switch results**

Update all twelve `lightRGB` and `darkRGB` cases to the exact values in Step 1. Do not reorder cases or edit `color(at:)`/`color(for:)`.

- [ ] **Step 4: Run focused GREEN and identity regressions**

Run:

```bash
swift test --filter PingScopeIOSMultiHostPresentationTests/testHostIdentityPaletteUsesExactBoldUtilityComponents
swift test --filter PingScopeIOSMultiHostPresentationTests/testHostIdentityPalette
swift test --filter PingScopeIOSMultiHostPresentationTests/testEveryHostIdentityTokenHasUniqueLightAndDarkComponents
swift test --filter PingScopeIOSMultiHostPresentationTests/testRingIdentityMatchesProductionGraphPreparedSeries
```

Expected: all selected tests pass, preserving uniqueness, normalization, determinism, and graph/ring agreement.

- [ ] **Step 5: Commit Task 1**

Stage only the palette source and its test, then commit:

```bash
git commit -m "Make host identity colors vivid" \
  -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Remove Session status from Monitor settings

**Files:**
- Modify: `Sources/PingScopeiOS/PingScopeIOSShell.swift:1247-1251,1459-1464`
- Test: `Tests/PingScopeFreshTests/BuildGraph/BuildGraphOptimizationTests.swift`

**Interfaces:**
- Consumes: `PingScopeIOSRootView.monitorSettings`.
- Produces: settings without `Section("Session")`, session phase text, or `remainingText`; Monitor run controls remain present.

- [ ] **Step 1: Add a shipping-source behavioral RED test**

Add:

```swift
func testIOSMonitorSettingsOmitsSessionStatusButKeepsRunControl() throws {
    let source = try String(
        contentsOf: try repositoryRoot().appendingPathComponent("Sources/PingScopeiOS/PingScopeIOSShell.swift"),
        encoding: .utf8
    )
    let settingsStart = try XCTUnwrap(source.range(of: "private var monitorSettings: some View"))
    let tabBarStart = try XCTUnwrap(
        source.range(of: "private var floatingTabBar: some View", range: settingsStart.upperBound..<source.endIndex)
    )
    let settings = source[settingsStart.lowerBound..<tabBarStart.lowerBound]

    XCTAssertFalse(settings.contains("Section(\"Session\")"))
    XCTAssertFalse(source.contains("private var remainingText: String"))
    XCTAssertTrue(source.contains("private var runControl: some View"))
    XCTAssertTrue(source.contains("Text(\"Live\").tag(Optional(MonitorSessionDuration.continuous))"))
}
```

- [ ] **Step 2: Run the test and capture behavioral RED**

Run:

```bash
swift test --filter BuildGraphOptimizationTests/testIOSMonitorSettingsOmitsSessionStatusButKeepsRunControl
```

Expected: compilation succeeds; both negative assertions fail against the shipping source because the Session section and `remainingText` still exist.

- [ ] **Step 3: Remove the settings block and unused projection**

Delete exactly:

```swift
Section("Session") {
    Text(session?.phase().rawValue.capitalized ?? "Ready")
    Text(remainingText)
        .font(.system(.body, design: .monospaced))
}
```

Delete the unused `private var remainingText: String` property. Do not change `runControl` or session runtime types.

- [ ] **Step 4: Run focused GREEN**

Run:

```bash
swift test --filter BuildGraphOptimizationTests/testIOSMonitorSettingsOmitsSessionStatusButKeepsRunControl
```

Expected: one test passes.

- [ ] **Step 5: Commit Task 2 without absorbing peer-latency edits**

Stage only the Session-removal hunk from `PingScopeIOSShell.swift` and the new test hunk from `BuildGraphOptimizationTests.swift`; leave peer mini-graph and history-window hunks unstaged. Commit:

```bash
git commit -m "Remove session status from settings" \
  -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Verify behavior and visual quality

**Files:**
- Verify all changed source and test files.
- Do not modify `design/`, version settings, or network behavior.

**Interfaces:**
- Consumes: completed Bold Utility palette and settings cleanup.
- Produces: test/build evidence and light/dark four-host visual evidence.

- [ ] **Step 1: Run affected and complete tests**

Run:

```bash
swift test --filter PingScopeIOSMultiHostPresentationTests
swift test --filter BuildGraphOptimizationTests
swift test
```

Expected: all tests pass with zero failures.

- [ ] **Step 2: Build the iOS simulator app**

Run:

```bash
xcodebuild -scheme PingScope-iOS -destination 'generic/platform=iOS Simulator' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Inspect four-host light and dark presentations**

Use four deterministic hosts and the production `PingScopeIOSAllHostsMonitorPresentation`, graph preparation, ring presentation, and SwiftUI palette bridge to inspect graph lines, rings, legend dots, host dots, and mini-graphs. Capture one light and one dark image. Confirm visually that the first four Bold Utility identities are vivid, mutually distinct, and consistent across every surface.

- [ ] **Step 4: Run final hygiene checks**

Run:

```bash
git diff --check
git status --short -- design
rg -n 'MARKETING_VERSION = 0.5.0|CURRENT_PROJECT_VERSION = 94' PingScope.xcodeproj/project.pbxproj
git status --short
```

Expected: no whitespace errors, no `design/` changes, versions remain 0.5.0/94, and only the intentionally preserved peer-latency edits remain unstaged.

- [ ] **Step 5: Install for device validation only after the user requests it**

Do not upload to TestFlight during this plan. A later TestFlight upload must use a new build number after device validation.
