import XCTest
@testable import PingScope

final class HostHealthTrackerTests: XCTestCase {
    private var tracker: HostHealthTracker!

    override func setUp() async throws {
        tracker = HostHealthTracker(failureThreshold: 3)
    }

    override func tearDown() async throws {
        tracker = nil
    }

    func testSuccessKeepsHostUp() async {
        let isUp = await tracker.record(host: "test", success: true)
        XCTAssertTrue(isUp)
    }

    func testSingleFailureKeepsHostUp() async {
        let isUp = await tracker.record(host: "test", success: false)
        XCTAssertTrue(isUp)
    }

    func testTwoFailuresKeepsHostUp() async {
        _ = await tracker.record(host: "test", success: false)
        let isUp = await tracker.record(host: "test", success: false)
        XCTAssertTrue(isUp)
    }

    func testConsecutiveFailuresMarkHostDownAtThreshold() async {
        _ = await tracker.record(host: "test", success: false)
        _ = await tracker.record(host: "test", success: false)
        let isUp = await tracker.record(host: "test", success: false)

        XCTAssertFalse(isUp)
    }

    func testSuccessResetsFailureCount() async {
        _ = await tracker.record(host: "test", success: false)
        _ = await tracker.record(host: "test", success: false)

        _ = await tracker.record(host: "test", success: true)

        _ = await tracker.record(host: "test", success: false)
        let isUp = await tracker.record(host: "test", success: false)

        XCTAssertTrue(isUp)
    }

    func testIsHostDownAfterThreshold() async {
        _ = await tracker.record(host: "test", success: false)
        _ = await tracker.record(host: "test", success: false)
        _ = await tracker.record(host: "test", success: false)

        let isDown = await tracker.isHostDown("test")
        XCTAssertTrue(isDown)
    }

    func testResetClearsFailures() async {
        _ = await tracker.record(host: "test", success: false)
        _ = await tracker.record(host: "test", success: false)

        await tracker.reset(host: "test")

        let failures = await tracker.failureCount(for: "test")
        XCTAssertEqual(failures, 0)
    }

    func testIndependentHostTracking() async {
        _ = await tracker.record(host: "hostA", success: false)
        _ = await tracker.record(host: "hostA", success: false)
        _ = await tracker.record(host: "hostB", success: false)

        let hostAIsUp = await tracker.record(host: "hostA", success: false)
        let hostBIsDown = await tracker.isHostDown("hostB")

        XCTAssertFalse(hostAIsUp)
        XCTAssertFalse(hostBIsDown)
    }
}
