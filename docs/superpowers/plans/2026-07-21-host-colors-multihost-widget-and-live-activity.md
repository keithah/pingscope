# Synced Host Colors, Multi-Host Widget, and Live Activity Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sync arbitrary host colors across Mac and iPhone, use those colors consistently, show up to five host lines in the widget and full telemetry in Switch Host, add truthful Live Activity controls, and ship the link-local gateway correction in the same validated phone build.

**Architecture:** Add an optional presentation-only opaque sRGB value to `HostConfig`, transported by the existing Codable/CloudKit host JSON and ignored by probe identity. Resolve custom-or-Automatic color through shared platform-neutral components, pass the resolved value into widget and Live Activity snapshots, and keep rendering decisions in small presentation units that can be behaviorally tested outside SwiftUI. Existing saved host order remains authoritative and the widget truncates presentation—not monitoring—to five enabled hosts.

**Tech Stack:** Swift 6, SwiftUI, WidgetKit, ActivityKit, CloudKit, Network.framework, XCTest, Swift Package Manager, Xcode.

## Global Constraints

- Behavioral RED must fail for the intended shipping behavior, not only because a new symbol is absent.
- Do not touch `design/`.
- Do not change probe/network wire protocols, retention windows, graph-downsampling math, or probe cache-key fingerprint fields.
- Keep host colors fully opaque sRGB; malformed values fall back to Automatic.
- Keep MARKETING_VERSION and CURRENT_PROJECT_VERSION unchanged during implementation.
- Do not archive, upload, tag, notarize, push, or post to GitHub.
- Local commits must include `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Preserve all existing enabled-host monitoring even when the widget displays only five hosts.
- The signed physical-device build is installed only after all code-review and verification gates pass.

### Behavioral RED protocol

For every task, first identify an existing production entry point that currently produces the wrong observable result. If the production path has no test seam, make a behavior-preserving extraction first and prove the existing suite remains green; then add the behavioral assertion. Never count a missing type/property/compiler error as RED. Capture the failing assertion and confirm it fails at the pre-fix behavior before changing that behavior.

---

## File structure

- Create `Sources/PingScopeCore/HostDisplayColor.swift`: platform-neutral opaque sRGB storage, validation, and deterministic fallback components.
- Modify `Sources/PingScopeCore/Domain.swift`: optional presentation-only `displayColor` on `HostConfig`.
- Modify `Sources/PingScopeCore/WidgetSnapshot.swift`: resolved host color in widget transport, backward-compatible decoding, and five-host selection support.
- Modify `Sources/PingScopeCloudSync/MonitoredHostRecordMapper.swift`: no new record fields; verify existing JSON transport round-trips color.
- Modify `Sources/PingScopeiOS/PingScopeIOSMultiHostPresentation.swift`: shared iOS color resolution and row/series color values.
- Modify `Sources/PingScopeiOS/PingScopeIOSShell.swift`: Switch Host telemetry, resolved colors, and Live Activity settings UI.
- Modify `Sources/PingScopeiOS/PingScopeIOSHostDraft.swift` and `PingScopeIOSHostEditorView.swift`: custom picker and Automatic reset.
- Modify `Sources/PingScopeiOSApp/PingScopeIOSApp.swift`: preference persistence, ActivityKit request/update gating, widget color/sample publishing.
- Modify `Sources/PingScopeApp/PingScopeDisplayPresentation.swift`, `SettingsRootView+Hosts.swift`, and model draft state: macOS color editing and rendering.
- Modify `PingScopeWidget/WidgetData.swift`, `Views/WidgetComponents.swift`, `MediumWidgetView.swift`, and `LargeWidgetView.swift`: decode color, prepare up to five series, draw shared-scale paths and the key.
- Modify `Sources/PingScopeLiveActivitySupport/PingScopeLiveActivity.swift`, `PingScopeLiveActivityPresentation.swift`, and `PingScopeLiveActivity/PingScopeLiveActivityBundle.swift`: identity colors and rich/minimal Island presentation state.
- Modify focused tests under `Tests/PingScopeFreshTests/Core`, `Cloud`, `iOS`, `MacApp`, `ExtensionSupport`, and `BuildGraph`.

---

### Task 1: Backward-compatible synced host color model

**Files:**
- Create: `Sources/PingScopeCore/HostDisplayColor.swift`
- Modify: `Sources/PingScopeCore/Domain.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSMultiHostSessionCoordinator.swift`
- Test: `Tests/PingScopeFreshTests/Core/DomainBehaviorTests.swift`
- Test: `Tests/PingScopeFreshTests/Core/SharedHostStoreTests.swift`
- Test: `Tests/PingScopeFreshTests/Cloud/CloudSyncCoordinatorTests.swift`
- Test: `Tests/PingScopeFreshTests/iOS/LiveMonitorSessionControllerTests.swift`

**Interfaces:**
- Produces: `HostDisplayColor`, `HostConfig.displayColor: HostDisplayColor?`, `HostDisplayColor.validatedComponents: HostDisplayColor?`.
- Guarantees: color-only edits are presentation metadata and `hasSameProbeConfiguration(as:)` remains based only on address, method, port, interval, timeout, and thresholds.

- [ ] **Step 1: Write behavioral RED tests using existing Codable entry points**

Decode a legacy-compatible raw host JSON that includes `displayColor`, re-encode it, and assert the color survives rather than being dropped. Decode legacy JSON without the field and assert the re-encoded object does not invent a custom color. Round-trip the same host through `MonitoredHostRecordMapper.record` / `monitoredHost` and shared host persistence.

```swift
func testHostConfigRoundTripPreservesOptionalDisplayColorAndLegacyDefaultsAutomatic() throws {
    let coloredJSON = Data(#"{"id":"00000000-0000-0000-0000-000000000001","displayName":"DNS","address":"1.1.1.1","method":"tcp","port":443,"interval":2000000000,"timeout":2000000000,"thresholds":{"degradedMilliseconds":100,"downAfterFailures":3},"isEnabled":true,"notifications":"inherit","displayColor":{"red":0.2,"green":0.4,"blue":0.8}}"#.utf8)
    let host = try JSONDecoder().decode(HostConfig.self, from: coloredJSON)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(host)) as? [String: Any])
    XCTAssertNotNil(object["displayColor"])
}
```

- [ ] **Step 2: Run RED and confirm behavior—not compilation—fails**

Run:

```bash
swift test --filter 'DomainBehaviorTests|SharedHostStoreTests|CloudSyncCoordinatorTests'
```

Expected: tests compile and fail because synthesized `HostConfig` currently discards the unknown `displayColor` JSON member.

- [ ] **Step 3: Implement the minimal model**

Create a value type that stores raw decoded components but exposes only validated values:

```swift
public struct HostDisplayColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var validatedComponents: HostDisplayColor? {
        guard red.isFinite, green.isFinite, blue.isFinite,
              (0...1).contains(red), (0...1).contains(green), (0...1).contains(blue) else { return nil }
        return self
    }
}
```

Add `displayColor: HostDisplayColor? = nil` to `HostConfig` and its initializer. In `applyingPresentationMetadata(from:)`, copy `displayColor`; do not add it to `hasSameProbeConfiguration(as:)`.

- [ ] **Step 4: Add invalid-value and color-only coordinator tests**

Assert invalid components decode without losing the host but resolve as invalid. Assert a color-only `reconcile(hosts:)` keeps the same controller identity/session samples while the returned snapshot carries the new presentation metadata.

- [ ] **Step 5: Run GREEN**

```bash
swift test --filter 'DomainBehaviorTests|SharedHostStoreTests|CloudSyncCoordinatorTests|LiveMonitorSessionControllerTests'
```

Expected: all selected tests pass; existing CloudKit schema fields remain unchanged because color travels inside `configJSON`.

- [ ] **Step 6: Commit**

```bash
git add Sources/PingScopeCore/HostDisplayColor.swift Sources/PingScopeCore/Domain.swift Sources/PingScopeiOS/PingScopeIOSMultiHostSessionCoordinator.swift Tests/PingScopeFreshTests/Core Tests/PingScopeFreshTests/Cloud Tests/PingScopeFreshTests/iOS/LiveMonitorSessionControllerTests.swift
git commit -m "Sync optional host display colors" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: One resolved identity color across Mac and iOS

