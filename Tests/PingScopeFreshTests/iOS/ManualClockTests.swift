import XCTest

final class ManualClockTests: XCTestCase {
    func testDurationUntilNextSleepDeadlineTracksManualTime() async throws {
        let clock = ManualClock()
        let sleeper = Task {
            try await clock.sleep(for: .milliseconds(100))
        }
        try await clock.waitForSleepers(atLeast: 1)

        XCTAssertEqual(clock.durationUntilNextSleepDeadline, .milliseconds(100))
        clock.advance(by: .milliseconds(99))
        XCTAssertEqual(clock.durationUntilNextSleepDeadline, .milliseconds(1))
        clock.advance(by: .milliseconds(1))
        try await sleeper.value
        XCTAssertNil(clock.durationUntilNextSleepDeadline)
    }

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
