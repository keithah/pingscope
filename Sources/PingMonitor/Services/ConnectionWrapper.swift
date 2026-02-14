import Foundation
import Network

struct ConnectionWrapper: Sendable {
    private final class ResumeState: @unchecked Sendable {
        let lock = NSLock()
        var didResume = false
    }

    private let queue = DispatchQueue(label: "ConnectionWrapper", qos: .userInitiated)

    func measureConnection(
        host: String,
        port: UInt16,
        parameters: NWParameters
    ) async throws -> Duration {
        let startTime = ContinuousClock.now

        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw PingError.invalidHost
        }

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: endpointPort
        )
        let connection = NWConnection(to: endpoint, using: parameters)
        let resumeState = ResumeState()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.stateUpdateHandler = { state in
                    resumeState.lock.lock()
                    defer { resumeState.lock.unlock() }

                    guard !resumeState.didResume else {
                        return
                    }

                    switch state {
                    case .ready:
                        resumeState.didResume = true
                        connection.cancel()
                        continuation.resume()
                    case .failed(let error):
                        resumeState.didResume = true
                        connection.cancel()
                        continuation.resume(throwing: PingError.connectionFailed(error.localizedDescription))
                    case .cancelled:
                        resumeState.didResume = true
                        continuation.resume(throwing: PingError.cancelled)
                    case .waiting(let error):
                        resumeState.didResume = true
                        connection.cancel()
                        continuation.resume(throwing: PingError.connectionFailed(error.localizedDescription))
                    default:
                        break
                    }
                }

                connection.start(queue: queue)
            }
        } onCancel: {
            connection.cancel()
        }

        return ContinuousClock.now - startTime
    }
}