**Files:**
- Modify: `Sources/PingScopeCore/HostDisplayColor.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSMultiHostPresentation.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSShell.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSGraphViews.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSRingViews.swift`
- Modify: `Sources/PingScopeApp/PingScopeDisplayPresentation.swift`
- Modify: `Sources/PingScopeApp/LatencyGraphPresentation.swift`
- Test: `Tests/PingScopeFreshTests/iOS/PingScopeIOSMultiHostPresentationTests.swift`
- Test: `Tests/PingScopeFreshTests/MacApp/LatencyGraphPresentationTests.swift`

**Interfaces:**
- Consumes: `HostConfig.displayColor` and `HostDisplayColor.validatedComponents` from Task 1.
- Produces: a shared resolver result that represents either validated custom RGB or the deterministic Automatic palette slot, plus platform bridges that resolve the current light/dark Bold Utility token; graph/ring/row presentation values carry this shared identity-color result rather than unrelated palette indexes.

- [ ] **Step 1: Write behavioral RED tests against existing production presentations**

Construct hosts by decoding JSON with custom colors, drive iOS `graphPresentation`, ring presentation, row presentation, and macOS `makeAllHostGraphSeries`, and assert each surface returns the custom RGB. Also assert a nil/invalid color returns the exact current Bold Utility fallback for the UUID.

