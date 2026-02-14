import Foundation
import Network

actor PingService {
    private let connectionWrapper = ConnectionWrapper()
    private let defaultTimeout: Duration = .seconds(3)

    func ping(host: Host) async -> PingResult {
        await ping(
            address: host.address,
            port: host.port,
            protocolType: host.protocolType,
            timeout: host.timeout
        )
    }

    func ping(
        address: String,
        port: UInt16,
        protocolType: Host.ProtocolType = .tcp,
        timeout: Duration? = nil
    ) async -> PingResult {
        let effectiveTimeout = timeout ?? defaultTimeout
        let parameters: NWParameters = protocolType == .tcp ? .tcp : .udp

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
