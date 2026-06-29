import Foundation
@preconcurrency import Network

public enum BuildFlavor: Sendable {
    case appStore
    case developerID

    public static var current: BuildFlavor {
        #if APPSTORE
        .appStore
        #else
        .developerID
        #endif
    }

    public var availableMethods: [PingMethod] {
        switch self {
        case .appStore: PingMethod.appStoreAvailableCases
        case .developerID: PingMethod.allCases
        }
    }

    public func normalizedHost(_ host: HostConfig) -> HostConfig {
        guard !availableMethods.contains(host.method) else { return host }
        var normalized = host
        normalized.apply(method: .tcp)
        return normalized
    }

    public func normalizedHosts(_ hosts: [HostConfig]) -> [HostConfig] {
        hosts.map(normalizedHost)
    }
}

public struct DefaultProbeFactory: ProbeFactory {
    private let flavor: BuildFlavor
    private let starlinkStatusClient: any StarlinkStatusFetching

    public init(
        flavor: BuildFlavor = .current,
        starlinkStatusClient: any StarlinkStatusFetching = StarlinkStatusGRPCClient(transport: StarlinkHTTP2Transport())
    ) {
        self.flavor = flavor
        self.starlinkStatusClient = starlinkStatusClient
    }

    public func makeProbe(for method: PingMethod) async -> any PingProbe {
        if method == .icmp, flavor == .appStore {
            return UnavailableProbe(reason: .icmpUnavailable)
        }
        let probe: any PingProbe
        switch method {
        case .https:
            probe = HTTPSRoundTripProbe()
        case .tcp:
            probe = NetworkProbe(parameters: .tcp)
        case .udp:
            probe = NetworkProbe(parameters: .udp)
        case .icmp:
            probe = ProcessICMPProbe()
        case .starlink:
            probe = StarlinkProbe(statusClient: starlinkStatusClient)
        }
        return TimeoutProbe(wrapping: probe)
    }
}

public struct UnavailableProbe: PingProbe {
    public var reason: FailureReason

    public init(reason: FailureReason) {
        self.reason = reason
    }

    public func measure(_ host: HostConfig) async -> PingResult {
        .failure(hostID: host.id, reason: reason).withHostMetadata(from: host)
    }
}

public struct NetworkProbe: PingProbe {
    public enum Parameters: Sendable {
        case tcp
        case udp
    }

    private let parameters: Parameters

    public init(parameters: Parameters) {
        self.parameters = parameters
    }

    public func measure(_ host: HostConfig) async -> PingResult {
        let start = ContinuousClock.now
        return await measureConnection(host, start: start)
    }

    private func measureConnection(_ host: HostConfig, start: ContinuousClock.Instant) async -> PingResult {
        guard let port = host.port ?? host.method.defaultPort,
              let nwPort = NWEndpoint.Port(rawValue: port) else {
            return .failure(hostID: host.id, reason: .unknown).withHostMetadata(from: host)
        }

        let nwParameters: NWParameters = parameters == .tcp ? .tcp : .udp
        let connection = NWConnection(host: NWEndpoint.Host(host.address), port: nwPort, using: nwParameters)

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let gate = ContinuationGate()

                let finish: @Sendable (PingResult) -> Void = { result in
                    guard gate.claim() else { return }
                    connection.cancel()
                    continuation.resume(returning: result.withHostMetadata(from: host))
                }

                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        switch parameters {
                        case .tcp:
                            let elapsed = start.duration(to: .now)
                            finish(.success(hostID: host.id, latency: elapsed, metadata: ProbeMetadata(note: "fresh TCP connection")))
                        case .udp:
                            connection.send(content: Data([0]), completion: .contentProcessed { error in
                                if let error {
                                    finish(.failure(
                                        hostID: host.id,
                                        reason: error.failureReason,
                                        metadata: ProbeMetadata(note: error.localizedDescription)
                                    ))
                                } else {
                                    let elapsed = start.duration(to: .now)
                                    finish(.success(
                                        hostID: host.id,
                                        latency: elapsed,
                                        metadata: ProbeMetadata(note: "fresh UDP datagram sent; remote response is not guaranteed")
                                    ))
                                }
                            })
                        }
                    case .failed(let error):
                        finish(.failure(hostID: host.id, reason: error.failureReason, metadata: ProbeMetadata(note: error.localizedDescription)))
                    case .cancelled:
                        finish(.failure(hostID: host.id, reason: .cancelled))
                    default:
                        break
                    }
                }

                connection.start(queue: .global(qos: .utility))
            }
        } onCancel: {
            connection.cancel()
        }
    }
}

