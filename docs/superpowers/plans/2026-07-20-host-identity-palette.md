# Host Identity Palette Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the six-color iOS host-identity palette with the approved twelve-color adaptive palette shared by concentric rings and multi-host graph series.

**Architecture:** Keep deterministic UUID-to-token assignment in `PingScopeIOSHostIdentityPalette`, expand the platform-neutral token set to twelve cases, and attach explicit light/dark RGB components to every token. Keep the single SwiftUI adapter consumed by both ring and graph views so no presentation surface can choose a different host color.

**Tech Stack:** Swift 6, SwiftUI, UIKit dynamic colors, XCTest, Swift Package Manager, Xcode 26.

## Global Constraints

- Apply the palette everywhere `PingScopeIOSHostIdentityPalette` supplies host identity: concentric rings, their legend, and multi-host graph series.
- Keep UUID hashing as the only assignment mechanism; do not persist color assignments.
- Accept the approved one-time remap from six to twelve buckets.
- Do not change health or diagnosis colors, focused-host health rings, host ordering, ring progress, probe/network protocols, retention, graph-downsampling math, or cache-key fingerprints.
- Keep `MARKETING_VERSION = 0.5.0` and `CURRENT_PROJECT_VERSION = 91` unchanged unless the user separately authorizes build 92 release work.
- Do not upload, archive, tag, notarize, push, create a GitHub release, or publish documentation/product-page changes.

---

### Task 1: Expand the shared adaptive identity palette

**Files:**
- Modify: `Tests/PingScopeFreshTests/iOS/PingScopeIOSMultiHostPresentationTests.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSMultiHostPresentation.swift`
- Modify: `Sources/PingScopeiOS/PingScopeIOSRingViews.swift`

**Interfaces:**
- Consumes: `PingScopeIOSAllHostsMonitorPresentation.stableColorIndex(for:paletteCount:) -> Int`
- Produces: `PingScopeIOSHostIdentityPalette.ColorToken`, `ColorToken.lightRGB`, `ColorToken.darkRGB`, and the existing `ColorToken.swiftUIColor`
- Preserves: `PingScopeIOSHostIdentityPalette.color(at:)`, `color(for:)`, and `count`

- [ ] **Step 1: Add a behavioral RED for the shipping shared palette**

Add this test beside `testRingAndGraphDeriveHostIdentityFromOneSharedPalette`:

```swift
func testSharedHostIdentityPaletteUsesTwelveDeterministicBuckets() {
    let hostIDs = (1...256).compactMap { value in
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", value))
    }

    let firstPass = hostIDs.map(PingScopeIOSHostIdentityPalette.color(for:))
    let secondPass = hostIDs.map(PingScopeIOSHostIdentityPalette.color(for:))

    XCTAssertEqual(PingScopeIOSHostIdentityPalette.count, 12)
    XCTAssertEqual(firstPass, secondPass)
    XCTAssertTrue(firstPass.contains { $0.rawValue >= 6 })
}
```

This compiles against the current shipping API and fails because `count` is `6` and no mapped token has a raw value above `5`.

- [ ] **Step 2: Run the focused test and capture behavioral RED**

Run:

```bash
swift test --filter PingScopeIOSMultiHostPresentationTests/testSharedHostIdentityPaletteUsesTwelveDeterministicBuckets
```

Expected: FAIL at `XCTAssertEqual(...count, 12)` with actual value `6`, and FAIL at the `rawValue >= 6` assertion. The failure must not be a missing-symbol or compile failure.

- [ ] **Step 3: Expand the token model and add explicit adaptive RGB data**

In `PingScopeIOSMultiHostPresentation.swift`, replace the six cases and add an exact byte-based RGB value type:

