import Foundation
@preconcurrency import Network
import PingScopeCore

struct ProbeCase {
    var name: String
    var host: HostConfig
    var expectedNote: String
}

@main
struct ProbeValidate {
    static func main() async {
        let cases = [
            ProbeCase(
                name: "TCP",
                host: HostConfig(
                    displayName: "TCP Cloudflare",
                    address: "1.1.1.1",
                    method: .tcp,
                    port: 443,
                    timeout: .seconds(3)
                ),
                expectedNote: "fresh TCP connection"
            ),
            ProbeCase(
                name: "UDP",
                host: HostConfig(
                    displayName: "UDP Cloudflare DNS",
                    address: "1.1.1.1",
                    method: .udp,
                    port: 53,
                    timeout: .seconds(3)
                ),
                expectedNote: "UDP datagram send path"
            ),
            ProbeCase(
                name: "ICMP",
                host: HostConfig(
                    displayName: "ICMP Cloudflare",
                    address: "1.1.1.1",
                    method: .icmp,
                    port: nil,
                    timeout: .seconds(3)
                ),
                expectedNote: "/sbin/ping"
            )
        ]

        let tester = HostTester(probeFactory: DefaultProbeFactory(flavor: .developerID))
        var failures = 0

        for probeCase in cases {
            let result = await tester.test(probeCase.host)
            if result.isSuccess {
                print("PASS \(probeCase.name): \(formatLatency(result.latency)) \(result.metadata.note ?? probeCase.expectedNote)")
            } else {
                failures += 1
                let reason = result.failureReason?.userMessage ?? "Unknown failure"
                print("FAIL \(probeCase.name): \(reason) \(result.metadata.note ?? "")")
            }
        }

        let starlinkCandidates = [
            starlinkHost(address: "192.168.100.1", port: 9200),
            starlinkHost(address: "192.168.1.1", port: 9000),
            starlinkHost(address: "192.168.1.1", port: 9200),
            starlinkHost(address: "192.168.8.1", port: 9000)
        ]
        var attemptedStarlink = false
        var starlinkPassed = false
        for candidate in starlinkCandidates {
            guard await isTCPReachable(host: candidate.address, port: candidate.port ?? 9200) else {
                print("SKIP Starlink \(candidate.address):\(candidate.port ?? 9200): TCP not reachable")
                continue
            }
            attemptedStarlink = true
            let result = await tester.test(candidate)
            if result.isSuccess {
                starlinkPassed = true
                print("PASS Starlink \(candidate.address):\(candidate.port ?? 9200): \(formatLatency(result.latency)) \(result.metadata.note ?? "dish status")")
                break
            } else {
                let reason = result.failureReason?.userMessage ?? "Unknown failure"
                print("FAIL Starlink \(candidate.address):\(candidate.port ?? 9200): \(reason) \(result.metadata.note ?? "")")
                if let telemetry = result.metadata.starlink {
                    print("  telemetry: \(formatStarlinkTelemetry(telemetry))")
                }
            }
        }
        if attemptedStarlink, !starlinkPassed {
            failures += 1
        } else if !attemptedStarlink {
            print("SKIP Starlink: no candidate endpoint reachable")
        }

        if failures > 0 {
            print("Probe validation failed: \(failures) failure(s).")
            exit(1)
        }

        print("Probe validation passed. UDP validates datagram send/readiness, not an echoed UDP round trip.")
    }

    private static func formatLatency(_ duration: Duration?) -> String {
        guard let duration else { return "--ms" }
        let components = duration.components
        let milliseconds = (Double(components.seconds) * 1_000.0)
            + (Double(components.attoseconds) / 1_000_000_000_000_000.0)
        return "\(Int(milliseconds.rounded()))ms"
    }

    private static func starlinkHost(address: String, port: UInt16) -> HostConfig {
        HostConfig(
            displayName: "Starlink \(address):\(port)",
            address: address,
            tier: .ispEdge,
            method: .starlink,
            port: port,
            interval: .seconds(5),
            timeout: .seconds(2),
            thresholds: LatencyThresholds(degradedMilliseconds: 150, downAfterFailures: 3)
        )
    }

    private static func formatStarlinkTelemetry(_ telemetry: StarlinkTelemetry) -> String {
        [
            "state=\(telemetry.state ?? "nil")",
            "drop=\(formatOptional(telemetry.popPingDropRate))",
            "downlink=\(formatOptional(telemetry.downlinkThroughputBps))",
            "uplink=\(formatOptional(telemetry.uplinkThroughputBps))",
            "obstructed=\(formatOptional(telemetry.fractionObstructed))",
            "uptime=\(formatOptional(telemetry.uptimeSeconds))",
            "alerts=\(telemetry.activeAlerts.joined(separator: "|"))",
            "hw=\(telemetry.hardwareVersion ?? "nil")",
            "sw=\(telemetry.softwareVersion ?? "nil")",
            "country=\(telemetry.countryCode ?? "nil")"
        ].joined(separator: " ")
    }

    private static func formatOptional(_ value: Double?) -> String {
        guard let value else { return "nil" }
        return String(value)
    }

    private static func isTCPReachable(host: String, port: UInt16, timeout: Duration = .seconds(2)) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            return false
        }
        return await ProbeValidationTCPAttempt(host: host, port: nwPort).run(timeout: timeout)
    }
}

private final class ProbeValidationTCPAttempt: @unchecked Sendable {
    private let connection: NWConnection
    private let gate = ProbeValidationGate()
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(host: String, port: NWEndpoint.Port) {
        self.connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
    }

    func run(timeout: Duration) async -> Bool {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                lock.unlock()

                connection.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        self?.finish(true)
                    case .failed, .cancelled:
                        self?.finish(false)
                    default:
                        break
                    }
                }
                connection.start(queue: .global(qos: .utility))

                let timeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    self?.finish(false)
                }
                lock.lock()
                self.timeoutTask = timeoutTask
                lock.unlock()
            }
        } onCancel: {
            finish(false)
        }
    }

    private func finish(_ result: Bool) {
        guard gate.claim() else { return }
        connection.cancel()

        lock.lock()
        let continuation = continuation
        self.continuation = nil
        let timeoutTask = timeoutTask
        self.timeoutTask = nil
        lock.unlock()

        timeoutTask?.cancel()
        continuation?.resume(returning: result)
    }
}

private final class ProbeValidationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didClaim = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didClaim else { return false }
        didClaim = true
        return true
    }
}