public protocol HTTPSRoundTripFetching: Sendable {
    func fetch(_ request: URLRequest) async throws
}

public struct URLSessionHTTPSRoundTripFetcher: HTTPSRoundTripFetching {
    public init() {}

    public func fetch(_ request: URLRequest) async throws {
        _ = try await URLSession.shared.data(for: request)
    }
}

public struct HTTPSRoundTripProbe: PingProbe {
    private let fetcher: any HTTPSRoundTripFetching

    public init(fetcher: any HTTPSRoundTripFetching = URLSessionHTTPSRoundTripFetcher()) {
        self.fetcher = fetcher
    }

    public func measure(_ host: HostConfig) async -> PingResult {
        guard let request = makeRequest(for: host) else {
            return .failure(hostID: host.id, reason: .unknown).withHostMetadata(from: host)
        }

        let start = ContinuousClock.now
        do {
            try await fetcher.fetch(request)
            return .success(
                hostID: host.id,
                latency: start.duration(to: .now),
                metadata: ProbeMetadata(note: "HTTPS response received")
            ).withHostMetadata(from: host)
        } catch is CancellationError {
            return .failure(hostID: host.id, reason: .cancelled).withHostMetadata(from: host)
        } catch {
            return .failure(
                hostID: host.id,
                reason: error.failureReason,
                metadata: ProbeMetadata(note: error.localizedDescription)
            ).withHostMetadata(from: host)
        }
    }

    private func makeRequest(for host: HostConfig) -> URLRequest? {
        guard let port = host.port ?? host.method.defaultPort else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host.address
        components.port = Int(port)
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "pingscope", value: "1")]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: host.timeout.seconds)
        request.httpMethod = "HEAD"
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("PingScope", forHTTPHeaderField: "User-Agent")
        return request
    }
}

public struct TimeoutProbe: PingProbe {
    private let wrapped: any PingProbe

    public init(wrapping wrapped: any PingProbe) {
        self.wrapped = wrapped
    }

    public func measure(_ host: HostConfig) async -> PingResult {
        await withTaskGroup(of: PingResult.self, returning: PingResult.self) { group in
            group.addTask {
                await wrapped.measure(host)
            }
            group.addTask {
                try? await Task.sleep(for: host.timeout)
                return .failure(hostID: host.id, reason: .timeout).withHostMetadata(from: host)
            }
            let result = await group.next() ?? .failure(hostID: host.id, reason: .unknown).withHostMetadata(from: host)
            group.cancelAll()
            return result
        }
    }
}

public struct StarlinkStatus: Equatable, Sendable {
    public var popPingLatencyMilliseconds: Double?
    public var telemetry: StarlinkTelemetry

    public init(popPingLatencyMilliseconds: Double?, telemetry: StarlinkTelemetry) {
        self.popPingLatencyMilliseconds = popPingLatencyMilliseconds
        self.telemetry = telemetry
    }

    public var isConnected: Bool {
        guard let state = telemetry.state?.trimmingCharacters(in: .whitespacesAndNewlines),
              !state.isEmpty else {
            return popPingLatencyMilliseconds != nil
        }
        return state.caseInsensitiveCompare("CONNECTED") == .orderedSame
    }
}

public protocol StarlinkStatusFetching: Sendable {
    func fetchStatus(host: HostConfig) async throws -> StarlinkStatus
}

public protocol StarlinkGRPCTransport: Sendable {
    func unary(path: String, requestFrame: Data, host: HostConfig) async throws -> Data
}

