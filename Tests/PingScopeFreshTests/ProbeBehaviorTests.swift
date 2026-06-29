import XCTest
@testable import PingScopeCore

final class ProbeBehaviorTests: XCTestCase {
    func testAppStoreFlavorHidesICMPAndReturnsUnavailableProbe() async {
        XCTAssertEqual(BuildFlavor.appStore.availableMethods, [.https, .tcp, .udp, .starlink])
        XCTAssertEqual(BuildFlavor.developerID.availableMethods, [.https, .tcp, .udp, .icmp, .starlink])

        let host = HostConfig(displayName: "Raw ICMP", address: "1.1.1.1", method: .icmp, port: nil)
        let probe = await DefaultProbeFactory(flavor: .appStore).makeProbe(for: .icmp)
        let result = await probe.measure(host)

        XCTAssertEqual(result.failureReason, .icmpUnavailable)
        XCTAssertEqual(result.method, .icmp)
    }

    func testHTTPSProbeMeasuresUntilFetcherCompletes() async throws {
        let host = HostConfig(displayName: "Cloudflare DNS", address: "1.1.1.1", method: .https, port: 443)
        let fetcher = DelayedHTTPSFetcher(delay: .milliseconds(25))
        let probe = HTTPSRoundTripProbe(fetcher: fetcher)

        let result = await probe.measure(host)

        XCTAssertEqual(result.method, .https)
        XCTAssertEqual(result.port, 443)
        XCTAssertEqual(result.metadata.note, "HTTPS response received")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(result.latency).milliseconds, 20)
        let method = await fetcher.method
        XCTAssertEqual(method, "HEAD")
        let request = await fetcher.request
        XCTAssertEqual(request?.scheme, "https")
        XCTAssertEqual(request?.host, "1.1.1.1")
        XCTAssertEqual(request?.port, 443)
        XCTAssertEqual(request?.query, "pingscope=1")
    }

    func testStarlinkProbeMapsConnectedStatusToLatencyResult() async throws {
        let host = HostConfig.defaultStarlinkDish
        let probe = StarlinkProbe(statusClient: FakeStarlinkStatusClient(status: StarlinkStatus(
            popPingLatencyMilliseconds: 42.5,
            telemetry: StarlinkTelemetry(
                state: "CONNECTED",
                popPingDropRate: 0.1,
                downlinkThroughputBps: 120_000_000,
                uplinkThroughputBps: 18_000_000,
                fractionObstructed: 0.02,
                activeAlerts: ["roaming"]
            )
        )))

        let result = await probe.measure(host)

        XCTAssertEqual(result.method, .starlink)
        XCTAssertEqual(result.port, 9200)
        XCTAssertEqual(try XCTUnwrap(result.latency).milliseconds, 42.5, accuracy: 0.01)
        XCTAssertEqual(result.metadata.starlink?.state, "CONNECTED")
        XCTAssertEqual(result.metadata.starlink?.popPingDropRate, 0.1)
        XCTAssertEqual(result.metadata.note, "state=CONNECTED drop=10% obstructed=2% alerts=roaming")
    }

    func testStarlinkProbeMapsDisconnectedStatusToFailureWithTelemetry() async {
        let host = HostConfig.defaultStarlinkDish
        let probe = StarlinkProbe(statusClient: FakeStarlinkStatusClient(status: StarlinkStatus(
            popPingLatencyMilliseconds: nil,
            telemetry: StarlinkTelemetry(state: "SEARCHING", popPingDropRate: 1)
        )))

        let result = await probe.measure(host)

        XCTAssertEqual(result.failureReason, .networkUnavailable)
        XCTAssertEqual(result.metadata.starlink?.state, "SEARCHING")
        XCTAssertEqual(result.metadata.starlink?.popPingDropRate, 1)
    }

    func testStarlinkGRPCClientUsesDeviceHandlePathAndDecodesResponse() async throws {
        let codec = StarlinkProtobufCodec()
        let transport = RecordingStarlinkTransport(response: codec.makeGRPCFrame(message: makeStarlinkResponse(latency: 38, dropRate: 0.05)))
        let client = StarlinkStatusGRPCClient(transport: transport, codec: codec)

        let status = try await client.fetchStatus(host: .defaultStarlinkDish)

        XCTAssertEqual(status.popPingLatencyMilliseconds ?? 0, 38, accuracy: 0.001)
        XCTAssertEqual(status.telemetry.popPingDropRate ?? 0, 0.05, accuracy: 0.001)
        XCTAssertEqual(status.telemetry.state, "CONNECTED")
        let snapshot = await transport.snapshot()
        XCTAssertEqual(snapshot.path, StarlinkStatusGRPCClient.statusPath)
        XCTAssertEqual(snapshot.hostAddress, "192.168.100.1")
        XCTAssertEqual(snapshot.requestFrame, codec.makeGetStatusGRPCFrame())
    }

    func testTimeoutProbeCancelsLateProbeAndReturnsTimeout() async {
        let host = HostConfig(displayName: "Slow", address: "example.com", timeout: .milliseconds(10))
        let slowProbe = CancellableSlowProbe()
        let probe = TimeoutProbe(wrapping: slowProbe)

        let result = await probe.measure(host)

        XCTAssertEqual(result.failureReason, .timeout)
        let wasCancelled = await slowProbe.wasCancelled
        XCTAssertTrue(wasCancelled)
    }

    func testTimeoutProbeCancellationDoesNotReportTimeout() async {
        let host = HostConfig(displayName: "Slow", address: "example.com", timeout: .seconds(60))
        let probe = TimeoutProbe(wrapping: CancellableSlowProbe())
        let task = Task {
            await probe.measure(host)
        }

        task.cancel()
        let result = await task.value

        XCTAssertEqual(result.failureReason, .cancelled)
    }
}

