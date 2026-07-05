import Foundation
@preconcurrency import Network

public enum BuildFlavor: Sendable {
    case appStore
    case developerID

    public static var current: BuildFlavor { detected }

    /// The `APPSTORE` compilation condition is set on the Xcode app targets,
    /// but target-level `SWIFT_ACTIVE_COMPILATION_CONDITIONS` never propagates
    /// into Swift package targets -- so when Xcode Cloud archives the App Store
    /// scheme, this package compiles without the flag and `#if APPSTORE` alone
    /// would misreport the flavor (and offer ICMP, which the sandbox cannot
    /// deliver). Detect the store flavor at runtime instead via ``detect``.
    private static let detected: BuildFlavor = {
        #if APPSTORE
        let hasCompileFlag = true
        #else
        let hasCompileFlag = false
        #endif
        return detect(
            hasCompileFlag: hasCompileFlag,
            bundleURL: Bundle.main.bundleURL,
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            sandboxContainerID: ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"]
        )
    }()

    /// Flavor detection with injectable inputs, in priority order: the compile
    /// flag when the build system managed to set it; a store receipt in the
    /// bundle -- both App Store ("receipt") and TestFlight ("sandboxReceipt")
    /// installs carry one (macOS keeps it under `Contents/_MASReceipt/`, iOS
    /// under `StoreKit/`), while Developer ID and local builds have none; and
    /// finally the app-sandbox container, because a sandboxed process cannot
    /// use ICMP either way, so a store build whose receipt has not materialized
    /// yet must still report the App Store flavor rather than offer methods
    /// that cannot work.
    static func detect(
        hasCompileFlag: Bool,
        bundleURL: URL,
        fileExists: (URL) -> Bool,
        sandboxContainerID: String?
    ) -> BuildFlavor {
        if hasCompileFlag {
            return .appStore
        }
        let receiptCandidates = [
            "Contents/_MASReceipt/receipt",
            "Contents/_MASReceipt/sandboxReceipt",
            "StoreKit/receipt",
            "StoreKit/sandboxReceipt"
        ].map { bundleURL.appendingPathComponent($0) }
        if receiptCandidates.contains(where: fileExists) {
            return .appStore
        }
        if sandboxContainerID != nil {
            return .appStore
        }
        return .developerID
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
        // Cancellation can be delivered before `connection.start()` runs (the
        // onCancel handler fires immediately, ahead of the operation block, when
        // the task is already cancelled). A never-started connection never emits
        // a state update, so relying on the state handler alone would leak the
        // continuation and hang the scheduler's stop(). The relay guarantees the
        // continuation is resolved no matter when cancellation lands.
        let cancellationRelay = ProbeCancellationRelay()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let gate = ContinuationGate()

                let finish: @Sendable (PingResult) -> Void = { result in
                    guard gate.claim() else { return }
                    connection.cancel()
                    continuation.resume(returning: result.withHostMetadata(from: host))
                }

                let finishTerminalError: @Sendable (NWError) -> Void = { error in
                    let reason = error.failureReason
                    // A TCP RST proves the host is reachable at L3. Gateway-tier
                    // hosts (the auto-detected default gateway in particular) are
                    // probed for reachability, not for a listening service, and
                    // most routers do not serve the probed port -- so a refusal
                    // there is a successful round trip, not an outage.
                    if reason == .connectionRefused, parameters == .tcp, host.effectiveNetworkTier == .localGateway {
                        finish(.success(
                            hostID: host.id,
                            latency: start.duration(to: .now),
                            metadata: ProbeMetadata(note: "TCP connection refused; host reachable")
                        ))
                    } else {
                        finish(.failure(hostID: host.id, reason: reason, metadata: ProbeMetadata(note: error.localizedDescription)))
                    }
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
                    case .waiting(let error):
                        // NWConnection parks refused connections in .waiting and
                        // retries on network changes. For a one-shot latency probe
                        // a refusal is a terminal answer; letting it sit burns the
                        // full timeout and misreports the reason. Anything else
                        // (ENETDOWN/EHOSTUNREACH during a Wi-Fi handoff or wake
                        // from sleep) is often transient, so let the connection
                        // keep retrying within the probe timeout rather than
                        // report an instant false failure for every host.
                        if error.failureReason == .connectionRefused {
                            finishTerminalError(error)
                        }
                    case .failed(let error):
                        finishTerminalError(error)
                    case .cancelled:
                        finish(.failure(hostID: host.id, reason: .cancelled))
                    default:
                        break
                    }
                }