```swift
let custom = HostDisplayColor(red: 0.95, green: 0.2, blue: 0.55)
var host = HostConfig(displayName: "Custom", address: "1.1.1.1")
host.displayColor = custom
let graph = PingScopeIOSAllHostsMonitorPresentation.graphPresentation(/* production inputs */)
XCTAssertEqual(graph.series.first?.resolvedColor, custom)
```

- [ ] **Step 2: Run RED**

```bash
swift test --filter 'PingScopeIOSMultiHostPresentationTests|LatencyGraphPresentationTests'
```

Expected: assertions fail because production surfaces still derive palette colors solely from UUID/index.

- [ ] **Step 3: Implement the shared resolver and thread it through production data**

Keep the twelve Bold Utility RGB pairs as the Automatic fallback. Change prepared series/ring/row values to carry resolved components. Platform bridges convert the shared components to SwiftUI `Color`:

```swift
extension HostDisplayColor {
    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
```

Do not use health status colors for identity lines, dots, legend keys, or latency values.

- [ ] **Step 4: Run GREEN and visual palette regression tests**

```bash
swift test --filter 'PingScopeIOSMultiHostPresentationTests|LatencyGraphPresentationTests'
```

Expected: custom-color agreement passes and every existing exact Bold Utility test remains green.

- [ ] **Step 5: Commit**

