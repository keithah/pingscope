import XCTest
@testable import PingScope
@testable import PingScopeCore

final class MacPowerActivityMonitorTests: XCTestCase {
    @MainActor
    func testDisplayWakeDoesNotClearAnIndependentScreenLock() {
        var reported: [CadenceInputs] = []
        let monitor = MacPowerActivityMonitor { reported.append($0) }
        monitor.start()

        monitor.screenDidLock()
        monitor.screenDidSleep()
        monitor.screenDidWake()

        XCTAssertEqual(reported.last?.visibility, .background)
    }
}