                connection.start(queue: .global(qos: .utility))
                // Installed after start() so a pre-start cancellation never calls
                // start() on an already-cancelled connection.
                cancellationRelay.install {
                    finish(.failure(hostID: host.id, reason: .cancelled))
                }
            }
        } onCancel: {
            cancellationRelay.cancel()
        }
    }
}

/// Bridges `withTaskCancellationHandler`'s `onCancel` (which may fire before,
/// during, or after the operation body) to a handler that is only known once the
/// body has set the probe up. Whichever of `install`/`cancel` happens second
/// invokes the handler exactly once.
final class ProbeCancellationRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private var isCancelled = false

    func install(_ newHandler: @escaping @Sendable () -> Void) {
        lock.lock()
        let fireImmediately = isCancelled
        if !fireImmediately {
            handler = newHandler
        }
        lock.unlock()
        if fireImmediately {
            newHandler()
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let installed = handler
        handler = nil
        lock.unlock()
        installed?()
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
        let race = AsyncFirstResult<PingResult>()
        let measurementTask = Task {
            await race.finish(await wrapped.measure(host))
        }
        let timeoutTask = Task {
            do {
                try await Task.sleep(for: host.timeout)
                await race.finish(.failure(hostID: host.id, reason: .timeout).withHostMetadata(from: host))
            } catch {
                await race.finish(.failure(hostID: host.id, reason: .cancelled).withHostMetadata(from: host))
            }
        }

        let result = await withTaskCancellationHandler {
            await race.value()
        } onCancel: {
            measurementTask.cancel()
            timeoutTask.cancel()
            Task {
                await race.finish(.failure(hostID: host.id, reason: .cancelled).withHostMetadata(from: host))
            }
        }
        measurementTask.cancel()
        timeoutTask.cancel()
        return result
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
                  // Non-finite values pass `>= 0` (infinity) and would trap in
                  // Duration.milliseconds; the dish payload is untrusted input.
                  latencyMilliseconds.isFinite,
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
                // macOS `ping -W` is milliseconds, not seconds.
                arguments: ["-c", "1", "-W", "\(max(1, Int(host.timeout.milliseconds.rounded())))", "--", host.address],
                timeout: host.timeout + .seconds(1)
            )
            if result.terminationStatus == 0 {
                let output = String(data: result.standardOutput, encoding: .utf8) ?? ""
                if let milliseconds = Self.parseRoundTripMilliseconds(from: output) {
                    return .success(
                        hostID: host.id,
                        latency: .milliseconds(milliseconds),
                        metadata: ProbeMetadata(note: "ICMP echo reply")
                    ).withHostMetadata(from: host)
                }
                // ping exited 0 but the reply line was unparseable; the process
                // lifetime is the only (over-)estimate left.
                return .success(hostID: host.id, latency: start.duration(to: .now)).withHostMetadata(from: host)
            }
            return .failure(hostID: host.id, reason: .unknown).withHostMetadata(from: host)
        } catch {
            return .failure(hostID: host.id, reason: .icmpUnavailable).withHostMetadata(from: host)
        }
        #endif
    }

    /// Extracts the reply RTT from `ping` stdout (`... time=12.345 ms`).
    ///
    /// The child process's wall-clock lifetime is dominated by fork/exec, DNS
    /// resolution, and teardown, so it is not usable as a latency measurement.
    public static func parseRoundTripMilliseconds(from output: String) -> Double? {
        for line in output.split(separator: "\n") {
            guard let range = line.range(of: "time=") else { continue }
            let value = line[range.upperBound...].prefix { $0.isNumber || $0 == "." }
            guard let milliseconds = Double(value), milliseconds.isFinite, milliseconds >= 0 else { continue }
            return milliseconds
        }
        return nil
    }
}

private extension NWError {
    var failureReason: FailureReason {
        // Prefer the typed error over the localized (and locale-dependent) text.
        if case .posix(let code) = self {
            switch code {
            case .ECONNREFUSED: return .connectionRefused
            case .ETIMEDOUT: return .timeout
            case .EHOSTUNREACH, .ENETUNREACH, .ENETDOWN: return .networkUnavailable
            default: break
            }
        }
        if case .dns = self {
            return .dnsFailure
        }
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
