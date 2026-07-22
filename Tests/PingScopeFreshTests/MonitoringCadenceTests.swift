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
