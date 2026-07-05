import Foundation

actor AsyncPermitPool {
    private var availablePermits: Int
    private var waiters: [Waiter] = []
    private var waiterIndexByID: [UUID: Int] = [:]
    private var waiterStartIndex = 0

    private struct Waiter {
        var id: UUID
        var continuation: CheckedContinuation<Void, Error>
        var isCancelled = false
    }

    init(permits: Int) {
        self.availablePermits = permits
    }

    func acquire() async throws {
        try Task.checkCancellation()
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiterIndexByID[id] = waiters.count
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await cancelWaiter(id: id) }
        }
    }

    func release() {
        compactWaitersIfNeeded()
        while waiterStartIndex < waiters.count {
            let waiter = waiters[waiterStartIndex]
            waiterStartIndex += 1
            if waiter.isCancelled {
                waiterIndexByID.removeValue(forKey: waiter.id)
                compactWaitersIfNeeded()
                continue
            }
            waiterIndexByID.removeValue(forKey: waiter.id)
            waiter.continuation.resume()
            compactWaitersIfNeeded()
            return
        }
        availablePermits += 1
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiterIndexByID[id], index >= waiterStartIndex else { return }
        guard !waiters[index].isCancelled else { return }
        waiters[index].isCancelled = true
        waiterIndexByID.removeValue(forKey: id)
        let waiter = waiters[index]
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func compactWaitersIfNeeded() {
        if waiterStartIndex == waiters.count {
            waiters.removeAll(keepingCapacity: true)
            waiterIndexByID.removeAll(keepingCapacity: true)
            waiterStartIndex = 0
        } else if waiterStartIndex > 32, waiterStartIndex * 2 > waiters.count {
            waiters = Array(waiters[waiterStartIndex...])
            waiterIndexByID = Dictionary(uniqueKeysWithValues: waiters.enumerated().map { index, waiter in
                (waiter.id, index)
            })
            waiterStartIndex = 0
        }
    }
}

actor AsyncPermitLease {
    private let pool: AsyncPermitPool
    private var isReleased = false

    init(pool: AsyncPermitPool) {
        self.pool = pool
    }

    func release() async {
        guard !isReleased else { return }
        isReleased = true
        await pool.release()
    }
}