```bash
git add Sources/PingScopeCore/HostDisplayColor.swift Sources/PingScopeiOS Sources/PingScopeApp/PingScopeDisplayPresentation.swift Sources/PingScopeApp/LatencyGraphPresentation.swift Tests/PingScopeFreshTests/iOS/PingScopeIOSMultiHostPresentationTests.swift Tests/PingScopeFreshTests/MacApp/LatencyGraphPresentationTests.swift
git commit -m "Resolve host identity colors consistently" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Custom color editing with Automatic reset on iOS and Mac

**Files:**
- Modify: `Sources/PingScopeiOS/PingScopeIOSHostDraft.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSHostEditorView.swift`
- Modify: `Sources/PingScopeApp/PingScopeModel.swift`
- Modify: `Sources/PingScopeApp/SettingsRootView+Hosts.swift`
- Test: `Tests/PingScopeFreshTests/iOS/LiveMonitorSessionControllerTests.swift`
- Test: `Tests/PingScopeFreshTests/MacApp/HostConfigPersistenceTests.swift`
- Test: `Tests/PingScopeFreshTests/BuildGraph/BuildGraphOptimizationTests.swift`

**Interfaces:**
- Consumes: `HostConfig.displayColor` and shared resolver.
- Produces: draft `displayColor`, `usesAutomaticDisplayColor`, opaque sRGB conversion, and editor callbacks that save/clear the field.

- [ ] **Step 1: Write behavioral RED draft round-trip tests**

Drive `PingScopeIOSHostDraft(host:)`, simulate a custom value and Automatic reset, finalize, and assert the host value. Drive the macOS draft/save model through its public editing actions and assert persistence without changing endpoint/probe fields.

- [ ] **Step 2: Run RED**

```bash
swift test --filter 'LiveMonitorSessionControllerTests|HostConfigPersistenceTests|BuildGraphOptimizationTests'
```

Expected: draft behavior assertions fail because editor draft state currently drops appearance.

- [ ] **Step 3: Implement iOS Appearance section**

Add a `ColorPicker("Host Color", selection:)` bound through opaque sRGB conversion and a `Button("Use Automatic Color")` that sets the optional draft color to nil. Show the resolved preview when Automatic is selected.

- [ ] **Step 4: Implement matching macOS editor control**

Add the same custom/Automatic behavior to the existing Edit Host pane. Keep current Hosts selection, primary-host behavior, and ordering controls intact.

- [ ] **Step 5: Add shipping wiring assertions and run GREEN**

```bash
swift test --filter 'LiveMonitorSessionControllerTests|HostConfigPersistenceTests|BuildGraphOptimizationTests'
```

Expected: custom and Automatic saves pass on both platforms; color-only saves do not restart probes.

- [ ] **Step 6: Commit**

```bash
git add Sources/PingScopeiOS/PingScopeIOSHostDraft.swift Sources/PingScopeiOS/PingScopeIOSHostEditorView.swift Sources/PingScopeApp/PingScopeModel.swift Sources/PingScopeApp/SettingsRootView+Hosts.swift Tests/PingScopeFreshTests
git commit -m "Add synced host color controls" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Five-host widget selection and independent graph series

**Files:**
- Modify: `Sources/PingScopeCore/WidgetSnapshot.swift`
- Modify: `Sources/PingScopeiOSApp/PingScopeIOSApp.swift`
- Modify: `Sources/PingScopeApp/PingScopeModel+Widgets.swift`
- Modify: `PingScopeWidget/WidgetData.swift`
- Modify: `PingScopeWidget/Views/WidgetComponents.swift`
- Modify: `PingScopeWidget/Views/MediumWidgetView.swift`
- Modify: `PingScopeWidget/Views/LargeWidgetView.swift`
- Test: `Tests/PingScopeFreshTests/Core/HistoryStoreTests.swift`
- Test: `Tests/PingScopeFreshTests/ExtensionSupport/WidgetTimelineAndFamilyPolicyTests.swift`
- Test: `Tests/PingScopeFreshTests/iOS/IOSResourceEfficiencyTests.swift`
- Test: `Tests/PingScopeFreshTests/BuildGraph/BuildGraphOptimizationTests.swift`

**Interfaces:**
- Consumes: resolved host colors and saved host order.
- Produces: `WidgetHost.displayColor`, `WidgetHostSelection.visibleHosts(maximum: 5)`, `WidgetMultiHostGraphPresentation` with ordered legend entries, per-host samples, one shared time window, and one shared latency scale.

- [ ] **Step 1: Add a behavior-preserving test seam if required**

If the widget target cannot currently expose its graph preparation to XCTest, extract the existing single-series preparation into an internal function without changing its combined-series/blue behavior. Run the existing widget tests and commit or retain this as a green refactor. Do not call an absent `WidgetMultiHostGraphPresentation` type from the RED test.

- [ ] **Step 2: Write behavioral RED against the current widget snapshot and extracted shipping seam**

Build a `RuntimeSnapshot` with six enabled hosts in a known order and interleaved samples. Map it through `WidgetSnapshot.make`, then through widget presentation. Assert exactly the first five hosts remain in order, each sample series contains only its host IDs, and every series carries the matching resolved color.

