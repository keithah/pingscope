import XCTest
import Network
@testable import PingScope

private actor ConnectionLifecycleTrackerSpy: ConnectionLifecycleTracking {
    private var registeredIDs: [UUID] = []
    private var unregisteredIDs: [UUID] = []

    func register(_ connection: NWConnection) async -> UUID {
        let id = UUID()
        registeredIDs.append(id)
        return id
    }

    func unregister(_ id: UUID) async {
        unregisteredIDs.append(id)
    }

    func counts() -> (registered: Int, unregistered: Int) {
        (registeredIDs.count, unregisteredIDs.count)
    }

    func idsMatch() -> Bool {
        Set(registeredIDs) == Set(unregisteredIDs)
    }
}

final class PingServiceTests: XCTestCase {
    private var pingService: PingService!

    override func setUp() async throws {
        pingService = PingService()
    }

    override func tearDown() async throws {
        pingService = nil
    }

    func testSuccessfulPingReturnsLatency() async {
        let result = await pingService.ping(
            address: "8.8.8.8",
            port: 443,
            pingMethod: .tcp,
            timeout: .seconds(5)
        )

        XCTAssertTrue(result.isSuccess)
        XCTAssertNotNil(result.latency)
        XCTAssertNil(result.error)
        guard let latency = result.latency else {
            XCTFail("Expected latency for successful ping")
            return
        }
        XCTAssertGreaterThan(latency, .zero)
    }

    func testUnreachableHostFailsWithinTimeoutBudget() async {
        let timeout: Duration = .milliseconds(500)
        let start = ContinuousClock.now

        let result = await pingService.ping(
            address: "192.0.2.1",
            port: 12345,
            pingMethod: .tcp,
            timeout: timeout
        )

        let elapsed = ContinuousClock.now - start

        if result.isSuccess {
            XCTAssertNotNil(result.latency)
        } else if result.isTimeout {
            XCTAssertGreaterThanOrEqual(elapsed, timeout - .milliseconds(50))
        } else {
            XCTAssertNotNil(result.error)
        }
        XCTAssertLessThanOrEqual(elapsed, timeout + .milliseconds(400))
    }

    func testTimeoutResultRespectsConfiguredDelayWhenReturned() async {
        let timeout: Duration = .milliseconds(300)
        let start = ContinuousClock.now

        let result = await pingService.ping(
            address: "192.0.2.1",
            port: 12345,
            pingMethod: .tcp,
            timeout: timeout
        )

        let elapsed = ContinuousClock.now - start

        if result.isSuccess {
            XCTAssertNotNil(result.latency)
            XCTAssertLessThan(elapsed, timeout + .milliseconds(400))
        } else if result.isTimeout {
            XCTAssertGreaterThanOrEqual(elapsed, timeout - .milliseconds(50))
        } else {
            XCTAssertNotNil(result.error)
            XCTAssertLessThan(elapsed, timeout + .milliseconds(400))
        }
    }

    func testInvalidHostReturnsFailure() async {
        let result = await pingService.ping(
            address: "",
            port: 443,
            pingMethod: .tcp,
            timeout: .seconds(1)
        )

        XCTAssertFalse(result.isSuccess)
        XCTAssertNotNil(result.error)
    }

    func testPingAllReturnsResultPerHost() async {
        let hosts = (0..<15).map { index in
            Host(
                name: "Host \(index)",
                address: "8.8.8.8",
                port: 443,
                pingMethod: .tcp,
                timeout: .seconds(3),
                isDefault: false
            )
        }

        let results = await pingService.pingAll(hosts: hosts, maxConcurrent: 10)

        XCTAssertEqual(results.count, hosts.count)
        XCTAssertTrue(results.allSatisfy { $0.isSuccess })
    }

    func testPingAllReturnsResultsInInputOrder() async {
        let hosts = [
            Host(name: "Google", address: "8.8.8.8", port: 443, pingMethod: .tcp, timeout: .seconds(3), isDefault: true),
            Host(name: "Cloudflare", address: "1.1.1.1", port: 443, pingMethod: .tcp, timeout: .seconds(3), isDefault: true)
        ]

        let results = await pingService.pingAll(hosts: hosts, maxConcurrent: 2)

        XCTAssertEqual(results.count, hosts.count)
        XCTAssertEqual(results[0].host, "8.8.8.8")
        XCTAssertEqual(results[1].host, "1.1.1.1")
    }

    func testUDPPingPathReturnsResult() async {
        let result = await pingService.ping(
            address: "8.8.8.8",
            port: 53,
            pingMethod: .udp,
            timeout: .seconds(3)
        )

        XCTAssertFalse(result.host.isEmpty)
    }

    func testTCPLifecycleTrackerUnregistersAfterSuccessfulPing() async {
        let tracker = ConnectionLifecycleTrackerSpy()
        pingService = PingService(connectionLifecycleTracker: tracker)

        let result = await pingService.ping(
            address: "8.8.8.8",
            port: 443,
            pingMethod: .tcp,
            timeout: .seconds(5)
        )

        XCTAssertTrue(result.isSuccess)
        await waitForLifecycleCleanup(on: tracker, expectedUnregisterCount: 1)

        let counts = await tracker.counts()
        let idsMatch = await tracker.idsMatch()
        XCTAssertEqual(counts.registered, 1)
        XCTAssertEqual(counts.unregistered, 1)
        XCTAssertTrue(idsMatch)
    }

    func testTCPLifecycleTrackerUnregistersAfterCancelledPingTask() async {
        let tracker = ConnectionLifecycleTrackerSpy()
        pingService = PingService(connectionLifecycleTracker: tracker)

        let task = Task {
            await pingService.ping(
                address: "192.0.2.1",
                port: 12345,
                pingMethod: .tcp,
                timeout: .seconds(5)
            )
        }

        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()

        let result = await task.value
        XCTAssertFalse(result.isSuccess)

        await waitForLifecycleCleanup(on: tracker, expectedUnregisterCount: 1)

        let counts = await tracker.counts()
        let idsMatch = await tracker.idsMatch()
        XCTAssertEqual(counts.registered, 1)
        XCTAssertEqual(counts.unregistered, 1)
        XCTAssertTrue(idsMatch)
    }

    private func waitForLifecycleCleanup(
        on tracker: ConnectionLifecycleTrackerSpy,
        expectedUnregisterCount: Int,
        timeout: Duration = .seconds(1)
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while clock.now < deadline {
            let counts = await tracker.counts()
            if counts.unregistered >= expectedUnregisterCount {
                return
            }

            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
