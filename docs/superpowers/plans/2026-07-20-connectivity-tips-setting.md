# Connectivity Tips Setting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an iOS Connectivity Tips setting that defaults off and hides only the general network diagnosis card while preserving health state and Starlink telemetry.

**Architecture:** `PingScopeIOSAppModel` owns a persisted Boolean preference and injects it into `PingScopeIOSRootView`. The root view routes `monitorInsights` through a small visibility projection used by the shipping rendering gate; that projection removes the general diagnosis only when tips are disabled and always preserves Starlink telemetry.

**Tech Stack:** Swift 6, SwiftUI, Combine/`ObservableObject`, `UserDefaults`, XCTest, Swift Package Manager, Xcode.

## Global Constraints

- Connectivity Tips defaults to off when no preference has been stored.
- The toggle controls only the general diagnosis/advice card.
- Host health, latency, graph colors, notifications, widgets, Live Activity state, and Starlink telemetry remain unchanged.
- Do not modify `design/`.
- Preserve the existing uncommitted peer-latency changes in `PingScopeIOSShell.swift`, `PingScopeIOSApp.swift`, and `BuildGraphOptimizationTests.swift`.

---

### Task 1: Define and behaviorally test insight visibility

**Files:**
- Modify: `Sources/PingScopeiOS/PingScopeIOSNetworkDiagnosisPresentation.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSShell.swift`
- Test: `Tests/PingScopeFreshTests/iOS/IOSNetworkDiagnosisPresentationTests.swift`

**Interfaces:**
- Consumes: `PingScopeIOSMonitorInsightsPresentation`, `PingScopeIOSDiagnosisPresentation`, and `[PingScopeIOSStarlinkPresentation]`.
- Produces: `PingScopeIOSMonitorInsightsVisibility.init(presentation:connectivityTipsEnabled:)`, with `diagnosis`, `starlink`, and `hasContent` used directly by `PingScopeIOSRootView.monitorInsightsSection`.

- [ ] **Step 1: Write the failing behavioral tests**

Add tests that construct a real `PingScopeIOSMonitorInsightsPresentation` containing both a network diagnosis and Starlink telemetry, then assert the shipping visibility projection hides only the diagnosis by default and restores it when enabled:

```swift
func testMonitorInsightsVisibilityHidesDiagnosisButKeepsStarlinkWhenConnectivityTipsAreOff() {
    let presentation = makeMonitorInsightsWithDiagnosisAndStarlink()

    let visibility = PingScopeIOSMonitorInsightsVisibility(
        presentation: presentation,
        connectivityTipsEnabled: false
    )

    XCTAssertNil(visibility.diagnosis)
    XCTAssertEqual(visibility.starlink, presentation.starlink)
    XCTAssertTrue(visibility.hasContent)
}

func testMonitorInsightsVisibilityShowsDiagnosisWhenConnectivityTipsAreOn() {
    let presentation = makeMonitorInsightsWithDiagnosisAndStarlink()

    let visibility = PingScopeIOSMonitorInsightsVisibility(
        presentation: presentation,
        connectivityTipsEnabled: true
    )

    XCTAssertEqual(visibility.diagnosis, presentation.diagnosis)
    XCTAssertEqual(visibility.starlink, presentation.starlink)
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --filter IOSNetworkDiagnosisPresentationTests/testMonitorInsightsVisibility
```

Expected: compilation succeeds after adding the test fixture against existing public types, then the behavioral assertion fails because the current shipping presentation always exposes its diagnosis. If introducing the projection name would make RED compile-fail-only, first express the expectation against a temporary test-local projection over the current unfiltered presentation, capture the behavioral failure, then replace it with the production projection during GREEN.

- [ ] **Step 3: Implement the minimal visibility projection and consume it in the shipping gate**

Add:

```swift
public struct PingScopeIOSMonitorInsightsVisibility: Equatable, Sendable {
    public let diagnosis: PingScopeIOSDiagnosisPresentation?
    public let starlink: [PingScopeIOSStarlinkPresentation]

    public init(
        presentation: PingScopeIOSMonitorInsightsPresentation,
        connectivityTipsEnabled: Bool
    ) {
        diagnosis = connectivityTipsEnabled ? presentation.diagnosis : nil
        starlink = presentation.starlink
    }

    public var hasContent: Bool {
        diagnosis != nil || !starlink.isEmpty
    }
}
```

In `monitorInsightsSection`, construct this projection from the root view's preference and render only its `diagnosis` and `starlink` values. Do not change diagnosis generation or downstream status data.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run:

```bash
swift test --filter IOSNetworkDiagnosisPresentationTests/testMonitorInsightsVisibility
```

Expected: both tests pass.

---

### Task 2: Persist and wire the Connectivity Tips setting