private actor CancellableSlowProbe: PingProbe {
    private(set) var wasCancelled = false

    func measure(_ host: HostConfig) async -> PingResult {
        do {
            try await Task.sleep(for: .seconds(60))
            return .success(hostID: host.id, latency: .seconds(60)).withHostMetadata(from: host)
        } catch {
            wasCancelled = true
            return .failure(hostID: host.id, reason: .cancelled).withHostMetadata(from: host)
        }
    }
}

private actor DelayedHTTPSFetcher: HTTPSRoundTripFetching {
    private let delay: Duration
    private(set) var request: URLComponents?
    private(set) var method: String?

    init(delay: Duration) {
        self.delay = delay
    }

    func fetch(_ request: URLRequest) async throws {
        self.request = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
        self.method = request.httpMethod
        try await Task.sleep(for: delay)
    }
}

private struct FakeStarlinkStatusClient: StarlinkStatusFetching {
    let status: StarlinkStatus

    func fetchStatus(host: HostConfig) async throws -> StarlinkStatus {
        status
    }
}

private actor RecordingStarlinkTransport: StarlinkGRPCTransport {
    private let response: Data
    private(set) var path: String?
    private(set) var requestFrame: Data?
    private(set) var hostAddress: String?

    init(response: Data) {
        self.response = response
    }

    func unary(path: String, requestFrame: Data, host: HostConfig) async throws -> Data {
        self.path = path
        self.requestFrame = requestFrame
        hostAddress = host.address
        return response
    }

    func snapshot() -> (path: String?, requestFrame: Data?, hostAddress: String?) {
        (path, requestFrame, hostAddress)
    }
}

private func makeStarlinkResponse(latency: Float, dropRate: Float) -> Data {
    var dish = ProtobufWriter()
    dish.writeFixed32(field: 1003, dropRate)
    dish.writeFixed32(field: 1009, latency)

    var response = ProtobufWriter()
    response.writeLengthDelimited(field: 2004, dish.data)
    return response.data
}