```swift
XCTAssertEqual(presentation.legend.map(\.hostID), Array(hosts.prefix(5)).map(\.id))
XCTAssertEqual(presentation.series.count, 5)
XCTAssertTrue(presentation.series.allSatisfy { series in
    series.samples.allSatisfy { $0.hostID == series.hostID }
})
```

- [ ] **Step 3: Run RED**

```bash
swift test --filter 'HistoryStoreTests|WidgetTimelineAndFamilyPolicyTests|IOSResourceEfficiencyTests|BuildGraphOptimizationTests'
```

Expected: tests fail because the current widget draws one combined blue path and has no five-host presentation model.

- [ ] **Step 4: Extend widget transport backward-compatibly**

Add optional resolved RGB to `WidgetHost`; update both macOS and iOS publishers. Preserve current stale/publish throttling semantics. Keep `recentSamples` host-tagged and do not change its retention/downsampling limits.

- [ ] **Step 5: Implement presentation-only five-host cap and grouping**

Create a pure presentation type in `PingScopeExtensionSupport` or widget-support code that:

- filters enabled hosts already supplied by the app;
- takes the first five in snapshot order;
- groups samples by `hostID`;
- derives one shared timestamp window and latency maximum; and
- returns no path points for empty/failure-only series.

- [ ] **Step 6: Render the approved existing composition**

Keep the top summaries as a compact key. Use flexible widths, one-line truncation, and minimum scale factor for two through five names. Replace `WidgetLatencySparkline(samples: snapshot.recentSamples, color: .blue)` with a multi-series canvas that draws every ordered series in its resolved color on the shared scale.

- [ ] **Step 7: Run GREEN for two/three/four/five/six-host and stale cases**

```bash
swift test --filter 'HistoryStoreTests|WidgetTimelineAndFamilyPolicyTests|IOSResourceEfficiencyTests|BuildGraphOptimizationTests'
```

Expected: all cases pass; six hosts produce five presentation entries while source monitoring data retains all six.

- [ ] **Step 8: Commit**

```bash
git add Sources/PingScopeCore/WidgetSnapshot.swift Sources/PingScopeiOSApp/PingScopeIOSApp.swift Sources/PingScopeApp/PingScopeModel+Widgets.swift Sources/PingScopeExtensionSupport PingScopeWidget Tests/PingScopeFreshTests
git commit -m "Show five colored host series in widgets" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Switch Host telemetry and saved-order behavior

**Files:**
- Modify: `Sources/PingScopeiOS/PingScopeIOSShell.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSMultiHostPresentation.swift`
- Test: `Tests/PingScopeFreshTests/iOS/PingScopeIOSMultiHostPresentationTests.swift`
- Test: `Tests/PingScopeFreshTests/BuildGraph/BuildGraphOptimizationTests.swift`

**Interfaces:**
- Consumes: standard host rows, cached peer data, resolved colors, `allHostsGraphPresentation`, and saved `hosts` order.
- Produces: Switch Host concrete rows with graph and latency; All Hosts remains first.

- [ ] **Step 1: Write behavioral RED on the existing shipping route**

Change the shipping-wiring expectation from `showsSparkline: false` to the standard reusable graph row. Add a presentation test with three hosts in nonalphabetical saved order, live selected data, cached peer data, and an empty peer. Assert order, color, live/cached/unavailable latency, and graph samples.

- [ ] **Step 2: Run RED**

```bash
swift test --filter 'PingScopeIOSMultiHostPresentationTests|BuildGraphOptimizationTests'
```

Expected: Switch Host test fails because it currently calls `hostRow(... showsSparkline: false)` and emits `--` for nonselected hosts.

- [ ] **Step 3: Reuse the standard row presentation**

Build a `[UUID: PingScopeIOSHostRowSnapshot]` and graph presentation in `hostSwitcher`. Render each concrete host through `allHostsRow` with action `.focus`, selected checkmark overlay, and cached semantics. Do not create a second mini-graph implementation.

- [ ] **Step 4: Run GREEN**

```bash
swift test --filter 'PingScopeIOSMultiHostPresentationTests|BuildGraphOptimizationTests'
```

- [ ] **Step 5: Commit**

```bash
git add Sources/PingScopeiOS/PingScopeIOSShell.swift Sources/PingScopeiOS/PingScopeIOSMultiHostPresentation.swift Tests/PingScopeFreshTests/iOS/PingScopeIOSMultiHostPresentationTests.swift Tests/PingScopeFreshTests/BuildGraph/BuildGraphOptimizationTests.swift
git commit -m "Show telemetry in Switch Host rows" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Live Activity master and Dynamic Island detail preferences