public enum StarlinkStatusFetchError: Error, Equatable, Sendable {
    case unavailable
    case invalidStatus
    case responseTooLarge
    case timedOut
}

public struct StarlinkStatusGRPCClient: StarlinkStatusFetching {
    public static let statusPath = "/SpaceX.API.Device.Device/Handle"

    private let transport: any StarlinkGRPCTransport
    private let codec: StarlinkProtobufCodec

    public init(
        transport: any StarlinkGRPCTransport,
        codec: StarlinkProtobufCodec = StarlinkProtobufCodec()
    ) {
        self.transport = transport
        self.codec = codec
    }

    public func fetchStatus(host: HostConfig) async throws -> StarlinkStatus {
        let response = try await transport.unary(
            path: Self.statusPath,
            requestFrame: codec.makeGetStatusGRPCFrame(),
            host: host
        )
        return try codec.decodeStatus(fromGRPCFrame: response)
    }
}

public struct StarlinkProbe: PingProbe {
    private let statusClient: any StarlinkStatusFetching

    public init(statusClient: any StarlinkStatusFetching) {
        self.statusClient = statusClient
    }

    public func measure(_ host: HostConfig) async -> PingResult {
        do {
            let status = try await statusClient.fetchStatus(host: host)
            let metadata = ProbeMetadata(note: status.telemetry.noteSummary, starlink: status.telemetry)
            guard status.isConnected,
                  let latencyMilliseconds = status.popPingLatencyMilliseconds,
                  latencyMilliseconds >= 0 else {
                return .failure(
                    hostID: host.id,
                    reason: .networkUnavailable,
                    metadata: metadata
                ).withHostMetadata(from: host)
            }
            return .success(
                hostID: host.id,
                latency: .milliseconds(latencyMilliseconds),
                metadata: metadata
            ).withHostMetadata(from: host)
        } catch is CancellationError {
            return .failure(hostID: host.id, reason: .cancelled).withHostMetadata(from: host)
        } catch {
            return .failure(
                hostID: host.id,
                reason: .starlinkUnavailable,
                metadata: ProbeMetadata(note: "Starlink dish status unavailable")
            ).withHostMetadata(from: host)
        }
    }
}

final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return false }
        resumed = true
        return true
    }
}

public struct ProcessICMPProbe: PingProbe {
    public init() {}

    public func measure(_ host: HostConfig) async -> PingResult {
        #if APPSTORE || !os(macOS)
        return .failure(hostID: host.id, reason: .icmpUnavailable).withHostMetadata(from: host)
        #else
        let start = ContinuousClock.now
        do {
            let result = try await AsyncProcess.run(
                executablePath: "/sbin/ping",
                arguments: ["-c", "1", "-W", "\(max(1, Int(host.timeout.seconds.rounded())))", host.address],
                timeout: host.timeout + .seconds(1)
            )
            if result.terminationStatus == 0 {
                return .success(hostID: host.id, latency: start.duration(to: .now)).withHostMetadata(from: host)
            }
            return .failure(hostID: host.id, reason: .unknown).withHostMetadata(from: host)
        } catch {
            return .failure(hostID: host.id, reason: .icmpUnavailable).withHostMetadata(from: host)
        }
        #endif
    }
}

private extension NWError {
    var failureReason: FailureReason {
        let text = localizedDescription.lowercased()
        if text.contains("dns") || text.contains("name") {
            return .dnsFailure
        }
        if text.contains("refused") {
            return .connectionRefused
        }
        if text.contains("network") {
            return .networkUnavailable
        }
        return .unknown
    }
}

private extension Error {
    var failureReason: FailureReason {
        if let urlError = self as? URLError {
            switch urlError.code {
            case .timedOut:
                return .timeout
            case .cannotFindHost, .dnsLookupFailed:
                return .dnsFailure
            case .cannotConnectToHost, .networkConnectionLost:
                return .networkUnavailable
            case .cancelled:
                return .cancelled
            default:
                return .unknown
            }
        }
        return .unknown
    }
}
