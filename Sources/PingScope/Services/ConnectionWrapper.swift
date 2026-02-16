import Foundation
import Network

protocol ConnectionLifecycleTracking: Sendable {
    func register(_ connection: NWConnection) async -> UUID
    func unregister(_ id: UUID) async
}

struct ConnectionWrapper: Sendable {
    private final class ConnectionState: @unchecked Sendable {
        let lock = NSLock()
        var didResume = false
        var registrationID: UUID?
        var didUnregister = false

        func shouldResume() -> Bool {
            lock.lock()
            defer { lock.unlock() }

            guard !didResume else {
                return false
            }

            didResume = true
            return true
        }

        func setRegistrationID(_ id: UUID) {
            lock.lock()
            registrationID = id
            lock.unlock()
        }

        func takeRegistrationForUnregister() -> UUID? {
            lock.lock()
            defer { lock.unlock() }

            guard !didUnregister else {
                return nil
            }

            didUnregister = true
            return registrationID
        }
    }

    private let lifecycleTracker: (any ConnectionLifecycleTracking)?
    private let queue = DispatchQueue(label: "ConnectionWrapper", qos: .userInitiated)

    init(lifecycleTracker: (any ConnectionLifecycleTracking)? = nil) {
        self.lifecycleTracker = lifecycleTracker
    }

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
        let connectionState = ConnectionState()

        if let lifecycleTracker {
            let registrationID = await lifecycleTracker.register(connection)
            connectionState.setRegistrationID(registrationID)
        }

        @Sendable func unregisterIfNeeded() {
            guard
                let lifecycleTracker,
                let registrationID = connectionState.takeRegistrationForUnregister()
            else {
                return
            }

            Task {
                await lifecycleTracker.unregister(registrationID)
            }
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.stateUpdateHandler = { state in
                    guard connectionState.shouldResume() else {
                        return
                    }

                    switch state {
                    case .ready:
                        unregisterIfNeeded()
                        connection.cancel()
                        continuation.resume()
                    case .failed(let error):
                        unregisterIfNeeded()
                        connection.cancel()
                        continuation.resume(throwing: PingError.connectionFailed(error.localizedDescription))
                    case .cancelled:
                        unregisterIfNeeded()
                        continuation.resume(throwing: PingError.cancelled)
                    case .waiting(let error):
                        unregisterIfNeeded()
                        connection.cancel()
                        continuation.resume(throwing: PingError.connectionFailed(error.localizedDescription))
                    default:
                        break
                    }
                }

                connection.start(queue: queue)
            }
        } onCancel: {
            unregisterIfNeeded()
            connection.cancel()
        }

        return ContinuousClock.now - startTime
    }
}
