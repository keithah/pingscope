import XCTest
@testable import PingScopeCore

final class HostTestingTests: XCTestCase {
    func testHostTesterMeasuresDraftWithoutMutatingStore() async {
        let host = HostConfig(displayName: "Example", address: "example.com")
        let store = HostStore(defaultHosts: [.defaultInternet])
        let factory = SingleProbeFactory(result: .success(hostID: host.id, latency: .milliseconds(18)))
        let tester = HostTester(probeFactory: factory)

        let result = await tester.test(host)
        let storedHosts = await store.hosts()

        XCTAssertEqual(result.latency?.milliseconds, 18)
        XCTAssertEqual(result.address, host.address)
        XCTAssertEqual(storedHosts.map(\.displayName), ["Cloudflare DNS"])
    }

    func testGatewayDetectorParsesDefaultGatewayFromRouteOutput() {
        let output = """
           route to: default
        destination: default
               mask: default
            gateway: 192.168.1.1
          interface: en0
        """

        let gateway = DefaultGatewayDetector.parse(routeOutput: output)

        XCTAssertEqual(gateway, "192.168.1.1")
    }

    func testGatewayDetectorBuildsDefaultGatewayHost() {
        let host = DefaultGatewayDetector.gatewayHost(address: "192.168.1.1")

        XCTAssertEqual(host.displayName, "Default Gateway")
        XCTAssertEqual(host.address, "192.168.1.1")
        XCTAssertEqual(host.tier, .localGateway)
        XCTAssertEqual(host.method, .tcp)
        XCTAssertEqual(host.port, 80)
        XCTAssertTrue(host.requiresLocalNetworkPermission)
    }

    func testStarlinkDishDetectorReturnsDefaultDishWhenStatusSucceeds() async {
        let detector = StarlinkDishDetector(statusClient: FakeStarlinkStatusClient(status: StarlinkStatus(
            popPingLatencyMilliseconds: 42,
            telemetry: StarlinkTelemetry(state: "CONNECTED")
        )), hosts: [.defaultStarlinkDish])

        let outcome = await detector.detectionOutcome(timeout: .milliseconds(100))

        XCTAssertEqual(outcome, .detected(.defaultStarlinkDish))
    }

    func testStarlinkDishDetectorReturnsNilWhenStatusFails() async {
        let detector = StarlinkDishDetector(statusClient: FailingStarlinkStatusClient())

        let outcome = await detector.detectionOutcome(timeout: .milliseconds(100))

        XCTAssertEqual(outcome, .notFound)
    }

    func testStarlinkDishDetectorReturnsReachableCandidate() async {
        let defaultHost = HostConfig.defaultStarlinkDish
        let routerHost = HostConfig(
            displayName: "Starlink",
            address: "192.168.1.1",
            tier: .ispEdge,
            method: .starlink,
            port: 9000,
            interval: .seconds(5),
            timeout: .seconds(2),
            thresholds: LatencyThresholds(degradedMilliseconds: 150, downAfterFailures: 3)
        )
        let detector = StarlinkDishDetector(
            statusClient: SelectiveStarlinkStatusClient(address: routerHost.address, port: routerHost.port),
            hosts: [defaultHost, routerHost]
        )

        let outcome = await detector.detectionOutcome(timeout: .milliseconds(100))

        XCTAssertEqual(outcome, .detected(routerHost))
    }

    func testStarlinkDishDetectorTimesOut() async {
        let detector = StarlinkDishDetector(statusClient: SlowStarlinkStatusClient())

        let outcome = await detector.detectionOutcome(timeout: .milliseconds(10))

        XCTAssertEqual(outcome, .notFound)
    }

    func testStarlinkDishDetectorReportsCancellationSeparatelyFromMiss() async {
        let detector = StarlinkDishDetector(statusClient: SlowStarlinkStatusClient())
        let task = Task {
            await detector.detectionOutcome(timeout: .seconds(60))
        }

        task.cancel()
        let outcome = await task.value

        XCTAssertEqual(outcome, .cancelled)
    }
}

private actor SingleProbeFactory: ProbeFactory {
    private let result: PingResult

    init(result: PingResult) {
        self.result = result
    }

    func makeProbe(for method: PingMethod) async -> any PingProbe {
        SingleProbe(result: result)
    }
}

private struct SingleProbe: PingProbe {
    let result: PingResult

    func measure(_ host: HostConfig) async -> PingResult {
        result.withHostMetadata(from: host)
    }
}

private struct FakeStarlinkStatusClient: StarlinkStatusFetching {
    let status: StarlinkStatus

    func fetchStatus(host: HostConfig) async throws -> StarlinkStatus {
        status
    }
}

private struct FailingStarlinkStatusClient: StarlinkStatusFetching {
    func fetchStatus(host: HostConfig) async throws -> StarlinkStatus {
        throw StarlinkStatusFetchError.unavailable
    }
}

private struct SelectiveStarlinkStatusClient: StarlinkStatusFetching {
    let address: String
    let port: UInt16?

    func fetchStatus(host: HostConfig) async throws -> StarlinkStatus {
        guard host.address == address, host.port == port else {
            throw StarlinkStatusFetchError.unavailable
        }
        return StarlinkStatus(popPingLatencyMilliseconds: 42, telemetry: StarlinkTelemetry(state: "CONNECTED"))
    }
}

private struct SlowStarlinkStatusClient: StarlinkStatusFetching {
    func fetchStatus(host: HostConfig) async throws -> StarlinkStatus {
        try await Task.sleep(for: .seconds(60))
        return StarlinkStatus(popPingLatencyMilliseconds: 42, telemetry: StarlinkTelemetry(state: "CONNECTED"))
    }
}
