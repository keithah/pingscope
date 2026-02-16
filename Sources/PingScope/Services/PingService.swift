import Foundation
import Network

actor PingService {
    private let connectionWrapper = ConnectionWrapper()
    private let icmpPinger = ICMPPinger()
    private let defaultTimeout: Duration = .seconds(3)

    func ping(host: Host) async -> PingResult {
        let effectiveTimeout = host.timeoutOverride ?? defaultTimeout

        switch host.pingMethod {
        case .tcp, .udp:
            return await ping(
                address: host.address,
                port: host.port,
                pingMethod: host.pingMethod,
                timeout: effectiveTimeout
            )
        case .icmp:
            return await pingICMP(host: host, timeout: effectiveTimeout)
        }
    }

    func ping(
        address: String,
        port: UInt16,
        pingMethod: PingMethod = .tcp,
        timeout: Duration? = nil
    ) async -> PingResult {
        let effectiveTimeout = timeout ?? defaultTimeout

        switch pingMethod {
        case .tcp:
            return await ping(
                address: address,
                port: port,
                parameters: .tcp,
                timeout: effectiveTimeout
            )
        case .udp:
            return await ping(
                address: address,
                port: port,
                parameters: .udp,
                timeout: effectiveTimeout
            )
        case .icmp:
            return .failure(
                host: address,
                port: port,
                error: .connectionFailed("Use ping(host:) for ICMP pings")
            )
        }
    }

    private func pingICMP(host: Host, timeout: Duration) async -> PingResult {
        do {
            let latency = try await icmpPinger.ping(host: host.address, timeout: timeout)
            return .success(host: host.address, port: 0, latency: latency)
        } catch let error as PingError {
            return .failure(host: host.address, port: 0, error: error)
        } catch is CancellationError {
            return .failure(host: host.address, port: 0, error: .cancelled)
        } catch {
            return .failure(host: host.address, port: 0, error: .connectionFailed(error.localizedDescription))
        }
    }

    private func ping(
        address: String,
        port: UInt16,
        parameters: NWParameters,
        timeout: Duration
    ) async -> PingResult {
        let effectiveTimeout = timeout

        do {
            let latency = try await withThrowingTaskGroup(of: Duration.self) { group in
                group.addTask {
                    try await self.connectionWrapper.measureConnection(
                        host: address,
                        port: port,
                        parameters: parameters
                    )
                }

                group.addTask {
                    try await Task.sleep(for: effectiveTimeout)
                    throw PingError.timeout
                }

                defer { group.cancelAll() }

                guard let result = try await group.next() else {
                    throw PingError.cancelled
                }

                return result
            }

            return .success(host: address, port: port, latency: latency)
        } catch let error as PingError {
            return .failure(host: address, port: port, error: error)
        } catch is CancellationError {
            return .failure(host: address, port: port, error: .cancelled)
        } catch {
            return .failure(host: address, port: port, error: .connectionFailed(error.localizedDescription))
        }
    }

    func pingAll(hosts: [Host], maxConcurrent: Int = 10) async -> [PingResult] {
        guard !hosts.isEmpty else {
            return []
        }

        var results: [UUID: PingResult] = [:]

        await withTaskGroup(of: (UUID, PingResult).self) { group in
            var index = 0

            for _ in 0..<min(maxConcurrent, hosts.count) {
                let host = hosts[index]
                index += 1
                group.addTask {
                    let result = await self.ping(host: host)
                    return (host.id, result)
                }
            }

            for await (id, result) in group {
                results[id] = result

                if index < hosts.count {
                    let host = hosts[index]
                    index += 1
                    group.addTask {
                        let result = await self.ping(host: host)
                        return (host.id, result)
                    }
                }
            }
        }

        return hosts.compactMap { results[$0.id] }
    }
}
