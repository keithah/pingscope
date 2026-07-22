# Battery-aware adaptive monitoring — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make PingScope adapt probe cadence to power/thermal/visibility state, coalesce probe wakeups, and stop the continuous-location battery drain on iOS.

**Architecture:** A pure `CadenceInputs` value in Core maps each host's configured interval to an effective interval via a max-across-axes multiplier. `MeasurementScheduler` gains an injected clock, applies that multiplier each loop iteration, and sleeps with a tolerance so the OS coalesces timer fires. Platform monitors (macOS/iOS) observe OS notifications, reduce them to `CadenceInputs`, and push them into `PingRuntime`.

**Tech Stack:** Swift, Swift Concurrency (actors, `Clock`), XCTest, `ManualClock` test double. AppKit/IOKit (macOS), CoreLocation/UIKit (iOS).

## Global Constraints

- Core (`PingScopeCore`) must stay platform-agnostic: no AppKit/UIKit/CoreLocation/IOKit imports. Platform monitors live in `PingScopeApp` (macOS) and `PingScopeiOSApp` (iOS).
- Adaptive backoff must NEVER probe faster than the host's configured `interval` (floor = base).
- Effective interval ceiling is `.seconds(300)` so outages are always caught within 5 minutes.
- Timeouts are never scaled by cadence.
- Missing/failed platform signals default to the nominal axis value (multiplier contribution 1×) — never faster than today, never a crash.
- `CadenceInputs.default` must yield multiplier exactly `1.0` (today's behavior).
- Follow the existing test-double pattern: `RecordingProbe`, `StaticProbeFactory`, `ManualClock` (`Tests/PingScopeFreshTests/`).

---

## Task 1: Cadence input value + multiplier (Core)

**Files:**
- Create: `Sources/PingScopeCore/MonitoringCadence.swift`
- Test: `Tests/PingScopeFreshTests/MonitoringCadenceTests.swift`

**Interfaces:**
- Produces:
  - `public enum MonitoringVisibility: Sendable, Equatable { case activeUI, idleForeground, background }`
  - `public enum PowerSource: Sendable, Equatable { case ac, battery, unknown }`
  - `public enum ThermalTier: Sendable, Equatable { case nominal, fair, serious, critical }`
  - `public struct CadenceInputs: Sendable, Equatable` with stored `visibility`, `powerSource`, `isLowPowerMode`, `thermalTier`; `static let default`; `var multiplier: Double`; `func effectiveInterval(base:ceiling:) -> Duration`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import PingScopeCore

final class MonitoringCadenceTests: XCTestCase {
    func testDefaultMultiplierIsOne() {
        XCTAssertEqual(CadenceInputs.default.multiplier, 1.0, accuracy: 0.0001)
    }

    func testMultiplierIsMaxAcrossAxes() {
        // battery (2x) + background (4x) -> max = 4x
        let inputs = CadenceInputs(
            visibility: .background,
            powerSource: .battery,
            isLowPowerMode: false,
            thermalTier: .nominal
        )
        XCTAssertEqual(inputs.multiplier, 4.0, accuracy: 0.0001)
    }

    func testLowPowerModeContributesFour() {
        let inputs = CadenceInputs(visibility: .activeUI, powerSource: .ac, isLowPowerMode: true, thermalTier: .nominal)
        XCTAssertEqual(inputs.multiplier, 4.0, accuracy: 0.0001)
    }

    func testThermalCriticalDominates() {
        let inputs = CadenceInputs(visibility: .activeUI, powerSource: .ac, isLowPowerMode: false, thermalTier: .critical)
        XCTAssertEqual(inputs.multiplier, 8.0, accuracy: 0.0001)
    }

    func testEffectiveIntervalNeverBelowBase() {
        // multiplier 1x: stays at base, not below.
        let interval = CadenceInputs.default.effectiveInterval(base: .seconds(5))
        XCTAssertEqual(interval, .seconds(5))
    }

    func testEffectiveIntervalScalesByMultiplier() {
        let inputs = CadenceInputs(visibility: .background, powerSource: .ac, isLowPowerMode: false, thermalTier: .nominal)
        // background = 4x
        XCTAssertEqual(inputs.effectiveInterval(base: .seconds(5)), .seconds(20))
    }

    func testEffectiveIntervalClampsToCeiling() {
        let inputs = CadenceInputs(visibility: .background, powerSource: .battery, isLowPowerMode: true, thermalTier: .critical)
        // 8x * 60s = 480s, clamped to 300s ceiling
        XCTAssertEqual(inputs.effectiveInterval(base: .seconds(60)), .seconds(300))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MonitoringCadenceTests`
Expected: FAIL — `cannot find 'CadenceInputs' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum MonitoringVisibility: Sendable, Equatable {
    case activeUI
    case idleForeground
    case background
}

public enum PowerSource: Sendable, Equatable {
    case ac
    case battery
    case unknown
}

public enum ThermalTier: Sendable, Equatable {
    case nominal
    case fair
    case serious
    case critical
}

/// Environment inputs that scale probe cadence. Reported by platform monitors;
/// consumed by ``MeasurementScheduler``. Core stays platform-agnostic — nothing
/// here imports AppKit/UIKit/IOKit.
public struct CadenceInputs: Sendable, Equatable {
    public var visibility: MonitoringVisibility
    public var powerSource: PowerSource
    public var isLowPowerMode: Bool
    public var thermalTier: ThermalTier

    public init(
        visibility: MonitoringVisibility = .activeUI,
        powerSource: PowerSource = .unknown,
        isLowPowerMode: Bool = false,
        thermalTier: ThermalTier = .nominal
    ) {
        self.visibility = visibility
        self.powerSource = powerSource
        self.isLowPowerMode = isLowPowerMode
        self.thermalTier = thermalTier
    }

    /// All-nominal: multiplier 1.0, i.e. today's fixed cadence.
    public static let `default` = CadenceInputs()

    /// The most-conservative axis wins. Taking the max (rather than the product)
    /// keeps the multiplier bounded and predictable, and is trivial to reason
    /// about in tests. Ceiling clamping in ``effectiveInterval(base:ceiling:)``
    /// still guards the combined worst case.
    public var multiplier: Double {
        let visibilityFactor: Double
        switch visibility {
        case .activeUI: visibilityFactor = 1
        case .idleForeground: visibilityFactor = 2
        case .background: visibilityFactor = 4
        }
        let powerFactor: Double
        switch powerSource {
        case .ac, .unknown: powerFactor = 1
        case .battery: powerFactor = 2
        }
        let lowPowerFactor: Double = isLowPowerMode ? 4 : 1
        let thermalFactor: Double
        switch thermalTier {
        case .nominal, .fair: thermalFactor = 1
        case .serious: thermalFactor = 4
        case .critical: thermalFactor = 8
        }
        return max(visibilityFactor, powerFactor, lowPowerFactor, thermalFactor)
    }

    /// Effective interval for a host whose configured interval is `base`.
    /// Floored at `base` (never faster than the user asked) and capped at
    /// `ceiling` (outages still caught).
    public func effectiveInterval(base: Duration, ceiling: Duration = .seconds(300)) -> Duration {
        let scaled = base.seconds * multiplier
        let clamped = min(max(scaled, base.seconds), ceiling.seconds)
        return .seconds(clamped)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MonitoringCadenceTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/PingScopeCore/MonitoringCadence.swift Tests/PingScopeFreshTests/MonitoringCadenceTests.swift
git commit -m "feat(core): add CadenceInputs cadence-scaling value"
```

---

## Task 2: Scheduler applies cadence + injected clock (Core)

**Files:**
- Modify: `Sources/PingScopeCore/Runtime.swift` (the `MeasurementScheduler` actor — `init`, `start(hosts:allowsLocalNetworkProbes:)`, per-host task creation, `runLoop(for:generation:)`; add `cadenceInputs` state + `setCadenceInputs(_:)`)
- Test: `Tests/PingScopeFreshTests/MonitoringCadenceTests.swift` (append scheduler-timing tests) — or a new `SchedulerCadenceTests.swift`

**Interfaces:**
- Consumes: `CadenceInputs` (Task 1); existing `RecordingProbe`, `StaticProbeFactory`, `ManualClock`.
- Produces:
  - `MeasurementScheduler.init(probeFactory:logger:maxConcurrentProbes:clock:)` — new trailing `clock: any Clock<Duration> = ContinuousClock()`.
  - `public func setCadenceInputs(_ inputs: CadenceInputs) async` on `MeasurementScheduler`.

- [ ] **Step 1: Write the failing test**

Create `Tests/PingScopeFreshTests/SchedulerCadenceTests.swift`:

```swift
import XCTest
@testable import PingScopeCore

final class SchedulerCadenceTests: XCTestCase {
    func testBatteryDoublesInterProbeWait() async throws {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1", interval: .seconds(5), timeout: .seconds(1))
        let probe = RecordingProbe(results: [
            .success(hostID: host.id, latency: .milliseconds(10))
        ])
        let clock = ManualClock()
        let scheduler = MeasurementScheduler(
            probeFactory: StaticProbeFactory(probe: probe),
            clock: clock
        )
        // battery => 2x => 10s between probes for a 5s base.
        await scheduler.setCadenceInputs(CadenceInputs(visibility: .activeUI, powerSource: .battery, isLowPowerMode: false, thermalTier: .nominal))

        let stream = await scheduler.start(hosts: [host])
        var iterator = stream.makeAsyncIterator()

        // First probe fires immediately (no startup stagger).
        let first = await iterator.next()
        XCTAssertNotNil(first)
        try await clock.waitForSleepers(atLeast: 1)

        // Advancing 5s (the raw base) is NOT enough — battery scaled it to 10s.
        clock.advance(by: .seconds(5))
        let measurementsAfter5s = await probe.measurementCount
        XCTAssertEqual(measurementsAfter5s, 1)

        // Advancing the rest (total 10s) releases the second probe.
        clock.advance(by: .seconds(5))
        let second = await iterator.next()
        XCTAssertNotNil(second)

        await scheduler.stop()
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SchedulerCadenceTests`
Expected: FAIL — `extra argument 'clock' in call` / `value of type 'MeasurementScheduler' has no member 'setCadenceInputs'`.

- [ ] **Step 3: Write minimal implementation**

In `Sources/PingScopeCore/Runtime.swift`, update `MeasurementScheduler`:

Add stored properties near the top of the actor:

```swift
    private let clock: any Clock<Duration>
    private var cadenceInputs: CadenceInputs = .default
```

Replace the initializer with:

```swift
    public init(
        probeFactory: any ProbeFactory,
        logger: (@Sendable (String) -> Void)? = nil,
        maxConcurrentProbes: Int = 8,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.probeFactory = probeFactory
        self.logger = logger
        self.probePermits = AsyncPermitPool(permits: max(1, maxConcurrentProbes))
        self.clock = clock
    }
```

Add the setter (place it right after `init`):

```swift
    /// Updates the environment inputs that scale probe cadence. Applied on each
    /// host's next loop iteration; a live scheduler picks it up without restart.
    public func setCadenceInputs(_ inputs: CadenceInputs) {
        cadenceInputs = inputs
    }
```

In `start(hosts:allowsLocalNetworkProbes:)`, replace the per-host task-creation loop (the `for (offset, host) in measurableHosts.enumerated()` block, including the `offset > 0` stagger) with:

```swift
        for host in measurableHosts {
            let task = Task { [weak self] in
                guard !Task.isCancelled else { return }
                await self?.runLoop(for: host, generation: runGeneration)
            }
            tasks.append(task)
        }
```

In `runLoop(for:generation:)`, replace the trailing sleep

```swift
            do {
                try await Task.sleep(for: host.interval)
            } catch {
                break
            }
```

with a cadence-scaled, coalescing sleep:

```swift
            let effectiveInterval = await currentEffectiveInterval(base: host.interval)
            do {
                // Tolerance lets the OS coalesce timer fires across hosts so the
                // CPU/radio can settle between bursts instead of waking per-host.
                let tolerance = Duration.seconds(min(max(effectiveInterval.seconds * 0.25, 1), 30))
                try await clock.sleep(until: clock.now.advanced(by: effectiveInterval), tolerance: tolerance)
            } catch {
                break
            }
```

`runLoop` is `nonisolated`, so it cannot read `cadenceInputs` directly; add an isolated accessor to the actor:

```swift
    private func currentEffectiveInterval(base: Duration) -> Duration {
        cadenceInputs.effectiveInterval(base: base)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SchedulerCadenceTests`
Expected: PASS.
Run: `swift test --filter RuntimeBehaviorTests`
Expected: PASS (no regressions from the stagger removal / clock injection).

- [ ] **Step 5: Commit**

```bash
git add Sources/PingScopeCore/Runtime.swift Tests/PingScopeFreshTests/SchedulerCadenceTests.swift
git commit -m "feat(core): scale + coalesce probe cadence via CadenceInputs"
```

---

## Task 3: Runtime forwards cadence inputs (Core)

**Files:**
- Modify: `Sources/PingScopeCore/Runtime.swift` (the `PingRuntime` actor — add `setCadenceInputs`)
- Test: `Tests/PingScopeFreshTests/RuntimeBehaviorTests.swift` (append)

**Interfaces:**
- Consumes: `MeasurementScheduler.setCadenceInputs` (Task 2).
- Produces: `public func setCadenceInputs(_ inputs: CadenceInputs) async` on `PingRuntime`.

- [ ] **Step 1: Write the failing test**

Append to `RuntimeBehaviorTests`:

```swift
    func testRuntimeForwardsCadenceInputsWithoutCrashing() async {
        let scheduler = MeasurementScheduler(probeFactory: NoopProbeFactory())
        let runtime = PingRuntime(scheduler: scheduler)
        // Smoke test: the call is reachable and does not trap.
        await runtime.setCadenceInputs(CadenceInputs(visibility: .background, powerSource: .battery, isLowPowerMode: true, thermalTier: .serious))
    }
```

(If `NoopProbeFactory` is not already in the test target, reuse the existing no-op factory referenced at `HistoryStoreTests.swift:167`; match that name.)

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter testRuntimeForwardsCadenceInputsWithoutCrashing`
Expected: FAIL — `value of type 'PingRuntime' has no member 'setCadenceInputs'`.

- [ ] **Step 3: Write minimal implementation**

In `PingRuntime`, add (near `setAllowsLocalNetworkProbes`):

```swift
    public func setCadenceInputs(_ inputs: CadenceInputs) async {
        await scheduler.setCadenceInputs(inputs)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter testRuntimeForwardsCadenceInputsWithoutCrashing`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PingScopeCore/Runtime.swift Tests/PingScopeFreshTests/RuntimeBehaviorTests.swift
git commit -m "feat(core): expose PingRuntime.setCadenceInputs"
```

---

## Task 4: Raise the default gateway interval (Core)

**Files:**
- Modify: `Sources/PingScopeCore/Domain.swift:111` (the `interval:` in `defaultGatewayHost(address:)`)
- Test: `Tests/PingScopeFreshTests/DomainBehaviorTests.swift` (append)

**Interfaces:** none new.

- [ ] **Step 1: Write the failing test**

Append to `DomainBehaviorTests`:

```swift
    func testDefaultGatewayIntervalIsFiveSeconds() {
        XCTAssertEqual(HostConfig.defaultGatewayHost(address: "192.168.1.1").interval, .seconds(5))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter testDefaultGatewayIntervalIsFiveSeconds`
Expected: FAIL — `("2 seconds") is not equal to ("5 seconds")`.

- [ ] **Step 3: Write minimal implementation**

In `Sources/PingScopeCore/Domain.swift`, in `defaultGatewayHost(address:)`, change `interval: .seconds(2)` to `interval: .seconds(5)`. Leave `timeout: .seconds(1)` unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter testDefaultGatewayIntervalIsFiveSeconds`
Expected: PASS.
Run: `swift test`
Expected: PASS (fix any other default-gateway-interval assertions that hard-coded 2s; update them to 5s).

- [ ] **Step 5: Commit**

```bash
git add Sources/PingScopeCore/Domain.swift Tests/PingScopeFreshTests/DomainBehaviorTests.swift
git commit -m "feat(core): raise default gateway interval to 5s"
```

---

## Task 5: Platform-agnostic cadence-input reducer (Core)

The macOS and iOS monitors both need to combine raw signals into a single
`CadenceInputs`, and combining is pure logic worth testing once in Core rather
than twice on-device.

**Files:**
- Modify: `Sources/PingScopeCore/MonitoringCadence.swift` (add a builder)
- Test: `Tests/PingScopeFreshTests/MonitoringCadenceTests.swift` (append)

**Interfaces:**
- Produces: `CadenceInputs.combining(screenObscured:uiVisible:appBackgrounded:powerSource:isLowPowerMode:thermalTier:) -> CadenceInputs`.

- [ ] **Step 1: Write the failing test**

Append to `MonitoringCadenceTests`:

```swift
    func testCombiningScreenObscuredForcesBackground() {
        let inputs = CadenceInputs.combining(
            screenObscured: true,     // display asleep or locked
            uiVisible: true,          // popover open, but screen is off
            appBackgrounded: false,
            powerSource: .ac,
            isLowPowerMode: false,
            thermalTier: .nominal
        )
        XCTAssertEqual(inputs.visibility, .background)
    }

    func testCombiningUIVisibleIsActive() {
        let inputs = CadenceInputs.combining(
            screenObscured: false,
            uiVisible: true,
            appBackgrounded: false,
            powerSource: .ac,
            isLowPowerMode: false,
            thermalTier: .nominal
        )
        XCTAssertEqual(inputs.visibility, .activeUI)
    }

    func testCombiningForegroundNoUIIsIdleForeground() {
        let inputs = CadenceInputs.combining(
            screenObscured: false,
            uiVisible: false,
            appBackgrounded: false,
            powerSource: .battery,
            isLowPowerMode: false,
            thermalTier: .nominal
        )
        XCTAssertEqual(inputs.visibility, .idleForeground)
        XCTAssertEqual(inputs.powerSource, .battery)
    }

    func testCombiningBackgroundedIsBackground() {
        let inputs = CadenceInputs.combining(
            screenObscured: false,
            uiVisible: false,
            appBackgrounded: true,
            powerSource: .unknown,
            isLowPowerMode: false,
            thermalTier: .nominal
        )
        XCTAssertEqual(inputs.visibility, .background)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MonitoringCadenceTests`
Expected: FAIL — `type 'CadenceInputs' has no member 'combining'`.

- [ ] **Step 3: Write minimal implementation**

Append to `CadenceInputs` in `MonitoringCadence.swift`:

```swift
    /// Reduces raw platform signals to a single set of inputs. Visibility is the
    /// most-conservative of: an obscured screen (asleep/locked) forces
    /// `.background`; a backgrounded app is `.background`; visible live UI is
    /// `.activeUI`; otherwise `.idleForeground`.
    public static func combining(
        screenObscured: Bool,
        uiVisible: Bool,
        appBackgrounded: Bool,
        powerSource: PowerSource,
        isLowPowerMode: Bool,
        thermalTier: ThermalTier
    ) -> CadenceInputs {
        let visibility: MonitoringVisibility
        if screenObscured || appBackgrounded {
            visibility = .background
        } else if uiVisible {
            visibility = .activeUI
        } else {
            visibility = .idleForeground
        }
        return CadenceInputs(
            visibility: visibility,
            powerSource: powerSource,
            isLowPowerMode: isLowPowerMode,
            thermalTier: thermalTier
        )
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MonitoringCadenceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PingScopeCore/MonitoringCadence.swift Tests/PingScopeFreshTests/MonitoringCadenceTests.swift
git commit -m "feat(core): add CadenceInputs.combining reducer"
```

---

## Task 6: macOS power/activity monitor (App)

**Files:**
- Create: `Sources/PingScopeApp/MacPowerActivityMonitor.swift`
- Modify: `Sources/PingScopeApp/PingScopeApp.swift` (instantiate the monitor, wire visibility + push into the model's runtime)

**Interfaces:**
- Consumes: `CadenceInputs.combining` (Task 5); `PingRuntime.setCadenceInputs` via the model (Task 3).
- Produces: `final class MacPowerActivityMonitor` with `init(onChange: @escaping @Sendable (CadenceInputs) -> Void)`, `func start()`, `func setUIVisible(_:)`.

- [ ] **Step 1: Write the monitor**

Create `Sources/PingScopeApp/MacPowerActivityMonitor.swift`:

```swift
#if os(macOS)
import AppKit
import Foundation
import IOKit.ps
import PingScopeCore

/// Observes macOS power/thermal/screen state and reports a debounced
/// ``CadenceInputs`` whenever any input changes. All state is touched on the
/// main actor; `onChange` is invoked on the main actor.
@MainActor
final class MacPowerActivityMonitor {
    private let onChange: (CadenceInputs) -> Void
    private var screenObscured = false
    private var uiVisible = true
    private var runLoopSource: CFRunLoopSource?
    private var lastReported: CadenceInputs?

    init(onChange: @escaping (CadenceInputs) -> Void) {
        self.onChange = onChange
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(screenAsleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screenAwake), name: NSWorkspace.screensDidWakeNotification, object: nil)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenLocked), name: .init("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenUnlocked), name: .init("com.apple.screenIsUnlocked"), object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(environmentChanged), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(environmentChanged), name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil)

        installPowerSourceObserver()
        report()
    }

    func setUIVisible(_ visible: Bool) {
        guard uiVisible != visible else { return }
        uiVisible = visible
        report()
    }

    @objc private func screenAsleep() { screenObscured = true; report() }
    @objc private func screenAwake() { screenObscured = false; report() }
    @objc private func screenLocked() { screenObscured = true; report() }
    @objc private func screenUnlocked() { screenObscured = false; report() }
    @objc private func environmentChanged() { report() }

    private func installPowerSourceObserver() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<MacPowerActivityMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in monitor.report() }
        }, context)?.takeRetainedValue() else { return }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    private func currentPowerSource() -> PowerSource {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, first)?.takeUnretainedValue() as? [String: Any],
              let state = description[kIOPSPowerSourceStateKey] as? String else {
            return .unknown
        }
        return state == kIOPSACPowerValue ? .ac : .battery
    }

    private func currentThermalTier() -> ThermalTier {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }

    private func report() {
        let inputs = CadenceInputs.combining(
            screenObscured: screenObscured,
            uiVisible: uiVisible,
            appBackgrounded: false, // a menu-bar agent is never "backgrounded" in the iOS sense
            powerSource: currentPowerSource(),
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalTier: currentThermalTier()
        )
        guard inputs != lastReported else { return }
        lastReported = inputs
        onChange(inputs)
    }
}
#endif
```

- [ ] **Step 2: Wire it into the app**

In `Sources/PingScopeApp/PingScopeApp.swift`, hold a `MacPowerActivityMonitor`, start it after the model/runtime exist, forward changes into the runtime, and call `setUIVisible` from the existing popover/overlay visibility transitions (search for `popover?.isShown`, `overlayController?.window?.isVisible`, and the show/close call sites around `PingScopeApp.swift:290` and `:356`):

```swift
    private var powerMonitor: MacPowerActivityMonitor?

    // called once, after `model` is constructed:
    private func startPowerMonitor() {
        let monitor = MacPowerActivityMonitor { [weak self] inputs in
            guard let self else { return }
            Task { await self.model.applyCadenceInputs(inputs) }
        }
        monitor.start()
        powerMonitor = monitor
    }

    // call powerMonitor?.setUIVisible(true) when the popover/overlay is shown,
    // and powerMonitor?.setUIVisible(false) when both are closed.
```

Add to the model (`Sources/PingScopeApp/PingScopeModel.swift` or a suitable extension) a passthrough to the runtime — match the existing `await runtime.<method>()` pattern used by the model:

```swift
    func applyCadenceInputs(_ inputs: CadenceInputs) async {
        await runtime.setCadenceInputs(inputs)
    }
```

- [ ] **Step 3: Build the macOS target**

Run: `swift build` (and the Xcode macOS scheme if the CI uses it).
Expected: builds clean; no Core imports of AppKit leaked (the monitor is `#if os(macOS)` in the App target only).

- [ ] **Step 4: Manual smoke check**

Launch the macOS app; confirm via debug log that cadence inputs update when: unplugging power, enabling Low Power Mode (System Settings › Battery), and locking the screen. (Use the existing `logger` path.)

- [ ] **Step 5: Commit**

```bash
git add Sources/PingScopeApp/MacPowerActivityMonitor.swift Sources/PingScopeApp/PingScopeApp.swift Sources/PingScopeApp/PingScopeModel.swift
git commit -m "feat(macos): drive cadence from power/thermal/screen state"
```

---

## Task 7: iOS power/activity monitor (iOSApp)

**Files:**
- Create: `Sources/PingScopeiOSApp/PowerActivityMonitor.swift`
- Modify: `Sources/PingScopeiOSApp/PingScopeIOSApp.swift` (drive it from `handleScenePhase` and push into the model/runtime)

**Interfaces:**
- Consumes: `CadenceInputs.combining` (Task 5); the model's runtime passthrough (Task 3).
- Produces: `final class PowerActivityMonitor` with `init(onChange:)`, `func start()`, `func setScenePhase(_ backgrounded: Bool)`.

- [ ] **Step 1: Write the monitor**

Create `Sources/PingScopeiOSApp/PowerActivityMonitor.swift`:

```swift
#if os(iOS)
import Foundation
import UIKit
import PingScopeCore

@MainActor
final class PowerActivityMonitor {
    private let onChange: (CadenceInputs) -> Void
    private var appBackgrounded = false
    private var lastReported: CadenceInputs?

    init(onChange: @escaping (CadenceInputs) -> Void) {
        self.onChange = onChange
    }

    func start() {
        NotificationCenter.default.addObserver(self, selector: #selector(environmentChanged), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(environmentChanged), name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil)
        report()
    }

    func setBackgrounded(_ backgrounded: Bool) {
        guard appBackgrounded != backgrounded else { return }
        appBackgrounded = backgrounded
        report()
    }

    @objc private func environmentChanged() { report() }

    private func currentThermalTier() -> ThermalTier {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }

    private func report() {
        let inputs = CadenceInputs.combining(
            screenObscured: false,
            uiVisible: !appBackgrounded,
            appBackgrounded: appBackgrounded,
            powerSource: .unknown, // iOS has no user-facing AC/battery distinction we act on
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalTier: currentThermalTier()
        )
        guard inputs != lastReported else { return }
        lastReported = inputs
        onChange(inputs)
    }
}
#endif
```

- [ ] **Step 2: Wire it into scene phase**

In `Sources/PingScopeiOSApp/PingScopeIOSApp.swift`, construct a `PowerActivityMonitor` in the model, start it, and drive `setBackgrounded` from `handleScenePhase(_:)` (around `PingScopeIOSApp.swift:264`): `.active` → `setBackgrounded(false)`, `.background`/`.inactive` → `setBackgrounded(true)`. Forward `onChange` into the runtime via `await model.<runtime>.setCadenceInputs(inputs)` (mirror the existing model→runtime call sites).

- [ ] **Step 3: Build the iOS target**

Run the iOS build (XcodeBuildMCP `build_sim` on the iOS scheme, or the project's CI build command).
Expected: builds clean.

- [ ] **Step 4: Commit**

```bash
git add Sources/PingScopeiOSApp/PowerActivityMonitor.swift Sources/PingScopeiOSApp/PingScopeIOSApp.swift
git commit -m "feat(ios): drive cadence from scene phase/thermal/low-power"
```

---

## Task 8: iOS significant-location keep-alive (iOSApp)

**Files:**
- Modify: `Sources/PingScopeiOSApp/PingScopeIOSApp.swift` — `BackgroundLocationKeepAliveController` (around `:722`–`:772`)

**Interfaces:** none new (internal behavior change).

- [ ] **Step 1: Replace continuous updates with significant-change**

In `BackgroundLocationKeepAliveController.start()` (the method that currently sets `allowsBackgroundLocationUpdates = true` and calls `manager.startUpdatingLocation()`), replace the continuous-update configuration and start call:

- Remove `manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers`, `manager.distanceFilter = 1_000`, and `manager.pausesLocationUpdatesAutomatically = false` (these only affect continuous updates).
- Keep `manager.allowsBackgroundLocationUpdates = true`.
- Replace `manager.startUpdatingLocation()` with `manager.startMonitoringSignificantLocationChanges()`.

In the stop path (the method that sets `allowsBackgroundLocationUpdates = false`), replace `manager.stopUpdatingLocation()` with `manager.stopMonitoringSignificantLocationChanges()`.

- [ ] **Step 2: Build the iOS target**

Run the iOS build.
Expected: builds clean.

- [ ] **Step 3: Update the design's known-limitation note in code**

Add a comment above the `startMonitoringSignificantLocationChanges()` call:

```swift
        // Significant-location-change keeps us relaunchable on movement without
        // the continuous-location battery drain. A stationary device is NOT woken
        // for background monitoring — restoring that is the deferred BGAppRefreshTask
        // follow-up (see docs/superpowers/specs/2026-07-21-battery-aware-monitoring-design.md).
```

- [ ] **Step 4: Manual smoke check**

Confirm the app still requests/holds location authorization and that enabling the background keep-alive toggle no longer schedules continuous location updates (check Settings › Privacy or Xcode's energy/location gauge).

- [ ] **Step 5: Commit**

```bash
git add Sources/PingScopeiOSApp/PingScopeIOSApp.swift
git commit -m "perf(ios): use significant-location-change for background keep-alive"
```

---

## Task 9: Full test + build sweep

- [ ] **Step 1:** Run `swift test`. Expected: all pass.
- [ ] **Step 2:** Run `swift build`. Expected: clean.
- [ ] **Step 3:** Build the macOS and iOS Xcode schemes the project/CI uses. Expected: clean.
- [ ] **Step 4:** Commit any test fixups made during the sweep.

```bash
git add -A && git commit -m "test: battery-aware monitoring sweep fixups"
```

---

## Self-Review

**Spec coverage:**
- Cadence engine (multiplier, floor/ceiling, `.default`==1×) → Task 1. ✓
- Coalesced deadline-based scheduling, stagger removed → Task 2 (tolerance-based coalescing; simpler and more idiomatic than manual grid alignment, and avoids the type-erased-`Instant` problem with `any Clock`). ✓
- Cadence-change propagation without full restart → Task 2 (`setCadenceInputs`, applied next iteration) + Task 3 (runtime passthrough). ✓
- Raised default (gateway 2s→5s) → Task 4. ✓
- Combining reducer → Task 5. ✓
- macOS monitor (screen sleep/lock, popover visibility, IOPS power, thermal, low-power) → Task 6. ✓
- iOS monitor (scenePhase, thermal, low-power) → Task 7. ✓
- iOS significant-change location rework + documented limitation → Task 8. ✓
- Timeout never scaled → Task 1 (`effectiveInterval` scales interval only). ✓

**Deviation from spec:** the spec described manual "align to a 1s quantum on a shared grid." Implemented instead as native `clock.sleep(until:tolerance:)`, which is the idiomatic coalescing mechanism, testable via the existing `ManualClock`, and sidesteps naming a type-erased `Instant`. Same battery goal, lower risk. Noted here so the reviewer expects it.

**Placeholder scan:** none.

**Type consistency:** `CadenceInputs`, `MonitoringVisibility`, `PowerSource`, `ThermalTier`, `setCadenceInputs`, `combining(...)`, `effectiveInterval(base:ceiling:)` used consistently across Tasks 1–8.
