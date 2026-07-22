import Foundation
@testable import PingScopeCore

final class ManualClock: Clock, @unchecked Sendable {
    enum WaitTimeout: Error, Equatable {
        case timedOut(count: Int, observed: Int)
    }

    struct Instant: InstantProtocol, Comparable {
        let offset: Duration

        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct Sleeper {
        let id: UUID
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct SleeperObserver {
        let id: UUID
        let threshold: Int
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var currentInstant = Instant(offset: .zero)
    private var sleepers: [Sleeper] = []
    private var cancelledSleeps: Set<UUID> = []
    private var sleeperObservers: [SleeperObserver] = []

    var now: Instant {
        lock.withLock { currentInstant }
    }

    var minimumResolution: Duration { .zero }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let observers: [CheckedContinuation<Void, any Error>] = lock.withLock {
                    if cancelledSleeps.remove(id) != nil {
                        continuation.resume(throwing: CancellationError())
                        return []
                    }
                    if deadline <= currentInstant {
                        continuation.resume()
                        return []
                    }
                    sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return dueObserversLocked()
                }
                observers.forEach { $0.resume() }
            }
        } onCancel: {
            let sleeper: Sleeper? = lock.withLock {
                if let index = sleepers.firstIndex(where: { $0.id == id }) {
                    return sleepers.remove(at: index)
                }
                cancelledSleeps.insert(id)
                return nil
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(by duration: Duration) {
        let due: [Sleeper] = lock.withLock {
            currentInstant = currentInstant.advanced(by: duration)
            let due = sleepers.filter { $0.deadline <= currentInstant }
            sleepers.removeAll { $0.deadline <= currentInstant }
            return due
        }
        due.forEach { $0.continuation.resume() }
    }

    func waitForSleepers(atLeast count: Int, timeout: Duration = .seconds(1)) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let shouldScheduleTimeout: Bool = lock.withLock {
                    if sleepers.count >= count {
                        continuation.resume()
                        return false
                    }
                    sleeperObservers.append(
                        SleeperObserver(id: id, threshold: count, continuation: continuation)
                    )
                    return true
                }
                if shouldScheduleTimeout {
                    Task { [weak self] in
                        try? await Task.sleep(for: timeout)
                        self?.timeOutSleeperObserver(id: id, count: count)
                    }
                }
            }
        } onCancel: {
            cancelSleeperObserver(id: id)
        }
    }

    private func timeOutSleeperObserver(id: UUID, count: Int) {
        let timedOut: (CheckedContinuation<Void, any Error>, Int)? = lock.withLock {
            guard let index = sleeperObservers.firstIndex(where: { $0.id == id }) else { return nil }
            return (sleeperObservers.remove(at: index).continuation, sleepers.count)
        }
        timedOut?.0.resume(throwing: WaitTimeout.timedOut(count: count, observed: timedOut?.1 ?? 0))
    }

    private func cancelSleeperObserver(id: UUID) {
        let continuation: CheckedContinuation<Void, any Error>? = lock.withLock {
            guard let index = sleeperObservers.firstIndex(where: { $0.id == id }) else { return nil }
            return sleeperObservers.remove(at: index).continuation
        }
        continuation?.resume(throwing: CancellationError())
    }

    private func dueObserversLocked() -> [CheckedContinuation<Void, any Error>] {
        let due = sleeperObservers.filter { sleepers.count >= $0.threshold }
        sleeperObservers.removeAll { sleepers.count >= $0.threshold }
        return due.map(\.continuation)
    }
}

actor RecordingProbe: PingProbe {
    private var results: [PingResult]
    private(set) var measurementCount = 0

    init(results: [PingResult]) {
        self.results = results
    }

    func measure(_ host: HostConfig) async -> PingResult {
        measurementCount += 1
        let index = min(measurementCount - 1, results.count - 1)
        return results[index].withHostMetadata(from: host)
    }
}

struct StaticProbeFactory: ProbeFactory {
    let probe: RecordingProbe

    func makeProbe(for method: PingMethod) async -> any PingProbe {
        probe
    }
}

struct NoopProbeFactory: ProbeFactory {
    func makeProbe(for method: PingMethod) async -> any PingProbe {
        NoopProbe()
    }
}

private struct NoopProbe: PingProbe {
    func measure(_ host: HostConfig) async -> PingResult {
        .failure(hostID: host.id, reason: .cancelled).withHostMetadata(from: host)
    }
}

struct StubStarlinkStatusClient: StarlinkStatusFetching {
    let status: StarlinkStatus

    func fetchStatus(host: HostConfig) async throws -> StarlinkStatus {
        status
    }
}