**Files:**
- Modify: `Sources/PingScopeiOS/PingScopeIOSShell.swift`
- Modify: `Sources/PingScopeiOSApp/PingScopeIOSApp.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSLiveActivityContentStateBuilder.swift`
- Modify: `Sources/PingScopeLiveActivitySupport/PingScopeLiveActivity.swift`
- Modify: `Sources/PingScopeLiveActivitySupport/PingScopeLiveActivityPresentation.swift`
- Modify: `PingScopeLiveActivity/PingScopeLiveActivityBundle.swift`
- Test: `Tests/PingScopeFreshTests/iOS/LiveMonitorSessionControllerTests.swift`
- Test: `Tests/PingScopeFreshTests/iOS/PingScopeLiveActivityTests.swift`
- Test: `Tests/PingScopeFreshTests/BuildGraph/BuildGraphOptimizationTests.swift`

**Interfaces:**
- Produces: persisted `PingScope.iOS.lockScreenLiveActivityEnabled` and `PingScope.iOS.dynamicIslandDetailsEnabled`, both defaulting false; `ContentState.showsDynamicIslandDetails`; request/update gates.

- [ ] **Step 1: Make the current always-enabled policy observable without changing it**

If the ActivityKit request/update decision is still embedded in private app-model methods, extract the current system-authorization-only decision behind the existing fake ActivityKit host and keep its behavior always enabled. Run the existing live-activity tests green before adding new preference assertions. This preparatory extraction must not add the requested opt-out behavior.

- [ ] **Step 2: Write behavioral RED using the extracted shipping orchestration seam**

With a dedicated `UserDefaults` suite, assert missing keys default false. Drive live-activity start/update policy with master false and assert no request; toggle false during an active fake activity and assert it ends. Build content states with Island details true/false and assert rich/minimal presentation decisions differ.

- [ ] **Step 3: Run RED**

```bash
swift test --filter 'LiveMonitorSessionControllerTests|PingScopeLiveActivityTests|BuildGraphOptimizationTests'
```

Expected: behavior fails because requests are currently gated only by system authorization and content state has no detail preference.

- [ ] **Step 4: Implement persistent preference policy**

Add a small public policy/state type that owns defaults and dependencies:

```swift
public struct PingScopeIOSLiveActivityPreferences: Equatable, Sendable {
    public var lockScreenEnabled: Bool = false
    public var dynamicIslandDetailsEnabled: Bool = false
}
```

The app model guards `startLiveActivity` and `updateLiveActivity` with the master. Turning the master off ends the owned activity. Re-enabling permits the next active update/start to request again.

- [ ] **Step 5: Add the approved Settings section**

Under `Section("Live Activity")`, add `Lock Screen Live Activity` and `Dynamic Island Details`. Disable the detail toggle when master is off and include concise dependency copy.

- [ ] **Step 6: Thread detail preference through Activity content**

Add `showsDynamicIslandDetails` to content state/builders. In the extension, rich expanded/compact/trailing content is used when true; false uses the smallest honest status-only content ActivityKit permits. The Lock Screen view remains unchanged while master is on.

- [ ] **Step 7: Run GREEN**

```bash
swift test --filter 'LiveMonitorSessionControllerTests|PingScopeLiveActivityTests|BuildGraphOptimizationTests'
```

- [ ] **Step 8: Commit**