```swift
public enum PingScopeIOSHostIdentityPalette {
    public struct RGB: Equatable, Hashable, Sendable {
        public let red: UInt8
        public let green: UInt8
        public let blue: UInt8

        public init(red: UInt8, green: UInt8, blue: UInt8) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    public enum ColorToken: Int, CaseIterable, Equatable, Sendable {
        case cobalt
        case magenta
        case teal
        case violet
        case gold
        case orange
        case seaGreen
        case purple
        case azure
        case crimson
        case olive
        case bronze

        public var lightRGB: RGB {
            switch self {
            case .cobalt: RGB(red: 0x25, green: 0x63, blue: 0xEB)
            case .magenta: RGB(red: 0xDB, green: 0x27, blue: 0x77)
            case .teal: RGB(red: 0x08, green: 0x91, blue: 0xB2)
            case .violet: RGB(red: 0x7C, green: 0x3A, blue: 0xED)
            case .gold: RGB(red: 0xCA, green: 0x8A, blue: 0x04)
            case .orange: RGB(red: 0xEA, green: 0x58, blue: 0x0C)
            case .seaGreen: RGB(red: 0x0F, green: 0x76, blue: 0x6E)
            case .purple: RGB(red: 0x93, green: 0x33, blue: 0xEA)
            case .azure: RGB(red: 0x03, green: 0x69, blue: 0xA1)
            case .crimson: RGB(red: 0xBE, green: 0x12, blue: 0x3C)
            case .olive: RGB(red: 0x4D, green: 0x7C, blue: 0x0F)
            case .bronze: RGB(red: 0xA1, green: 0x62, blue: 0x07)
            }
        }

        public var darkRGB: RGB {
            switch self {
            case .cobalt: RGB(red: 0x60, green: 0xA5, blue: 0xFA)
            case .magenta: RGB(red: 0xF4, green: 0x72, blue: 0xB6)
            case .teal: RGB(red: 0x22, green: 0xD3, blue: 0xEE)
            case .violet: RGB(red: 0xA7, green: 0x8B, blue: 0xFA)
            case .gold: RGB(red: 0xFA, green: 0xCC, blue: 0x15)
            case .orange: RGB(red: 0xFB, green: 0x92, blue: 0x3C)
            case .seaGreen: RGB(red: 0x2D, green: 0xD4, blue: 0xBF)
            case .purple: RGB(red: 0xC0, green: 0x84, blue: 0xFC)
            case .azure: RGB(red: 0x38, green: 0xBD, blue: 0xF8)
            case .crimson: RGB(red: 0xFB, green: 0x71, blue: 0x85)
            case .olive: RGB(red: 0xA3, green: 0xE6, blue: 0x35)
            case .bronze: RGB(red: 0xFB, green: 0xBF, blue: 0x24)
            }
        }
    }

    // Keep count, color(at:), and color(for:) unchanged.
}
```

In `PingScopeIOSRingViews.swift`, add `import UIKit` next to the existing imports and replace the system-color switch with one adaptive conversion used by both ring and graph files:

```swift
extension PingScopeIOSHostIdentityPalette.ColorToken {
    var swiftUIColor: Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? darkRGB : lightRGB
            return UIColor(
                red: CGFloat(rgb.red) / 255,
                green: CGFloat(rgb.green) / 255,
                blue: CGFloat(rgb.blue) / 255,
                alpha: 1
            )
        })
    }
}
```

Keep the adapter inside the existing `#if os(iOS)` compilation boundary.

- [ ] **Step 4: Add exact adaptive-component and shared-surface coverage**

Add these tests after the behavioral test:

```swift
func testEveryHostIdentityTokenHasUniqueLightAndDarkComponents() {
    let tokens = PingScopeIOSHostIdentityPalette.ColorToken.allCases

    XCTAssertEqual(Set(tokens.map(\.lightRGB)).count, 12)
    XCTAssertEqual(Set(tokens.map(\.darkRGB)).count, 12)
    XCTAssertTrue(tokens.allSatisfy { $0.lightRGB != $0.darkRGB })
}

func testExpandedRingCellsStillMatchSharedGraphIdentityTokens() {
    let hosts = (1...12).compactMap { value -> HostConfig? in
        guard let id = UUID(
            uuidString: String(format: "10000000-0000-0000-0000-%012X", value)
        ) else { return nil }
        return HostConfig(id: id, displayName: "Host \(value)", address: "192.0.2.\(value)")
    }
    let rows = hosts.map { PingScopeIOSHostRowSnapshot(host: $0, health: nil) }
    let cells = PingScopeIOSAllHostsRingGridPresentation.cells(from: rows)

    XCTAssertEqual(
        cells.map(\.identityColor),
        hosts.map { PingScopeIOSHostIdentityPalette.color(for: $0.id) }
    )
}
```

- [ ] **Step 5: Run focused tests and confirm GREEN**

