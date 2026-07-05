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
        let probe = StarlinkProbe(statusClient: StubStarlinkStatusClient(status: StarlinkStatus(
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
        let probe = StarlinkProbe(statusClient: StubStarlinkStatusClient(status: StarlinkStatus(
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
        let wasCancelled = await slowProbe.waitForCancellation()
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

    func testProcessICMPProbeParsesRoundTripFromPingOutput() {
        let output = """
        PING 1.1.1.1 (1.1.1.1): 56 data bytes
        64 bytes from 1.1.1.1: icmp_seq=0 ttl=57 time=12.345 ms

        --- 1.1.1.1 ping statistics ---
        1 packets transmitted, 1 packets received, 0.0% packet loss
        round-trip min/avg/max/stddev = 12.345/12.345/12.345/0.000 ms
        """
        XCTAssertEqual(ProcessICMPProbe.parseRoundTripMilliseconds(from: output), 12.345)
        XCTAssertEqual(ProcessICMPProbe.parseRoundTripMilliseconds(from: "a time=0.081 ms\nb time=9 ms"), 0.081)
        XCTAssertNil(ProcessICMPProbe.parseRoundTripMilliseconds(from: "no reply here"))
        XCTAssertNil(ProcessICMPProbe.parseRoundTripMilliseconds(from: "x time=abc ms"))
    }

    func testStarlinkProbeRejectsNonFiniteLatency() async {
        // A non-finite Float from the dish passes `>= 0` (infinity) and would
        // trap in Duration.milliseconds; the payload is untrusted input.
        let probe = StarlinkProbe(statusClient: StubStarlinkStatusClient(status: StarlinkStatus(
            popPingLatencyMilliseconds: .infinity,
            telemetry: StarlinkTelemetry(state: "CONNECTED")
        )))

        let result = await probe.measure(.defaultStarlinkDish)

        XCTAssertNil(result.latency)
        XCTAssertEqual(result.failureReason, .networkUnavailable)
    }

    func testNetworkProbeResolvesWhenCancelledBeforeStart() async {
        // Cancellation delivered before connection.start() runs the onCancel
        // handler ahead of the operation body. A never-started NWConnection
        // emits no state update, so without an explicit resolution the
        // continuation leaks and measure() hangs forever (deadlocking stop()).
        let host = HostConfig(
            displayName: "Unroutable", address: "203.0.113.1",
            method: .tcp, port: 65_000, timeout: .seconds(5)
        )
        for _ in 0..<32 {
            let task = Task { await NetworkProbe(parameters: .tcp).measure(host) }
            task.cancel()
            let result = await withTaskGroup(of: PingResult?.self) { group -> PingResult? in
                group.addTask { await task.value }
                group.addTask {
                    try? await Task.sleep(for: .seconds(10))
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            XCTAssertNotNil(result, "cancelled probe never resolved")
            guard result != nil else { return }
        }
    }

    func testTCPConnectionRefusedIsTerminalAndGatewayTierCountsAsReachable() async throws {
        let port = Self.closedLoopbackPort()
        try XCTSkipIf(port == nil, "unable to allocate a loopback port in this environment")
        guard let port else { return }

        // NWConnection parks a refused connection in .waiting; for a one-shot
        // probe that must be terminal and carry the real reason, not .timeout.
        let remote = HostConfig(
            displayName: "Remote", address: "127.0.0.1", tier: .remoteService,
            method: .tcp, port: port, timeout: .seconds(5)
        )
        let remoteResult = await NetworkProbe(parameters: .tcp).measure(remote)
        XCTAssertNil(remoteResult.latency)
        XCTAssertEqual(remoteResult.failureReason, .connectionRefused)

        // A TCP RST proves the host is reachable at L3; gateway-tier hosts are
        // probed for reachability, so a refusal there is a successful round trip.
        let gateway = HostConfig(
            displayName: "Default Gateway", address: "127.0.0.1", tier: .localGateway,
            method: .tcp, port: port, timeout: .seconds(5)
        )
        let gatewayResult = await NetworkProbe(parameters: .tcp).measure(gateway)
        XCTAssertNotNil(gatewayResult.latency, "a refused gateway probe should count as reachable")
        XCTAssertNil(gatewayResult.failureReason)
    }

    /// Binds an ephemeral loopback port and immediately closes it, yielding a
    /// port that reliably refuses connections.
    private static func closedLoopbackPort() -> UInt16? {
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                Darwin.bind(fd, pointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return nil }
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                getsockname(fd, pointer, &length)
            }
        }
        let port = UInt16(bigEndian: address.sin_port)
        return port == 0 ? nil : port
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

    func waitForCancellation() async -> Bool {
        for _ in 0..<20 {
            if wasCancelled {
                return true
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return wasCancelled
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
