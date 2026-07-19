import Foundation

/// A manually advanced `Clock` for deterministic tests: time only moves when
/// the test calls `advance(by:)`, and `waitForSleepers(atLeast:)` lets the test
/// synchronize with code that has reached a `sleep`, instead of racing real
/// wall-clock delays against the code under test.
final class ManualClock: Clock, @unchecked Sendable {
    enum WaitTimeout: Error, Equatable {
        case timedOut(count: Int, observed: Int)
    }

    struct Instant: InstantProtocol, Comparable, Hashable {
        var offset: Duration

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

    private struct Waiter {
        let id: UUID
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var currentInstant = Instant(offset: .zero)
    private var waiters: [Waiter] = []
    private var cancelledSleeps: Set<UUID> = []
    private struct SleeperObserver {
        let id: UUID
        let threshold: Int
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var sleeperObservers: [SleeperObserver] = []

    /// Anchor for `currentDate`, so wall-clock reads under test move in
    /// lockstep with the clock.
    let baseDate: Date

    init(baseDate: Date = Date(timeIntervalSince1970: 1_000_000)) {
        self.baseDate = baseDate
    }

    var now: Instant {
        lock.lock()
        defer { lock.unlock() }
        return currentInstant
    }

    var minimumResolution: Duration { .zero }

    var durationUntilNextSleepDeadline: Duration? {
        lock.lock()
        defer { lock.unlock() }
        guard let deadline = waiters.map(\.deadline).min() else { return nil }
        return currentInstant.duration(to: deadline)
    }

    /// The wall-clock equivalent of `now`, for injecting as a date provider.
    var currentDate: Date {
        lock.lock()
        defer { lock.unlock() }
        let components = currentInstant.offset.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        return baseDate.addingTimeInterval(seconds)
    }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                lock.lock()
                if cancelledSleeps.remove(id) != nil {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if deadline <= currentInstant {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                waiters.append(Waiter(id: id, deadline: deadline, continuation: continuation))
                let observers = dueObserversLocked()
                lock.unlock()
                observers.forEach { $0.resume() }
            }
        } onCancel: {
            lock.lock()
            if let index = waiters.firstIndex(where: { $0.id == id }) {
                let waiter = waiters.remove(at: index)
                lock.unlock()
                waiter.continuation.resume(throwing: CancellationError())
            } else {
                // Cancellation delivered before the sleep registered.
                cancelledSleeps.insert(id)
                lock.unlock()
            }
        }
    }

    /// Moves time forward and resumes every sleeper whose deadline has passed.
    func advance(by duration: Duration) {
        lock.lock()
        currentInstant = currentInstant.advanced(by: duration)
        let due = waiters.filter { $0.deadline <= currentInstant }
        waiters.removeAll { $0.deadline <= currentInstant }
        lock.unlock()
        due.forEach { $0.continuation.resume() }
    }

    /// Suspends until at least `count` tasks are blocked in `sleep` on this
    /// clock. This is the synchronization point that replaces "sleep a while
    /// and hope the loop got there".
    func waitForSleepers(atLeast count: Int, timeout: Duration = .seconds(1)) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                lock.lock()
                if waiters.count >= count {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                sleeperObservers.append(SleeperObserver(id: id, threshold: count, continuation: continuation))
                lock.unlock()

                Task { [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    self?.timeOutSleeperObserver(id: id, count: count)
                }
            }
        } onCancel: {
            cancelSleeperObserver(id: id)
        }
    }

    private func timeOutSleeperObserver(id: UUID, count: Int) {
        lock.lock()
        guard let index = sleeperObservers.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            return
        }
        let observer = sleeperObservers.remove(at: index)
        let observed = waiters.count
        lock.unlock()
        observer.continuation.resume(throwing: WaitTimeout.timedOut(count: count, observed: observed))
    }

    private func cancelSleeperObserver(id: UUID) {
        lock.lock()
        guard let index = sleeperObservers.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            return
        }
        let observer = sleeperObservers.remove(at: index)
        lock.unlock()
        observer.continuation.resume(throwing: CancellationError())
    }

    private func dueObserversLocked() -> [CheckedContinuation<Void, any Error>] {
        let due = sleeperObservers.filter { waiters.count >= $0.threshold }
        sleeperObservers.removeAll { waiters.count >= $0.threshold }
        return due.map(\.continuation)
    }
}