Run:

```bash
swift test --filter PingScopeIOSMultiHostPresentationTests
```

Expected: all `PingScopeIOSMultiHostPresentationTests` pass, including the new twelve-bucket, adaptive-component, and ring/graph identity tests.

- [ ] **Step 6: Review the production diff for prohibited changes**

Run:

```bash
git diff -- Sources/PingScopeiOS/PingScopeIOSMultiHostPresentation.swift Sources/PingScopeiOS/PingScopeIOSRingViews.swift Tests/PingScopeFreshTests/iOS/PingScopeIOSMultiHostPresentationTests.swift
```

Expected: changes are limited to palette tokens, adaptive RGB conversion, and tests. There are no changes to ring progress, graph sampling, cache fingerprints, host order, health colors, or focused-host rings.

- [ ] **Step 7: Commit the implementation**

```bash
git add Sources/PingScopeiOS/PingScopeIOSMultiHostPresentation.swift Sources/PingScopeiOS/PingScopeIOSRingViews.swift Tests/PingScopeFreshTests/iOS/PingScopeIOSMultiHostPresentationTests.swift
git commit -m "Improve host identity color palette"
```

---

### Task 2: Verify appearance and the final tree

**Files:**
- Verify: `Sources/PingScopeiOS/PingScopeIOSRingViews.swift`
- Verify: `Sources/PingScopeiOS/PingScopeIOSGraphViews.swift`
- Verify: `PingScope.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `PingScopeIOSHostIdentityPalette.ColorToken.swiftUIColor`
- Produces: no new interface; this task supplies release evidence only

- [ ] **Step 1: Build and inspect the iOS surfaces in both appearances**

Run the iOS simulator build:

```bash
xcodebuild -scheme PingScope-iOS -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/host-palette-ios build
```

Expected: `** BUILD SUCCEEDED **`.

Boot an available iPhone simulator, install the verified product, and launch it:

```bash
open -a Simulator
xcrun simctl boot 'iPhone 16 Pro' 2>/dev/null || true
xcrun simctl bootstatus booted -b
xcrun simctl install booted .build/host-palette-ios/Build/Products/Debug-iphonesimulator/PingScope.app
xcrun simctl launch booted com.hadm.PingScope
```

Use the app’s Hosts settings to enable at least four hosts, then inspect the All Hosts concentric rings, legend dots, and multi-host graph. Switch appearance with:

```bash
xcrun simctl ui booted appearance light
xcrun simctl ui booted appearance dark
```

Confirm that:

- each displayed host uses the same color in ring, legend, and graph;
- text and ring tracks remain legible;
- the four representative colors are perceptually distinct;
- status text/dashes still use health colors rather than identity colors.

- [ ] **Step 2: Run the complete package suite**

```bash
swift build
swift test
```

Expected: both commands exit `0`; all package tests pass with zero failures.

- [ ] **Step 3: Run platform and smoke gates**

```bash
xcodebuild -scheme PingScope-DeveloperID -destination 'generic/platform=macOS' -jobs 1 build
PATH="$(dirname "$(command -v rg)"):$PATH" scripts/validate-ios.sh
scripts/validate-app-smoke.sh
```

Expected:

- macOS build ends with `** BUILD SUCCEEDED **`;
- iOS validation reports `Observed 2 requested and 2 delivered Live Activity updates without chatty warnings` and passes;
- app smoke validation reports `PASS: PingScope app smoke validation passed`.

- [ ] **Step 4: Confirm versions and repository hygiene**

```bash
rg -n 'MARKETING_VERSION =|CURRENT_PROJECT_VERSION =' PingScope.xcodeproj/project.pbxproj
git diff --check
git status --short -- design
git status --short
```

Expected:

- every marketing version remains `0.5.0`;
- every project build number remains `91`;
- `git diff --check` emits nothing;
- `design/` is untouched;
- only the plan document may remain uncommitted if it was intentionally not included in Task 1’s commit.

- [ ] **Step 5: Report without publishing**

Report the behavioral RED and GREEN output, new test names, palette token count, one-time remap, light/dark visual inspection, full verification totals, and local commit. Explicitly confirm that no build was uploaded or archived and no tag, push, GitHub release, notarization, or publication occurred. State that a future TestFlight build containing these changes must use build 92 or later.
