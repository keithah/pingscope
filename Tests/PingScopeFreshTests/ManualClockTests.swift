import XCTest

final class ManualClockTests: XCTestCase {
    func testWaitForSleepersTimesOutWhenNoSleepRegisters() async {
        let clock = ManualClock()

        do {
            try await clock.waitForSleepers(atLeast: 1, timeout: .milliseconds(1))
            XCTFail("expected waitForSleepers to time out")
        } catch ManualClock.WaitTimeout.timedOut(let count, let observed) {
            XCTAssertEqual(count, 1)
            XCTAssertEqual(observed, 0)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