**Files:**
- Modify: `Sources/PingScopeiOS/PingScopeIOSShell.swift`
- Modify: `Sources/PingScopeiOSApp/PingScopeIOSApp.swift`
- Test: `Tests/PingScopeFreshTests/iOS/LiveMonitorSessionControllerTests.swift`
- Test: `Tests/PingScopeFreshTests/BuildGraph/BuildGraphOptimizationTests.swift`

**Interfaces:**
- Consumes: `UserDefaults.pingScopeIOSConnectivityTipsEnabled` and `PingScopeIOSRootView` initializer injection.
- Produces: `PingScopeIOSAppModel.connectivityTipsEnabled`, `PingScopeIOSRootView.connectivityTipsEnabled`, and `onSetConnectivityTipsEnabled: (Bool) -> Void`.

- [ ] **Step 1: Write behavioral preference RED and shipping-wiring RED**

Add a dedicated-suite preference test:

```swift
func testIOSConnectivityTipsDefaultOffAndPersistExplicitOptIn() {
    let suiteName = "PingScopeIOSConnectivityTipsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    XCTAssertFalse(defaults.pingScopeIOSConnectivityTipsEnabled)
    defaults.pingScopeIOSConnectivityTipsEnabled = true
    XCTAssertTrue(defaults.pingScopeIOSConnectivityTipsEnabled)
}
```

Add source-wiring assertions alongside the existing iOS app build-graph coverage to ensure the shipping model loads, injects, mutates, and persists the setting, and that `monitorInsightsSection` constructs `PingScopeIOSMonitorInsightsVisibility` with the injected value. This complements rather than replaces the behavioral presentation test from Task 1.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
swift test --filter LiveMonitorSessionControllerTests/testIOSConnectivityTipsDefaultOffAndPersistExplicitOptIn
swift test --filter BuildGraphOptimizationTests/testIOSConnectivityTipsShippingWiring
```

Expected: the preference test fails behaviorally because the existing unfiltered shipping state has no opt-out preference; the wiring test fails because the app model and root view do not yet carry that preference.

- [ ] **Step 3: Implement the minimal persisted preference and UI toggle**

Add the preference beside the existing iOS display preference:

```swift
var pingScopeIOSConnectivityTipsEnabled: Bool {
    get { bool(forKey: "pingScopeIOSConnectivityTipsEnabled") }
    set { set(newValue, forKey: "pingScopeIOSConnectivityTipsEnabled") }
}
```

Add this app-model property:

```swift
@Published var connectivityTipsEnabled: Bool {
    didSet {
        UserDefaults.standard.pingScopeIOSConnectivityTipsEnabled = connectivityTipsEnabled
    }
}
```

Initialize it from `UserDefaults.standard`, pass it into `PingScopeIOSRootView`, and set it through `onSetConnectivityTipsEnabled`. Add the settings control under **Display**:

```swift
Toggle("Connectivity Tips", isOn: Binding(
    get: { connectivityTipsEnabled },
    set: { onSetConnectivityTipsEnabled($0) }
))
```

Use the root view's injected value when creating `PingScopeIOSMonitorInsightsVisibility` in the shipping monitor section. Default the root-view initializer parameter to `false` so previews and callers preserve the opt-out default.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
swift test --filter LiveMonitorSessionControllerTests/testIOSConnectivityTipsDefaultOffAndPersistExplicitOptIn
swift test --filter BuildGraphOptimizationTests/testIOSConnectivityTipsShippingWiring
swift test --filter IOSNetworkDiagnosisPresentationTests/testMonitorInsightsVisibility
```

Expected: all focused tests pass.

---

### Task 3: Regression verification and commit

**Files:**
- Verify all modified source and test files.
- Do not stage or alter `design/`.

**Interfaces:**
- Consumes: completed Connectivity Tips preference and rendering gate.
- Produces: a verified local commit without publishing or overwriting the peer-latency work.

- [ ] **Step 1: Run the complete Swift test suite**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 2: Build the iOS simulator target**

Run:

```bash
xcodebuild -scheme PingScope-iOS -destination 'generic/platform=iOS Simulator' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Check formatting, scope, and version invariants**

Run:

```bash
git diff --check
git status --short -- design
rg -n 'MARKETING_VERSION = 0.5.0|CURRENT_PROJECT_VERSION = ' PingScope.xcodeproj/project.pbxproj
```

Expected: no whitespace errors, no `design/` changes, and no unintended version mutation.

- [ ] **Step 4: Commit only the completed source and test changes**

Review the pre-existing peer-latency diff together with this feature. If it is still uncommitted, keep its logical changes intact and report whether it is included in or separated from the Connectivity Tips commit. Commit with:

```bash
git commit -m "Make connectivity tips optional" \
  -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

Do not push, upload, archive, tag, notarize, or publish unless the user separately requests it.