```bash
git add Sources/PingScopeiOS Sources/PingScopeiOSApp/PingScopeIOSApp.swift Sources/PingScopeLiveActivitySupport PingScopeLiveActivity Tests/PingScopeFreshTests
git commit -m "Add Live Activity presentation controls" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Gateway preservation, integration review, and physical-device build

**Files:**
- Verify: `Sources/PingScopeiOS/PingScopeIOSGatewayDetector.swift`
- Modify if needed: `Sources/PingScopeiOSApp/PingScopeIOSApp.swift`
- Test: `Tests/PingScopeFreshTests/iOS/LiveMonitorSessionControllerTests.swift`
- Test: `Tests/PingScopeFreshTests/BuildGraph/BuildGraphOptimizationTests.swift`

**Interfaces:**
- Consumes: `HostConfig.displayColor`, saved host order, existing `refreshDefaultGatewayHost`, and `NWPathMonitor` handler.
- Guarantees: `169.254/16` never becomes a gateway and valid changes preserve UUID, custom color, settings, and order.

- [ ] **Step 1: Preserve the already-captured gateway RED→GREEN evidence**

The existing behavioral RED is:

```text
XCTAssertNil failed: "169.254.44.1" - A self-assigned link-local interface is not a router and must never replace the saved default gateway.
```

The committed correction in `5576c0f` rejects link-local inputs. Do not rewrite or broaden it without a new behavioral failure.

- [ ] **Step 2: Add app-level gateway update regression coverage**

Drive an extractable MainActor gateway-update decision with a host list containing a colored Default Gateway in the middle. Apply a new valid address and assert the same UUID, display color, notification policy, enabled state, and index remain. Verify shipping wiring calls this path from every satisfied `pathUpdateHandler` event.

- [ ] **Step 3: Run focused and full verification**

```bash
swift test --filter 'LiveMonitorSessionControllerTests|PingScopeIOSMultiHostPresentationTests|PingScopeLiveActivityTests|WidgetTimelineAndFamilyPolicyTests|BuildGraphOptimizationTests'
swift test
xcodebuild -scheme PingScope-iOS -destination 'generic/platform=iOS Simulator' build
xcodebuild -scheme PingScope-DeveloperID -destination 'generic/platform=macOS' -jobs 1 build
scripts/validate-ios.sh
scripts/validate-app-smoke.sh
git diff --check
git status --short -- design
```

Expected: all commands exit 0; `design/` has no changes; project version settings are unchanged.

- [ ] **Step 4: Conduct a findings-first review**

Review every commit since `8ea227c` for persistence compatibility, CloudKit conflict behavior, probe identity, widget sample grouping, five-host ordering, ActivityKit truthfulness, accessibility, stale/cached semantics, and rendering consistency. Resolve all Critical/Important findings test-first before device installation.

- [ ] **Step 5: Build, sign, install, and launch on the connected iPhone**

```bash
xcodebuild -project PingScope.xcodeproj -scheme PingScope-iOS -configuration Debug \
  -destination 'id=D7CC0DBD-509D-5937-A38E-B9142C6CCA0D' \
  -derivedDataPath .build/device-current build
xcrun devicectl device install app \
  --device D7CC0DBD-509D-5937-A38E-B9142C6CCA0D \
  .build/device-current/Build/Products/Debug-iphoneos/PingScope.app
xcrun devicectl device process launch \
  --device D7CC0DBD-509D-5937-A38E-B9142C6CCA0D \
  --terminate-existing com.hadm.PingScope
```

- [ ] **Step 6: Physical-device acceptance pass**

Verify:

- switching Wi-Fi networks replaces the gateway and never shows `169.254.x.x`;
- custom color survives relaunch, appears on every app surface, and resets to Automatic;
- synced color arrives on the other platform when Sync History is enabled;
- Hosts reorder controls still work and determine Switch Host/widget order;
- the widget shows two, three, four, and five matching lines/key entries and caps six at five;
- Switch Host shows graph and latency for each available host;
- Lock Screen Live Activity master and Dynamic Island Details preferences behave as documented.

- [ ] **Step 7: Stop before publication**

Report device results and request explicit approval before any build-number bump, archive, TestFlight upload, push, tag, release, or website publication.
